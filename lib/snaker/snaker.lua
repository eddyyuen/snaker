local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort
local pcall = pcall
local require = require
local config_loader = require("snaker.utils.config_loader")
local utils = require("snaker.utils.utils")
local dao = require("snaker.store.dao")
local ev = require ("resty.worker.events")
local stringy = require("snaker.utils.stringy")


local HEADERS = {
    PROXY_LATENCY = "X-Orange-Proxy-Latency",
    UPSTREAM_LATENCY = "X-Orange-Upstream-Latency",
}
local loaded_plugins = {}
local function load_node_plugins(config, store)
    ngx.log(ngx.DEBUG, "Discovering used plugins")

    local sorted_plugins = {}
    local plugins = config.plugins

    for _, v in ipairs(plugins) do
        local loaded, plugin_handler = utils.load_module_if_exists("snaker.plugins." .. v .. ".handler")
        if not loaded then
            ngx.log(ngx.WARN, "The following plugin is not installed or has no handler: " .. v)
        else
            ngx.log(ngx.DEBUG, "Loading plugin: " .. v)
            table_insert(sorted_plugins, {
                name = v,
                handler = plugin_handler(store),
            })
        end
    end

    table_sort(sorted_plugins, function(a, b)
        local priority_a = a.handler.PRIORITY or 0
        local priority_b = b.handler.PRIORITY or 0
        return priority_a > priority_b
    end)

    return sorted_plugins
end

-- ms
local function now()
    return ngx.now() * 1000
end

local Snaker = {}

local function init(options)
    options = options or {}
    local store, config
    local status, err = pcall(function()
        local conf_file_path = options.config
        
        config,f = config_loader.load(conf_file_path)
        store = require("snaker.store.mysql_store")(config.store_mysql)

        loaded_plugins = load_node_plugins(config, store)
        ngx.update_time()
        config.gateway_start_at = ngx.now()
    end)

    if not status or err then
        ngx.log(ngx.ERR, "Startup error: " .. err)
        os.exit(1)
    end

    local consul = require("snaker.plugins.consul_balancer.consul_balancer")
    consul.set_shared_dict_name("consul_upstream", "consul_upstream_watch")
    Snaker.data = {
        store = store,
        config = config,
        consul = consul
    }

    -- init dns_client
    -- assert(dns_client.init())

    return config, store

end


local function init_worker()
    -- 仅在 init_worker 阶段调用，初始化随机因子，仅允许调用一次
    --  math.randomseed()

    

    -- 初始化定时器，清理计数器等
    if Snaker.data and Snaker.data.store and Snaker.data.config.store == "mysql" then
        local ok, err = ngx.timer.at(0, function(premature, store, config)
            local available_plugins = config.plugins
            for _, v in ipairs(available_plugins) do
                local load_success = dao.load_data_by_mysql(store, v)
                if not load_success then
                    os.exit(1)
                end
                
                if v == "consul_balancer" then
                    for ii,p in ipairs(loaded_plugins) do
                        if v == p.name then
                            p.handler.db_ready()
                        end
                    end
                end
            end
        end, Snaker.data.store, Snaker.data.config)

        if not ok then
            ngx.log(ngx.ERR, "failed to create the timer: ", err)
            return os.exit(1)
        end
    end

    for _, plugin in ipairs(loaded_plugins) do
    plugin.handler:init_worker()
    end

    -- 注册事件回调，更新本地LRUCACHE缓存
    
    local handler = function(data, event, source, pid)
        local worker_id = tostring(ngx.worker.pid())
        ngx.log(ngx.ERR,"worker_id:"..worker_id.."source:"..source..",event:"..event..",pid:"..pid)
        if source ~= worker_id then
            if event =="update_local_meta" then
                dao.update_local_meta(data, Snaker.data.store)
            end
            if event =="update_local_selectors" then
                dao.update_local_selectors(data, Snaker.data.store)
            end
            if event =="update_local_selector_rules" then
                local tmp = stringy.split(data, ",")
                dao.update_local_selector_rules(tmp[1], Snaker.data.store,tmp[2])
            end
        end
        
    end

    ev.register(handler)

    local ok, err = ev.configure {
        shm = "process_events", -- defined by "lua_shared_dict"
        timeout = 2,            -- life time of unique event data in shm
        interval = 1,           -- poll interval (seconds)

        wait_interval = 0.010,  -- wait before retry fetching event data
        wait_max = 0.5,         -- max wait time before discarding event
        shm_retries = 5,        -- retries for shm fragmentation (no memory)
    }
    if not ok then
        ngx.log(ngx.ERR, "failed to start event system: ", err)
        return
    end
end


local function init_cookies()
    ngx.ctx.__cookies__ = nil

    local COOKIE, err = ck:new()
    if not err and COOKIE then
        ngx.ctx.__cookies__ = COOKIE
    end
end

local function redirect()
    ngx.ctx.ORANGE_REDIRECT_START = now()

    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:redirect()
    end

    local now_time = now()
    ngx.ctx.ORANGE_REDIRECT_TIME = now_time - ngx.ctx.ORANGE_REDIRECT_START
    ngx.ctx.ORANGE_REDIRECT_ENDED_AT = now_time
end

local function rewrite()
    ngx.ctx.ORANGE_REWRITE_START = now()

    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:rewrite()
    end

    local now_time = now()
    ngx.ctx.ORANGE_REWRITE_TIME = now_time - ngx.ctx.ORANGE_REWRITE_START
    ngx.ctx.ORANGE_REWRITE_ENDED_AT = now_time
end

local function access()
    ngx.ctx.ORANGE_ACCESS_START = now()

    for _, plugin in ipairs(loaded_plugins) do
        if not ngx.ctx.SNAKER_CANCEL or ngx.ctx.SNAKER_CANCEL == false then
            plugin.handler:access()
        end
    end
    if ngx.var.upstream_scheme == '' then
        ngx.var.upstream_scheme = "http://"
    end
    if ngx.var.upstream_url == '' then
        ngx.var.upstream_url = "default_upstream"
    end
    local now_time = now()
    ngx.ctx.ORANGE_ACCESS_TIME = now_time - ngx.ctx.ORANGE_ACCESS_START
    ngx.ctx.ORANGE_ACCESS_ENDED_AT = now_time
    ngx.ctx.ORANGE_PROXY_LATENCY = now_time - ngx.req.start_time() * 1000
    ngx.ctx.ACCESSED = true

   
end

local function balancer()
    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:balancer()
    end
end

local function header_filter()
    if ngx.ctx.ACCESSED then
        local now_time = now()
        ngx.ctx.ORANGE_WAITING_TIME = now_time - ngx.ctx.ORANGE_ACCESS_ENDED_AT -- time spent waiting for a response from upstream
        ngx.ctx.ORANGE_HEADER_FILTER_STARTED_AT = now_time
    end

    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:header_filter()
    end

    if ngx.ctx.ACCESSED then
        ngx.header[HEADERS.UPSTREAM_LATENCY] = ngx.ctx.ORANGE_WAITING_TIME
        ngx.header[HEADERS.PROXY_LATENCY] = ngx.ctx.ORANGE_PROXY_LATENCY
    end
end

local function body_filter()
    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:body_filter()
    end

    if ngx.ctx.ACCESSED then
        if ngx.ctx.ORANGE_HEADER_FILTER_STARTED_AT == nil then
            ngx.ctx.ORANGE_HEADER_FILTER_STARTED_AT = 0
        end
        ngx.ctx.ORANGE_RECEIVE_TIME = now() - ngx.ctx.ORANGE_HEADER_FILTER_STARTED_AT
    end
end

local function log()
    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:log()
    end
end


Snaker.init = init
Snaker.init_worker = init_worker
Snaker.ininit_cookiesit = init_cookies
Snaker.redirect = redirect
Snaker.rewrite = rewrite
Snaker.access = access
Snaker.balancer = balancer
Snaker.header_filter = header_filter
Snaker.body_filter = body_filter
Snaker.log = log

return Snaker

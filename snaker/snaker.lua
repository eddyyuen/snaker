local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort
local pcall = pcall
local require = require
local config_loader = require("snaker.utils.config_loader")
local utils = require("snaker.utils.utils")
local dao = require("snaker.store.dao")


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

local RestyGateway = {}

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

    -- local consul = require("orange.plugins.consul_balancer.consul_balancer")
    -- consul.set_shared_dict_name("consul_upstream", "consul_upstream_watch")
    RestyGateway.data = {
        store = store,
        config = config,
        -- consul = consul
    }

    -- init dns_client
    -- assert(dns_client.init())

    return config, store

end


local function init_worker()
    -- 仅在 init_worker 阶段调用，初始化随机因子，仅允许调用一次
    -- math.randomseed()

    -- 初始化定时器，清理计数器等
    if RestyGateway.data and RestyGateway.data.store and RestyGateway.data.config.store == "mysql" then
        local ok, err = ngx.timer.at(0, function(premature, store, config)
            local available_plugins = config.plugins
            for _, v in ipairs(available_plugins) do
                local load_success = dao.load_data_by_mysql(store, v)
                if not load_success then
                    os.exit(1)
                end
                
             --[[    if v == "consul_balancer" then
                    for ii,p in ipairs(loaded_plugins) do
                        if v == p.name then
                            p.handler.db_ready()
                        end
                    end
                end ]]
            end
        end, RestyGateway.data.store, RestyGateway.data.config)

        if not ok then
            ngx.log(ngx.ERR, "failed to create the timer: ", err)
            return os.exit(1)
        end
    end

    for _, plugin in ipairs(loaded_plugins) do
    plugin.handler:init_worker()
    end
end


local function init_cookies()
end

local function redirect()
end

local function rewrite()
end

local function access()
end

local function balancer()
end

local function header_filter()
end

local function body_filter()
end

local function log()
end

RestyGateway.init = init
RestyGateway.init_worker = init_worker
RestyGateway.ininit_cookiesit = init_cookies
RestyGateway.redirect = redirect
RestyGateway.rewrite = rewrite
RestyGateway.access = access
RestyGateway.balancer = balancer
RestyGateway.inheader_filterit = header_filter
RestyGateway.body_filter = body_filter
RestyGateway.log = log

return RestyGateway

local ipairs = ipairs
local pairs = pairs
local type = type
local require = require
local xpcall = xpcall
local string_lower = string.lower
local string_upper = string.upper
local lua_next = next

local template = require("resty.template")
local snaker_db = require("snaker.store.snaker_db_lrucache")
local utils = require("snaker.utils.utils")
local json = require("snaker.utils.json")
local res = require("dashboard.response")
local request = require("dashboard.request")
local router = require("resty.router")
local stringy = require("snaker.utils.stringy")
local r = router.new()
local _M = {}
local api_router = {
    get={},
    post={},
    put={},
    delete={}
}
local function urlDecode(s)  
    s = string.gsub(s, '%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)  
    return s  
end 

local function load_plugin_api(plugin, api_router, store)
    local plugin_api_path = "snaker.plugins." .. plugin .. ".api"
    ngx.log(ngx.ERR, "[plugin's api load], plugin_api_path:", plugin_api_path)

    local ok, plugin_api, e
    ok = xpcall(function() 
        plugin_api = require(plugin_api_path)
    end, function()
        e = debug.traceback()
    end)
    if not ok or not plugin_api or type(plugin_api) ~= "table" then
        ngx.log(ngx.ERR, "[plugin's api load error], plugin_api_path:", plugin_api_path, " error:", e)
        return
    end

    local plugin_apis
    ngx.log(ngx.ERR,"load_plugin_api"..plugin)
    if plugin_api.get_mode and plugin_api:get_mode() == 2 then
        plugin_apis = plugin_api:get_apis()
        ngx.log(ngx.ERR,"load_plugin_api get_mode 2 "..plugin)
    else
        plugin_apis = plugin_api
        ngx.log(ngx.ERR,"load_plugin_api get_mode 1 "..plugin)
    end

    for uri, api_methods in pairs(plugin_apis) do
        -- ngx.log(ngx.INFO, "load route, uri:", uri)
        ngx.log(ngx.ERR,"load route, uri:", uri)
        if type(api_methods) == "table" then
            for method, func in pairs(api_methods) do
                local m = string_lower(method)
                if m == "get" or m == "post" or m == "put" or m == "delete" then
                    -- api_router[m](api_router, uri, func(store))
                    
                    api_router[m][uri] =  func(store)
                    r:match(string_upper(m),uri,function(params)
                        local local_req = {params = params }
                        if params.request_bodys  then
                            ngx.log(ngx.ERR,"request_bodys exists".. table.concat(params.request_bodys,"-"))
                            local_req["body"] =  params.request_bodys 
                            params.request_bodys = nil                   
                        end
                        if  params.request_query  then
                            -- ngx.log(ngx.ERR,"query exists".. table.concat(params.query,"-"))
                            local_req["query"] =  params.request_query 
                            params.request_query = nil  
                        end
                        
                        func(store)(local_req,res,nil)
                    end)
                   
                end
            end
        end
    end
end


local function init()
   --- 加载其他"可用"插件API
   local available_plugins =  context.config.plugins
   local store = context.store
   if not available_plugins or type(available_plugins) ~= "table" or #available_plugins<1 then
       return 
   end

   for i, p in ipairs(available_plugins) do
       load_plugin_api(p, api_router, store)
   end
   r:match("GET","/",function(params)
--    api_router["GET"]["/"] = function(req, res)
        local data = {}
        local plugins =  context.config.plugins
        data.plugins = plugins

        local plugin_configs = {}
        for i, v in ipairs(plugins) do
            local tmp
            if v ~= "kvstore" then
                tmp = {
                    enable =  snaker_db.get(v .. ".enable"),
                    name = v,
                    active_selector_count = 0,
                    inactive_selector_count = 0,
                    active_rule_count = 0,
                    inactive_rule_count = 0
                }
                local plugin_selectors = snaker_db.get(v .. ".selectors")
                if plugin_selectors then
                    for sid, s in pairs(plugin_selectors) do
                        if s.enable == true then
                            tmp.active_selector_count = tmp.active_selector_count + 1
                            local selector_rules = snaker_db.get(v .. ".selector." .. sid .. ".rules")
                            if not selector_rules then
                                tmp.active_rule_count = 0
                                tmp.inactive_rule_count = 0
                            else
                                for _, r in ipairs(selector_rules) do
                                    if r.enable == true then
                                        tmp.active_rule_count = tmp.active_rule_count + 1
                                    else
                                        tmp.inactive_rule_count = tmp.inactive_rule_count + 1
                                    end
                                end
                            end
                        else
                            tmp.inactive_selector_count = tmp.inactive_selector_count + 1
                        end
                    end
                end
                plugin_configs[v] = tmp
            else
                tmp = {
                    enable =  snaker_db.get(v .. ".enable"),
                    name = v
                }
            end
            plugin_configs[v] = tmp
        end
        data.plugin_configs = plugin_configs
        

        -- local uri = ngx.var.uri
        -- local loaded, plugin_handler = utils.load_module_if_exists("snaker.plugins." .. v .. ".api")
        res:html(template.render("index.html",data))
    end)

 
    -- api_router["get"]["/property_rate_limiting"] = function(req, res)
    --     res:html(template.render("property_rate_limiting.html"))
    -- end
    -- api_router["get"]["/rewrite"] = function(req, res)
    --     res:html(template.render("rewrite.html"))
    -- end
    r:match("GET","/rewrite",function(params)
        res:html(template.render("rewrite.html"))
    end)
    r:match("GET","/property_rate_limiting",function(params)
        res:html(template.render("property_rate_limiting.html"))
    end)
    r:match("GET","/jwt_auth",function(params)
        res:html(template.render("jwt_auth/jwt_auth.html"))
    end)

  

    r:match("GET","/dynamic_upstream",function(params)
        local upstream = require "ngx.upstream"

        local upstream_list = upstream.get_upstreams()
        local empty_table = false

        if lua_next(upstream_list) == nil then
            empty_table = true
        end

        local every_upstream_config = {}
        for _, v in ipairs(upstream_list) do
            every_upstream_config[v] = upstream.get_servers(v)
        end

        res:html(template.render("dynamic_upstream.html",{upstreams=upstream_list, empty_table = empty_table, every_upstream_config = json.encode(every_upstream_config)}))
    end)



    r:match("GET","/status",function(params)
        res:html(template.render("status.html"))
    end)

    r:match("GET","/monitor",function(params)
        res:html(template.render("monitor.html"))
    end)

    r:match("GET","/monitor/rule/statistic",function(params)
        local rule_id = req.query.rule_id;
        local rule_name = req.query.rule_name or "";
        res:html(template.render("monitor-rule-stat.html", {
            rule_id = rule_id,
            rule_name = rule_name
        }))
    end)

    r:match("GET","/basic_auth",function(params)
        res:html(template.render("basic_auth/basic_auth.html"))
    end)
    
    r:match("GET","/divide",function(params)
        res:html(template.render("divide.html"))
    end)

    r:match("GET","/balancer",function(params)
        res:html(template.render("balancer.html"))
    end)

    r:match("GET","/consul_balancer",function(params)
        res:html(template.render("consul_balancer.html"))
    end)
    
   

    
end

local function run ()
    local request_method = ngx.var.request_method
    local request_args 
    local  body ={}
    local headers = ngx.req.get_headers()
    if "POST" == request_method or   "PUT" == request_method then
        ngx.req.read_body()
        request_args = ngx.req.get_post_args()
        local request_body = ngx.req.get_body_data()
        local from,to = ngx.re.find(headers["Content-Type"], 'application/x-www-form-urlencoded','jo')
        ngx.log(ngx.ERR,"from - "..headers["Content-Type"])
        if  from then
            ngx.log(ngx.ERR,"from - "..from)
            local bodys = stringy.split(request_body,"=")
            for i=1,#bodys,2 do   
                ngx.log(ngx.ERR,bodys[i].." - "..bodys[i+1])             
                body[bodys[i]] = urlDecode(bodys[i+1])
            end
        end
        
        -- end
        -- application/x-www-form-urlencoded
        -- req.body = request_body
    else
        request_args = ngx.req.get_uri_args()
        -- ngx.log(ngx.ERR,"request_args - ".. ngx.var.request_uri..request_args["service"])
        
    end
    -- ngx.log(ngx.ERR,"request_args - ".. ngx.var.request_uri..request_args["service"])
    -- ngx.log(ngx.ERR,"request_args"..table.concat(request_args,"#"))
    
    local ok, errmsg = r:execute(
        request_method,
        ngx.var.uri,
        request_args,-- all these parameters
        {request_bodys = body,request_query = request_args} -- will be merged in order
        )         -- into a single "params" table



    -- local uri = ngx.var.uri
    -- local request_method = string_lower(ngx.var.request_method)
    -- local req = request:init()

    --  api_router[request_method][uri](req,res)
end
  

_M.run =run
_M.init =init
return _M
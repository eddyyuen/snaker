---
-- from https://github.com/Mashape/kong/blob/master/kong/plugins/base_plugin.lua
-- modified by sumory.wu

local Object = require("snaker.lib.classic")
local BasePlugin = Object:extend()

function BasePlugin:new(name)
    self._name = name
end

function BasePlugin:get_name()
    return self._name
end

function BasePlugin:init_worker()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": init_worker")
end

function BasePlugin:redirect()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": redirect")
end

function BasePlugin:rewrite()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": rewrite")
end

function BasePlugin:access()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": access")
end

function BasePlugin:balancer()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": balancer")
end

function BasePlugin:header_filter()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": header_filter")
end

function BasePlugin:body_filter()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": body_filter")
end

function BasePlugin:log()
    ngx.log(ngx.DEBUG, " executing plugin \"", self._name, "\": log")
end

return BasePlugin

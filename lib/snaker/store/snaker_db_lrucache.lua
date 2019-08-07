local json = require("snaker.utils.json")
-- local snaker_data = ngx.shared.snaker_data

local lrucache = require "resty.lrucache"
local snaker_data, err = lrucache.new(1000)  -- allow up to 200 items in the cache
if err then
    ngx.log(ngx.ERR,"snaker_data init lrucache",err)
end
local _M = {}

 
function _M.get(key)
    return snaker_data:get(key)
end

 
function _M.set(key, value)
   snaker_data:set(key, value)
   return true,nil,nil
end


function _M.incr(key, value)
    local v,err = _M.get(key)
    if v then
        v = v + value
    else
        v = value
    end
    return snaker_data:set(key, v)
end

function _M.delete(key)
    return snaker_data:delete(key)
end

function _M.delete_all()
    snaker_data:flush_all()
end


return _M

local json = require("snaker.utils.json")

local _M = {}

function _M:html(content)
    ngx.header["Content-Type"] ="text/html; charset=UTF-8"
    ngx.say(content)
end

function _M:json(content)
    ngx.header["Content-Type"] ="application/json; charset=UTF-8"
    ngx.say(json.encode(content))
end

return _M
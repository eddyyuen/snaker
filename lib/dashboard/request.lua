local json = require("snaker.utils.json")

local _M = {}


function _M:init()
    local req = {
        params = {},
        body = {}
    }
    local request_method = ngx.var.request_method
    local request_args , request_body 
    if "POST" == request_method then
        ngx.req.read_body()
        request_args = ngx.req.get_post_args()
        request_body = ngx.req.get_body_data()
        req.body = request_body
    else
        request_args = ngx.req.get_uri_args()
    end
    req.params = request_args
    

    return req
end


return _M
local BaseAPI = require("snaker.plugins.base_api")
local common_api = require("snaker.plugins.common_api")

local api = BaseAPI:new("dynamic-upstream-api", 2)
api:merge_apis(common_api("dynamic_upstream"))
return api

local BaseAPI = require("snaker.plugins.base_api")
local common_api = require("snaker.plugins.common_api")
local plugin_config =  require("snaker.plugins.property_rate_limiting.plugin")

local api = BaseAPI:new(plugin_config.api_name, 2)
api:merge_apis(common_api(plugin_config.table_name))
return api

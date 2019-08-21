local stat = require("snaker.plugins.monitor.stat")
local BaseAPI = require("snaker.plugins.base_api")
local common_api = require("snaker.plugins.common_api")

local api = BaseAPI:new("monitor-api", 2)

api:merge_apis(common_api("monitor"))

api:get("/monitor/stat", function(store)
    return function(req, res, next)
        local rule_id = req.query.rule_id
        local statistics = stat.get(rule_id)

        res:json({
            success = true,
            data = statistics
        })
    end
end)

return api

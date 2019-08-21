local BasePlugin = require("snaker.plugins.base_handler")
local persist = require("snaker.plugins.persist.persist")

local PersistHandler = BasePlugin:extend()
PersistHandler.PRIORITY = 1999

function PersistHandler:new(store)
    PersistHandler.super.new(self, "persist-plugin")
    self.store = store
end

function PersistHandler:init_worker()
    PersistHandler.super.init_worker(self)
    persist.init(self)
end

function PersistHandler:log()
    PersistHandler.super.log(self)
    persist.log(self)
end

return PersistHandler

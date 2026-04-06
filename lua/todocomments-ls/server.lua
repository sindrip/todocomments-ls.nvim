--- Base class for in-process LSP servers.
---
--- Usage:
---   local Server = require("todocomments-ls.server")
---   local M = Server.new("name")
---
---   M.capabilities = { ... }          -- LSP capabilities to advertise
---   M.root_markers = { ".git" }       -- files that identify the project root (default: nil)
---   M.single_file_support = false     -- work without a project root (default: true)
---
---   function M:on_init(params) end    -- called on initialize
---   function M:on_shutdown() end      -- called on shutdown (once)
---
---   M.requests["method"] = function(self, params) return result end
---   M.notifications["method"] = function(self, params) end
---
---   return M:build()
local Server = {}
Server.__index = Server

function Server.new(name)
  return setmetatable({
    name = name,
    capabilities = {},
    root_markers = nil,
    single_file_support = true,

    requests = {
      ["initialize"] = function(self, params)
        if self.on_init then
          self:on_init(params)
        end
        return { capabilities = self.capabilities, serverInfo = { name = self.name } }
      end,

      ["shutdown"] = function(self)
        if not self._did_shutdown and self.on_shutdown then
          self:on_shutdown()
        end
        self._did_shutdown = true
        return vim.NIL
      end,
    },

    notifications = {
      ["exit"] = function(self)
        if not self._did_shutdown and self.on_shutdown then
          self:on_shutdown()
        end
        self.closing = true
        self.dispatchers.on_exit(0, 0)
      end,
    },
  }, { __index = Server })
end

function Server:handle_request(method, params, callback, notify_reply_callback)
  self.request_id = self.request_id + 1

  local handler = self.requests[method]
  if handler then
    local ok, result, err = pcall(handler, self, params)
    if not ok then
      callback({ code = -32603, message = tostring(result) }, nil)
    elseif err then
      callback({ code = -32603, message = err }, nil)
    else
      callback(nil, result or {})
    end
  else
    callback({ code = -32601, message = "Method not found: " .. method }, nil)
  end

  if notify_reply_callback then
    notify_reply_callback(self.request_id)
  end

  return true, self.request_id
end

function Server:handle_notify(method, params)
  local handler = self.notifications[method]
  if handler then
    handler(self, params)
  end
end

function Server:build()
  local proto = self

  return {
    cmd = function(dispatchers)
      dispatchers.notification = vim.schedule_wrap(dispatchers.notification)
      dispatchers.on_error = vim.schedule_wrap(dispatchers.on_error)

      local srv = setmetatable({
        dispatchers = dispatchers,
        closing = false,
        request_id = 0,
      }, { __index = proto })

      return {
        request = function(method, params, callback, notify_reply_callback)
          return srv:handle_request(method, params, vim.schedule_wrap(callback),
            notify_reply_callback and vim.schedule_wrap(notify_reply_callback))
        end,

        notify = function(...)
          srv:handle_notify(...)
        end,

        is_closing = function()
          return srv.closing
        end,

        terminate = function()
          srv.closing = true
        end,
      }
    end,

    root_markers = self.root_markers,
    single_file_support = self.single_file_support,
  }
end

return Server

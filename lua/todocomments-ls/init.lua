-- Highlights TODO-style keywords as diagnostics with document colors.
local Server = require("todocomments-ls.server")
local M = Server.new("todocomments-ls")

M.capabilities = {
  diagnosticProvider = {},
  colorProvider = true,
}

local function hl_color(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  if not hl.fg then
    return nil
  end
  return {
    red = bit.rshift(bit.band(hl.fg, 0xFF0000), 16) / 255,
    green = bit.rshift(bit.band(hl.fg, 0x00FF00), 8) / 255,
    blue = bit.band(hl.fg, 0x0000FF) / 255,
    alpha = 1,
  }
end

local sev = vim.diagnostic.severity

-- stylua: ignore
local sev_hl = {
  [sev.ERROR] = "DiagnosticError",
  [sev.WARN]  = "DiagnosticWarn",
  [sev.INFO]  = "DiagnosticInfo",
  [sev.HINT]  = "DiagnosticHint",
}

-- stylua: ignore
local keywords = {
  FIX  = { alt = { "FIXME", "BUG", "FIXIT", "ISSUE" }, severity = sev.ERROR },
  TODO = { severity = sev.INFO },
  HACK = { alt = { "XXX" }, severity = sev.WARN },
  WARN = { alt = { "WARNING" }, severity = sev.WARN },
  PERF = { hl = "Identifier", alt = { "OPTIM", "PERFORMANCE" }, severity = sev.HINT },
  NOTE = { alt = { "INFO" }, severity = sev.HINT },
  TEST = { hl = "Identifier", alt = { "TESTING", "PASSED", "FAILED" }, severity = sev.INFO },
}

local keyword_map = {}
for name, cfg in pairs(keywords) do
  keyword_map[name] = cfg
  for _, alt in ipairs(cfg.alt or {}) do
    keyword_map[alt] = cfg
  end
end

local names = vim.tbl_keys(keyword_map)
table.sort(names, function(a, b)
  return #a > #b
end)

local function find_keyword(line)
  for _, name in ipairs(names) do
    local col = 1
    while col <= #line do
      local s, e = line:find(name, col, true)
      if not s then
        break
      end

      local before_ok = s == 1 or not line:sub(s - 1, s - 1):match("[%w_]")
      local after_char = line:sub(e + 1, e + 1)

      if before_ok and (after_char == ":" or after_char == "(") then
        local colon_pos
        if after_char == ":" then
          colon_pos = e + 1
        elseif after_char == "(" then
          local close = line:find(")", e + 2, true)
          if close and line:sub(close + 1, close + 1) == ":" then
            colon_pos = close + 1
          end
        end

        if colon_pos then
          local message = vim.trim(line:sub(colon_pos + 1))
          return s, e, name, keyword_map[name], message
        end
      end

      col = e + 1
    end
  end
end

local function in_comment(bufnr, row, col)
  local captures = vim.treesitter.get_captures_at_pos(bufnr, row, col)
  for _, c in ipairs(captures) do
    if c.capture:find("^comment") then
      return true
    end
  end
  return false
end

local function scan(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return {}
  end

  local has_ts = vim.treesitter.get_parser(bufnr, nil, { error = false }) ~= nil
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}

  for i, line in ipairs(lines) do
    local s, e, name, cfg, message = find_keyword(line)
    if s and (not has_ts or in_comment(bufnr, i - 1, s - 1)) then
      table.insert(results, {
        range = {
          start = { line = i - 1, character = s - 1 },
          ["end"] = { line = i - 1, character = e },
        },
        message = message ~= "" and (name .. ": " .. message) or name,
        severity = cfg.severity,
        color = hl_color(cfg.hl or sev_hl[cfg.severity]),
        source = "todocomments-ls",
      })
    end
  end

  return results
end

M.requests["textDocument/diagnostic"] = function(_, params)
  local results = scan(params.textDocument.uri)
  local items = {}
  for _, r in ipairs(results) do
    table.insert(items, {
      range = r.range,
      message = r.message,
      severity = r.severity,
      source = r.source,
    })
  end
  return { kind = "full", items = items }
end

M.requests["textDocument/documentColor"] = function(_, params)
  local results = scan(params.textDocument.uri)
  local colors = {}
  for _, r in ipairs(results) do
    table.insert(colors, {
      range = {
        start = { line = r.range.start.line, character = math.max(0, r.range.start.character - 1) },
        ["end"] = { line = r.range["end"].line, character = r.range["end"].character + 1 },
      },
      color = r.color,
    })
  end
  return colors
end

return M:build()

-- Highlights TODO-style keywords as diagnostics with document colors.
local Server = require("todocomments-ls.server")
local M = Server.new("todocomments-ls")

M.capabilities = {
  textDocumentSync = { change = 1, openClose = true },
  colorProvider = true,
}

local function hl_color(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  local color = hl.fg or hl.sp
  if not color then
    return nil
  end
  return {
    red = bit.rshift(bit.band(color, 0xFF0000), 16) / 255,
    green = bit.rshift(bit.band(color, 0x00FF00), 8) / 255,
    blue = bit.band(color, 0x0000FF) / 255,
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

local function collect_comments(node, ranges)
  if node:type():find("comment") then
    local sr, sc, er, ec = node:range()
    table.insert(ranges, { sr, sc, er, ec })
    return
  end
  for child in node:iter_children() do
    collect_comments(child, ranges)
  end
end

local function get_comment_ranges(text, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok then
    return nil
  end
  parser:parse()
  local ranges = {}
  parser:for_each_tree(function(tstree)
    collect_comments(tstree:root(), ranges)
  end)
  return ranges
end

local function in_comment(ranges, row, col)
  if not ranges then
    return true
  end
  for _, r in ipairs(ranges) do
    if (row > r[1] or (row == r[1] and col >= r[2]))
      and (row < r[3] or (row == r[3] and col < r[4])) then
      return true
    end
  end
  return false
end

local function scan(text, lang)
  local comment_ranges = get_comment_ranges(text, lang)
  local lines = vim.split(text, "\n", { plain = true })
  local results = {}

  for i, line in ipairs(lines) do
    local s, e, name, cfg, message = find_keyword(line)
    if s and in_comment(comment_ranges, i - 1, s - 1) then
      table.insert(results, {
        range = {
          start = { line = i - 1, character = math.max(0, s - 2) },
          ["end"] = { line = i - 1, character = e + 1 },
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

local documents = {}
local scan_cache = {}

local function scan_buf(uri)
  local doc = documents[uri]
  if not doc then
    return {}
  end
  local cached = scan_cache[uri]
  if cached and cached.text == doc.text then
    return cached.results
  end
  local results = scan(doc.text, doc.lang)
  scan_cache[uri] = { text = doc.text, results = results }
  return results
end

local function publish_diagnostics(self, uri, version)
  local results = scan_buf(uri)
  local items = {}
  for _, r in ipairs(results) do
    table.insert(items, {
      range = r.range,
      message = r.message,
      severity = r.severity,
      source = r.source,
    })
  end
  self.dispatchers.notification("textDocument/publishDiagnostics", {
    uri = uri,
    version = version,
    diagnostics = items,
  })
end

M.notifications["textDocument/didOpen"] = function(self, params)
  local td = params.textDocument
  documents[td.uri] = { text = td.text, lang = td.languageId }
  publish_diagnostics(self, td.uri, td.version)
end

M.notifications["textDocument/didChange"] = function(self, params)
  local td = params.textDocument
  if params.contentChanges[1] then
    documents[td.uri].text = params.contentChanges[1].text
  end
  vim.schedule(function()
    publish_diagnostics(self, td.uri, td.version)
  end)
end

M.notifications["textDocument/didClose"] = function(_, params)
  local uri = params.textDocument.uri
  documents[uri] = nil
  scan_cache[uri] = nil
end

M.requests["textDocument/documentColor"] = function(_, params)
  local results = scan_buf(params.textDocument.uri)
  local colors = {}
  for _, r in ipairs(results) do
    if r.color then
      table.insert(colors, { range = r.range, color = r.color })
    end
  end
  return colors
end

local built = M:build()
built.bench = function(n)
  n = n or 100
  for uri, doc in pairs(documents) do
    scan_cache[uri] = nil
    local t0 = vim.uv.hrtime()
    for _ = 1, n do
      scan_cache[uri] = nil
      scan(doc.text, doc.lang)
    end
    local avg = (vim.uv.hrtime() - t0) / 1e6 / n
    vim.notify(("%s: %.2fms avg (%d runs)"):format(vim.uri_to_fname(uri), avg, n))
  end
end
return built

-- vim_mcp_lsp.lua — Neovim LSP helpers exposed to the MCP bridge.
-- All functions return plain JSON-able tables and never raise (pcall-guarded
-- at the vimscript boundary). Neovim-only; the vimscript side guards has('nvim').
local M = {}

local SEV = { "ERROR", "WARN", "INFO", "HINT" }

local function clients_for_buf()
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  return get({ bufnr = 0 })
end

local function pos_params()
  local cs = clients_for_buf()
  local enc = (cs[1] and cs[1].offset_encoding) or "utf-16"
  return vim.lsp.util.make_position_params(0, enc)
end

local function uri_path(uri) return vim.uri_to_fname(uri) end

function M.diagnostics()
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    out[#out + 1] = {
      line = d.lnum + 1,
      col = d.col + 1,
      severity = SEV[d.severity] or tostring(d.severity),
      message = d.message,
      source = d.source,
    }
  end
  return { success = true, count = #out, diagnostics = out }
end

-- definition / references / implementation / type_definition -> locations
function M.locations(method)
  if #clients_for_buf() == 0 then return { success = false, error = "no LSP client attached" } end
  local params = pos_params()
  if method == "textDocument/references" then
    params.context = { includeDeclaration = true }
  end
  local results = vim.lsp.buf_request_sync(0, method, params, 2000) or {}
  local locs = {}
  for _, res in pairs(results) do
    local r = res.result
    if r then
      local items = (r.uri or r.targetUri) and { r } or r
      for _, loc in ipairs(items) do
        local uri = loc.uri or loc.targetUri
        local range = loc.range or loc.targetSelectionRange
        if uri and range then
          locs[#locs + 1] = { file = uri_path(uri), line = range.start.line + 1, col = range.start.character + 1 }
        end
      end
    end
  end
  return { success = true, count = #locs, locations = locs }
end

function M.hover()
  if #clients_for_buf() == 0 then return { success = false, error = "no LSP client attached" } end
  local results = vim.lsp.buf_request_sync(0, "textDocument/hover", pos_params(), 2000) or {}
  local parts = {}
  for _, res in pairs(results) do
    local c = res.result and res.result.contents
    if type(c) == "string" then
      parts[#parts + 1] = c
    elseif type(c) == "table" then
      if c.value then
        parts[#parts + 1] = c.value
      else
        for _, p in ipairs(c) do parts[#parts + 1] = type(p) == "table" and (p.value or "") or tostring(p) end
      end
    end
  end
  return { success = true, hover = table.concat(parts, "\n") }
end

function M.rename(new_name)
  if not new_name or new_name == "" then return { success = false, error = "new_name required" } end
  if #clients_for_buf() == 0 then return { success = false, error = "no LSP client attached" } end
  vim.lsp.buf.rename(new_name) -- async; edits applied across buffers
  return { success = true, message = 'rename to "' .. new_name .. '" requested at cursor' }
end

function M.code_actions()
  if #clients_for_buf() == 0 then return { success = false, error = "no LSP client attached" } end
  local params = vim.lsp.util.make_range_params(0, (clients_for_buf()[1].offset_encoding) or "utf-16")
  params.context = { diagnostics = vim.diagnostic.get(0) }
  local results = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 2000) or {}
  local actions = {}
  for _, res in pairs(results) do
    for _, a in ipairs(res.result or {}) do actions[#actions + 1] = a.title end
  end
  return { success = true, count = #actions, actions = actions }
end

-- dispatch entry used by the vimscript layer
function M.action(req)
  local a = req.action
  local map = {
    diagnostics = M.diagnostics,
    hover = M.hover,
    rename = function() return M.rename(req.new_name) end,
    code_action = M.code_actions,
    definition = function() return M.locations("textDocument/definition") end,
    references = function() return M.locations("textDocument/references") end,
    implementation = function() return M.locations("textDocument/implementation") end,
    type_definition = function() return M.locations("textDocument/typeDefinition") end,
  }
  local fn = map[a]
  if not fn then return { success = false, error = "unknown lsp action: " .. tostring(a) } end
  local ok, res = pcall(fn)
  if not ok then return { success = false, error = tostring(res) } end
  return res
end

return M

local M = {}

local data = require "lemon.core.scope.data"
local biscuit = require "lemon.core.scope.biscuit"

local ns = vim.api.nvim_create_namespace "lemon_scope"
local augroup = vim.api.nvim_create_augroup("lemon_scope", { clear = true })

---@type table<number, { symbols: table[], path: table[] }>
local bufstates = {}

local enabled = true

local function get_cfg()
  return require("lemon.config").get().scope
end

local function render(bufnr)
  if not enabled then
    return
  end

  local state = bufstates[bufnr]
  if not state or not state.symbols or #state.symbols == 0 then
    return
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local cursor_line = cursor[1] - 1
  local cursor_col = cursor[2]

  local path = data.find_path(state.symbols, cursor_line, cursor_col)
  local cfg = get_cfg()

  state.path = path

  if cfg.biscuit.enabled then
    biscuit.render(bufnr, ns, state.symbols, winid, cfg.biscuit.visible_mode, cursor_line, cfg.biscuit)
  end
end

local function refresh(bufnr)
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/documentSymbol" }
  if #clients == 0 then
    return
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  clients[1]:request("textDocument/documentSymbol", params, function(err, result)
    if err or not result then
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    if not bufstates[bufnr] then
      bufstates[bufnr] = { symbols = {}, path = {} }
    end

    bufstates[bufnr].symbols = result

    vim.schedule(function()
      render(bufnr)
    end)
  end, bufnr)
end

local function setup_buf(bufnr)
  if bufstates[bufnr] then
    return
  end

  bufstates[bufnr] = { symbols = {}, path = {} }

  local cfg = get_cfg()
  local events = cfg.lazy_update and { "CursorHold" } or { "CursorMoved", "CursorHold" }

  vim.api.nvim_create_autocmd(events, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      render(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      render(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      bufstates[bufnr] = nil
    end,
  })

  vim.api.nvim_create_autocmd("LspNotify", {
    group = augroup,
    buffer = bufnr,
    callback = function(args)
      local method = args.data and args.data.method
      if method == "textDocument/didChange" or method == "textDocument/didOpen" then
        refresh(bufnr)
      end
    end,
  })

  refresh(bufnr)
end

function M.setup()
  local cfg = get_cfg()
  if not cfg.enabled then
    return
  end

  enabled = true

  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client then
        return
      end

      if not client.server_capabilities.documentSymbolProvider then
        return
      end

      setup_buf(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    callback = function(args)
      local bufnr = args.buf

      local remaining = vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/documentSymbol" }
      local still_has = false
      for _, c in ipairs(remaining) do
        if c.id ~= args.data.client_id then
          still_has = true
          break
        end
      end

      if not still_has then
        bufstates[bufnr] = nil
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        end
      end
    end,
  })
end

function M.toggle()
  enabled = not enabled
  if not enabled then
    for bufnr in pairs(bufstates) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      end
    end
  else
    local bufnr = vim.api.nvim_get_current_buf()
    if bufstates[bufnr] then
      render(bufnr)
    end
  end
end

function M.is_available(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = bufstates[bufnr]
  return state ~= nil and state.symbols ~= nil and #state.symbols > 0
end

function M.get_location(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = bufstates[bufnr]
  if not state or not state.path then
    return {}
  end
  return state.path
end

function M.get_data(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = bufstates[bufnr]
  if not state or not state.path or #state.path == 0 then
    local cfg = get_cfg()
    if cfg.safe_output then
      return ""
    end
    return ""
  end

  local cfg = get_cfg()
  local chunks = data.format_path(state.path, cfg.separator, cfg.depth_limit, cfg.depth_limit_indicator)

  local parts = {}
  for _, chunk in ipairs(chunks) do
    local text = chunk[1]:gsub("%%", "%%%%"):gsub(" ", "\\ ")
    local hl = chunk[2]
    table.insert(parts, "%#" .. hl .. "#" .. text)
  end

  return table.concat(parts, "")
end

return M

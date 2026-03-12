local M = {}

local render_mod = require "lemon.core.inlay_hint.render"
local debounce = require "lemon.util.debounce"

local ns = vim.api.nvim_create_namespace "lemon_inlay_hint"
local augroup = vim.api.nvim_create_augroup("lemon_inlay_hint", { clear = true })

---@type table<number, { enabled: boolean, client_hints: table<number, table<number, table[]>> }>
local bufstates = {}

---@type table<number, function>
local debounced_renders = {}

local function get_cfg()
  return require("lemon.config").get().inlay_hint
end

local function render(bufnr)
  render_mod.render(bufnr, bufstates[bufnr], ns)
end

local function on_inlayhint(err, result, ctx)
  if err then
    return
  end

  local bufnr = ctx.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local client_id = ctx.client_id
  local state = bufstates[bufnr]
  if not state then
    return
  end

  local grouped = {}
  for _, hint in ipairs(result or {}) do
    local lnum = hint.position.line
    local character = hint.position.character

    local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
    local col = 0
    if line then
      local ok, byte_idx = pcall(vim.str_byteindex, line, character, true)
      if ok and byte_idx then
        col = byte_idx
      end
    end

    hint._col = col

    if not grouped[lnum] then
      grouped[lnum] = {}
    end
    table.insert(grouped[lnum], hint)
  end

  state.client_hints[client_id] = grouped

  vim.schedule(function()
    render(bufnr)
  end)
end

local function refresh(bufnr)
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/inlayHint" }
  if #clients == 0 then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    range = {
      start = { line = 0, character = 0 },
      ["end"] = { line = line_count, character = 0 },
    },
  }

  for _, client in ipairs(clients) do
    client:request("textDocument/inlayHint", params, function(err, result)
      on_inlayhint(err, result, { bufnr = bufnr, client_id = client.id })
    end, bufnr)
  end
end

local function setup_buf_autocmds(bufnr)
  local cfg = get_cfg()

  debounced_renders[bufnr] = debounce(50, function()
    render(bufnr)
  end)

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      bufstates[bufnr] = nil
      debounced_renders[bufnr] = nil
    end,
  })

  if cfg.hide_in_insert then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      end,
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        render(bufnr)
      end,
    })
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if debounced_renders[bufnr] then
        debounced_renders[bufnr]()
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      if vim.api.nvim_get_current_buf() == bufnr then
        render(bufnr)
      end
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
end

local builtin_enable = vim.lsp.inlay_hint.enable

local function disable_builtin()
  pcall(builtin_enable, false)

  local builtin_ns = vim.api.nvim_create_namespace "vim/lsp/inlay_hint"
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, builtin_ns, 0, -1)
    end
  end

  vim.lsp.inlay_hint.enable = function(enable, filter)
    if enable == false or (type(enable) == "boolean" and not enable) then
      return builtin_enable(false, filter)
    end
  end
end

function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not bufstates[bufnr] then
    bufstates[bufnr] = { enabled = true, client_hints = {} }
    setup_buf_autocmds(bufnr)
  else
    bufstates[bufnr].enabled = true
  end

  refresh(bufnr)
end

function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local state = bufstates[bufnr]
  if state then
    state.enabled = false
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = bufstates[bufnr]
  if state and state.enabled then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

function M.setup()
  local cfg = get_cfg()
  if not cfg.enabled then
    return
  end

  disable_builtin()

  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client then
        return
      end

      local supports = client.server_capabilities.inlayHintProvider
      if not supports then
        return
      end

      local bufnr = args.buf
      pcall(builtin_enable, false, { bufnr = bufnr })
      local builtin_ns = vim.api.nvim_create_namespace "vim/lsp/inlay_hint"
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, builtin_ns, 0, -1)

      M.enable(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    callback = function(args)
      local bufnr = args.buf
      local client_id = args.data.client_id
      local state = bufstates[bufnr]
      if not state then
        return
      end

      state.client_hints[client_id] = nil

      local has_clients = false
      for _ in pairs(state.client_hints) do
        has_clients = true
        break
      end

      if not has_clients then
        bufstates[bufnr] = nil
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        end
      else
        render(bufnr)
      end
    end,
  })
end

return M

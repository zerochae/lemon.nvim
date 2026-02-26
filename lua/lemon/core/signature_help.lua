local M = {}

local glyph = require "lemon.glyph"
local footer = require "lemon.ui.footer"
local window = require "lemon.ui.window"
local FloatPanel = require "lemon.ui.float"

local SignatureHelpPanel = setmetatable({}, { __index = FloatPanel })
SignatureHelpPanel.__index = SignatureHelpPanel

local panel = SignatureHelpPanel:new "signature_help"

function SignatureHelpPanel:get_config()
  return FloatPanel.get_config(self)
end

function SignatureHelpPanel:build_content(result, server_name)
  local signatures = result.signatures
  if not signatures or #signatures == 0 then
    return {}, {}
  end

  local active_sig = result.activeSignature or 0
  if active_sig >= #signatures then
    active_sig = 0
  end
  self._active_sig = active_sig
  self._result = result
  self._server_name = server_name

  local ft = vim.api.nvim_get_option_value("filetype", { buf = self.source_bufnr })
  local clients = vim.lsp.get_clients { bufnr = self.source_bufnr, method = "textDocument/signatureHelp" }
  local triggers
  if clients[1] and clients[1].server_capabilities.signatureHelpProvider then
    triggers = clients[1].server_capabilities.signatureHelpProvider.triggerCharacters
  end

  local lines, hl = vim.lsp.util.convert_signature_help_to_markdown_lines(result, ft, triggers)
  if not lines or #lines == 0 then
    return {}, {}
  end

  local meta_lines, meta_ext = self:build_meta(server_name)

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.lsp.util.stylize_markdown(self.buf, lines, {})

  local meta_insert = {}
  for i = 1, #meta_lines do
    table.insert(meta_insert, meta_lines[i])
  end
  table.insert(meta_insert, "")
  vim.api.nvim_buf_set_lines(self.buf, 0, 0, false, meta_insert)
  lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)

  self._meta_ext = meta_ext
  self._meta_count = #meta_lines
  self._meta_offset = #meta_insert
  self._active_hl = hl

  return lines, {}
end

function SignatureHelpPanel:open_win(lines)
  local cfg = self:get_config()
  local win_opts = window.compute(lines, {
    max_width = cfg.max_width,
    max_height = cfg.max_height,
    pad_right = cfg.pad_right,
    min_width = cfg.min_width,
    min_height = cfg.min_height,
    extra_height = cfg.extra_height,
  })

  self._enter = false
  local border_height = (cfg.border and cfg.border ~= "none") and 2 or 0
  local total_height = win_opts.height + border_height
  local cursor_screen_row = vim.fn.screenrow()
  local row
  if cursor_screen_row > total_height then
    row = -total_height
  else
    row = 1
  end

  self.win = vim.api.nvim_open_win(self.buf, false, {
    relative = "cursor",
    row = row,
    col = 0,
    width = win_opts.width,
    height = win_opts.height,
    border = cfg.border,
    style = "minimal",
  })

  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:LemonNormal,FloatBorder:LemonBorder,SignColumn:LemonNormal",
    { win = self.win }
  )
  vim.api.nvim_set_option_value("signcolumn", "yes", { win = self.win })
  vim.api.nvim_set_option_value("wrap", true, { win = self.win })

  if cfg.conceal then
    vim.api.nvim_set_option_value("conceallevel", 2, { win = self.win })
    vim.api.nvim_set_option_value("concealcursor", "niv", { win = self.win })
  end
end

function SignatureHelpPanel:apply_extmarks(_, lines)
  local ns = vim.api.nvim_create_namespace "lemon_signature_help"

  for i, ext in ipairs(self._meta_ext or {}) do
    vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
      sign_text = ext.sign.icon,
      sign_hl_group = ext.sign.hl,
    })
    if ext.text_hl then
      local line_len = #lines[i]
      vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
        end_col = line_len,
        hl_group = ext.text_hl,
      })
    end
  end

  local tag_icons = require("lemon.parsers").get_all_tags()
  local content_start = self._meta_count or 0
  local total_lines = vim.api.nvim_buf_line_count(self.buf)
  local first_content = true
  for i = content_start, total_lines - 1 do
    local l = lines[i + 1] or ""
    local matched = false
    local stripped = l:gsub("%*", ""):gsub("%s+", " "):gsub("^%s+", "")
    for pattern, tag_cfg in pairs(tag_icons) do
      if stripped:match("^" .. pattern .. "%s") or stripped:match("^" .. pattern .. "$") then
        vim.api.nvim_buf_set_extmark(self.buf, ns, i, 0, {
          sign_text = tag_cfg.icon,
          sign_hl_group = tag_cfg.hl,
        })
        matched = true
        break
      end
    end
    if not matched and first_content and l ~= "" and not l:match "^```" then
      vim.api.nvim_buf_set_extmark(self.buf, ns, i, 0, {
        sign_text = glyph.ui.content,
        sign_hl_group = "LemonTitle",
      })
      first_content = false
    end
  end

  if self._active_hl then
    local offset = self._meta_offset or 0
    vim.hl.range(
      self.buf,
      ns,
      "LemonSignatureActiveParam",
      { self._active_hl[1] + offset, self._active_hl[2] },
      { self._active_hl[3] + offset, self._active_hl[4] }
    )
  end
end

function SignatureHelpPanel:after_open()
  vim.treesitter.start(self.buf, "markdown")
  local cfg = self:get_config()
  local sigs = self._result and self._result.signatures or {}
  local footer_items = {}
  if #sigs > 1 then
    local idx = (self._active_sig or 0) + 1
    table.insert(footer_items, {
      icon = glyph.footer.select,
      desc = "overload(" .. idx .. "/" .. #sigs .. ")",
      key = "C-s",
    })
  end
  if #footer_items > 0 then
    footer.set(self.win, footer_items, cfg.footer)
  end
end

function SignatureHelpPanel:setup_keymaps()
  FloatPanel.setup_keymaps(self)

  if self._result and self._result.signatures and #self._result.signatures > 1 then
    vim.keymap.set("i", "<C-s>", function()
      if not panel:is_open() then
        return
      end
      local sigs = panel._result.signatures
      local next_sig = ((panel._active_sig or 0) + 1) % #sigs
      panel._result.activeSignature = next_sig
      panel:show(panel.source_bufnr, panel._result, panel._server_name)
    end, {
      buffer = self.source_bufnr,
      nowait = true,
      silent = true,
    })
  end
end

function SignatureHelpPanel:close()
  local src = self.source_bufnr
  FloatPanel.close(self)
  if src and vim.api.nvim_buf_is_valid(src) then
    pcall(vim.keymap.del, "i", "<C-s>", { buffer = src })
  end
end

local function request_signature_help(bufnr)
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = "textDocument/signatureHelp" }
  if #clients == 0 then
    return
  end

  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding or "utf-16")

  vim.lsp.buf_request(bufnr, "textDocument/signatureHelp", params, function(err, result)
    if err or not result or not result.signatures or #result.signatures == 0 then
      if panel:is_open() then
        vim.schedule(function()
          panel:close()
        end)
      end
      return
    end
    if panel:is_open() and panel._active_sig then
      result.activeSignature = panel._active_sig
    else
      result.activeSignature = 0
    end
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      panel:show(bufnr, result, client.name or "LSP")
    end)
  end)
end

function M.signature_help()
  local source_bufnr = vim.api.nvim_get_current_buf()
  request_signature_help(source_bufnr)
end

local function setup_auto_trigger(group, bufnr, trigger_chars, retrigger_chars)
  local trigger_set = {}
  for _, ch in ipairs(trigger_chars or {}) do
    trigger_set[ch] = true
  end
  for _, ch in ipairs(retrigger_chars or {}) do
    trigger_set[ch] = true
  end

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    buffer = bufnr,
    callback = function()
      if trigger_set[vim.v.char] then
        vim.schedule(function()
          request_signature_help(bufnr)
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = bufnr,
    callback = function()
      if panel:is_open() then
        vim.schedule(function()
          request_signature_help(bufnr)
        end)
      end
    end,
  })
end

function M.setup_auto()
  local cfg = require("lemon.config").get()
  if not cfg.signature_help or not cfg.signature_help.auto then
    return
  end

  pcall(vim.api.nvim_del_augroup_by_name, "lemon_signature_auto")
  pcall(vim.api.nvim_del_augroup_by_name, "lemon_signature_attach")

  local trigger_group = vim.api.nvim_create_augroup("lemon_signature_auto", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lemon_signature_attach", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or not client.server_capabilities.signatureHelpProvider then
        return
      end
      local provider = client.server_capabilities.signatureHelpProvider
      local triggers = provider.triggerCharacters
      local retriggers = provider.retriggerCharacters
      if (not triggers or #triggers == 0) and (not retriggers or #retriggers == 0) then
        return
      end
      setup_auto_trigger(trigger_group, args.buf, triggers, retriggers)
    end,
  })
end

return setmetatable(M, {
  __call = function(_)
    return M.signature_help()
  end,
})

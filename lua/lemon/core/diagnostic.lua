local M = {}

local glyph = require("lemon.glyph")
local extmarks_ui = require("lemon.ui.extmarks")
local FloatPanel = require("lemon.ui.float")
local PreviewManager = require("lemon.ui.preview")

local DiagnosticPanel = setmetatable({}, { __index = FloatPanel })
DiagnosticPanel.__index = DiagnosticPanel

local panel = DiagnosticPanel:new("diagnostic")
local preview = PreviewManager:new(panel)

local function get_client_name(namespace_id, bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local ok, ns = pcall(vim.lsp.diagnostic.get_namespace, client.id)
    if ok and ns == namespace_id then
      return client.name
    end
    local ok2, pull_ns = pcall(vim.lsp.diagnostic.get_namespace, client.id, true)
    if ok2 and pull_ns == namespace_id then
      return client.name
    end
  end
  return nil
end

function DiagnosticPanel:get_config()
  local cfg = require("lemon.config").get()
  return {
    border = cfg.hover.border,
    max_width = cfg.hover.max_width,
    max_height = cfg.hover.max_height,
    pad_right = cfg.hover.pad_right,
    close_key = cfg.hover.close_key,
    close_events = cfg.hover.close_events,
    scroll_indicator = cfg.hover.scroll_indicator,
    enter = true,
    diff_context = 3,
  }
end

function DiagnosticPanel:close()
  FloatPanel.close(self)
  preview:reset()
  self._actions = nil
  self._cursor_pos = nil
  self._action_start_line = 0
end

function DiagnosticPanel:build_content(cursor_pos)
  self._cursor_pos = cursor_pos
  self._action_start_line = 0
  local lnum = cursor_pos[1] - 1

  local diagnostics = vim.diagnostic.get(self.source_bufnr, { lnum = lnum })
  if #diagnostics == 0 then
    return {}, {}
  end

  table.sort(diagnostics, function(a, b)
    local code_a = tostring(a.code or "")
    local code_b = tostring(b.code or "")
    if code_a ~= code_b then
      local sev_a = math.huge
      local sev_b = math.huge
      for _, d in ipairs(diagnostics) do
        if tostring(d.code or "") == code_a and d.severity < sev_a then sev_a = d.severity end
        if tostring(d.code or "") == code_b and d.severity < sev_b then sev_b = d.severity end
      end
      if sev_a ~= sev_b then return sev_a < sev_b end
      return code_a < code_b
    end
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    return (a.source or "") < (b.source or "")
  end)

  local lines = {}
  local ext_list = {}

  local providers = {}
  for _, diag in ipairs(diagnostics) do
    local name = get_client_name(diag.namespace, self.source_bufnr) or diag.source or "LSP"
    if not providers[name] then
      providers[name] = true
      table.insert(lines, name)
      table.insert(ext_list, { sign = { icon = glyph.ui.server, hl = "LemonTitle" }, line_hl = "LemonTitle" })
    end
  end

  local last_code = nil
  for idx, diag in ipairs(diagnostics) do
    local code = diag.code and tostring(diag.code) or nil
    local is_child = code and code == last_code

    if is_child then
      local msg = "↳ " .. diag.message:gsub("\n", " "):gsub("%.$", "")
      local s = glyph.severity[diag.severity] or glyph.severity[4]
      table.insert(lines, msg)
      table.insert(ext_list, { sign = { icon = s.icon, hl = s.hl }, line_hl = s.hl })
    else
      if idx > 1 then
        table.insert(lines, "")
        table.insert(ext_list, {})
      end

      if code then
        table.insert(lines, code)
        table.insert(ext_list, { sign = { icon = glyph.ui.code, hl = "@label" }, line_hl = "@comment" })
      end

      table.insert(lines, "")
      table.insert(ext_list, {})

      local msg = diag.message:gsub("\n", " "):gsub("%.$", "")
      local s = glyph.severity[diag.severity] or glyph.severity[4]
      table.insert(lines, msg)
      table.insert(ext_list, { sign = { icon = s.icon, hl = s.hl }, line_hl = s.hl })
    end

    last_code = code
  end

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].modifiable = false
  vim.bo[self.buf].buftype = "nofile"

  return lines, ext_list
end

local function apply_action(action, client)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding or "utf-16")
  end
  if action.command then
    local command = type(action.command) == "table" and action.command or action
    client:exec_cmd(command)
  end
end

local function execute_action(idx)
  local entry = preview.action_cache[idx]
  if not entry then
    if #preview.action_cache == 0 then
      vim.notify("Lemon: No code actions available yet", vim.log.levels.INFO)
    end
    return
  end

  local source_bufnr = panel.source_bufnr

  panel:close()

  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    vim.notify("Lemon: Client not found for action", vim.log.levels.ERROR)
    return
  end

  local resolved = preview:get_resolved(idx)
  if resolved then
    apply_action(resolved, client)
    return
  end

  local action = entry.action
  if action.data and not action.edit then
    client:request("codeAction/resolve", action, function(err, r)
      if err then
        vim.notify("Code action resolve failed: " .. (err.message or "unknown error"), vim.log.levels.ERROR)
        return
      end
      vim.schedule(function()
        apply_action(r or action, client)
      end)
    end, source_bufnr)
  else
    apply_action(action, client)
  end
end

local function get_action_idx_at_cursor()
  if not panel:is_open() then
    return nil
  end
  if #preview.action_cache == 0 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(panel.win)[1]
  local action_idx = row - panel._action_start_line
  if action_idx >= 1 and action_idx <= #preview.action_cache then
    return action_idx
  end
  return nil
end

local function request_code_actions()
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    return
  end

  local source_bufnr = panel.source_bufnr
  local cursor_pos = panel._cursor_pos
  local target_buf = panel.buf
  if not cursor_pos then
    return
  end

  local clients = vim.lsp.get_clients({ bufnr = source_bufnr, method = "textDocument/codeAction" })
  if #clients == 0 then
    return
  end

  local lnum = cursor_pos[1] - 1
  local diagnostics = vim.diagnostic.get(source_bufnr, { lnum = lnum })

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(source_bufnr),
    range = {
      start = { line = lnum, character = 0 },
      ["end"] = { line = lnum, character = 0 },
    },
    context = {
      diagnostics = vim.tbl_map(function(d)
        return {
          range = {
            start = { line = d.lnum, character = d.col },
            ["end"] = { line = d.end_lnum or d.lnum, character = d.end_col or d.col },
          },
          severity = d.severity,
          code = d.code,
          source = d.source,
          message = d.message,
        }
      end, diagnostics),
      only = nil,
      triggerKind = 1,
    },
  }

  local pending = #clients
  local all_actions = {}

  for _, client in ipairs(clients) do
    client:request("textDocument/codeAction", params, function(err, result)
      if not err and result then
        for _, action in ipairs(result) do
          table.insert(all_actions, { action = action, client_id = client.id })
        end
      end
      pending = pending - 1
      if pending == 0 then
        vim.schedule(function()
          if #all_actions == 0 or not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
            return
          end

          local current_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
          panel._action_start_line = #current_lines + 1

          local action_lines = { "" }
          local action_extmarks = { {} }
          for i, entry in ipairs(all_actions) do
            local title = entry.action.title or "Action"
            table.insert(action_lines, title)
            local icon = glyph.numeric[i] or glyph.numeric[#glyph.numeric]
            table.insert(action_extmarks, { sign = { icon = icon, hl = "LemonActionNumber" }, line_hl = "Normal", text_hl = "Normal" })
          end

          vim.bo[target_buf].modifiable = true
          vim.api.nvim_buf_set_lines(target_buf, #current_lines, -1, false, action_lines)
          vim.bo[target_buf].modifiable = false

          extmarks_ui.apply(target_buf, "lemon_diagnostic", action_extmarks, action_lines, #current_lines)

          local new_total = vim.api.nvim_buf_line_count(target_buf)
          local new_height = math.min(new_total, math.floor(vim.api.nvim_get_option_value("lines", {}) * 0.4))
          if panel:is_open() then
            vim.api.nvim_win_set_config(panel.win, { height = new_height })
          end

          preview:attach(all_actions, panel._action_start_line + #all_actions)
        end)
      end
    end, source_bufnr)
  end
end

function DiagnosticPanel:setup_keymaps()
  FloatPanel.setup_keymaps(self)

  vim.api.nvim_buf_set_keymap(self.buf, "n", "<CR>", "", {
    callback = function()
      local action_idx = get_action_idx_at_cursor()
      if action_idx then
        execute_action(action_idx)
        return
      end
      if #preview.action_cache > 0 then
        return
      end
      request_code_actions()
    end,
    nowait = true,
  })

  for i = 1, 9 do
    vim.keymap.set("n", tostring(i), function()
      execute_action(i)
    end, { buffer = self.buf, nowait = true, silent = true })
  end
end

function DiagnosticPanel:setup_autocmds()
  FloatPanel.setup_autocmds(self)

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = self.augroup,
    buffer = self.buf,
    callback = function()
      local action_idx = get_action_idx_at_cursor()
      if action_idx then
        preview:update(action_idx)
      elseif preview.current_idx ~= 0 then
        preview:clear_preview()
      end
    end,
  })
end

function DiagnosticPanel:after_open()
  request_code_actions()
end

local function open_styled_float()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local lnum = cursor_pos[1] - 1
  local diagnostics = vim.diagnostic.get(source_bufnr, { lnum = lnum })
  if #diagnostics == 0 then
    return
  end

  panel:show(source_bufnr, cursor_pos)
end

function M.goto_next()
  vim.diagnostic.jump({ count = 1, float = false })
  vim.schedule(function()
    open_styled_float()
  end)
end

function M.goto_prev()
  vim.diagnostic.jump({ count = -1, float = false })
  vim.schedule(function()
    open_styled_float()
  end)
end

function M.open_float()
  open_styled_float()
end

return M

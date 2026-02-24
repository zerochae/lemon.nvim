local M = {}
local glyph = require("lemon.glyph")
local diff_ui = require("lemon.ui.diff")
local extmarks_ui = require("lemon.ui.extmarks")

local diag_win = nil
local diag_buf = nil
local action_cache = {}
local resolve_cache = {}
local diff_cache = {}
local action_start_line = 0
local current_preview_idx = 0
local updating_preview = false

local function close_float()
  local win, buf = diag_win, diag_buf
  diag_win = nil
  diag_buf = nil
  action_cache = {}
  resolve_cache = {}
  diff_cache = {}
  action_start_line = 0
  current_preview_idx = 0
  updating_preview = false

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace "lemon_diff_syntax", 0, -1)
  end
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

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

local function apply_action(action, client)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding or "utf-16")
  end
  if action.command then
    local command = type(action.command) == "table" and action.command or action
    client:exec_cmd(command)
  end
end

local function execute_action(idx, source_bufnr)
  local entry = action_cache[idx]
  if not entry then
    if #action_cache == 0 then
      vim.notify("Lemon: No code actions available yet", vim.log.levels.INFO)
    end
    return
  end

  close_float()

  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    vim.notify("Lemon: Client not found for action", vim.log.levels.ERROR)
    return
  end

  local resolved = resolve_cache[idx]
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
  if not diag_win or not vim.api.nvim_win_is_valid(diag_win) then
    return nil
  end
  if #action_cache == 0 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(diag_win)[1]
  local action_idx = row - action_start_line
  if action_idx >= 1 and action_idx <= #action_cache then
    return action_idx
  end
  return nil
end

local function update_action_preview(idx)
  if not diag_buf or not vim.api.nvim_buf_is_valid(diag_buf) then
    return
  end
  if not diag_win or not vim.api.nvim_win_is_valid(diag_win) then
    return
  end
  if idx == current_preview_idx then
    return
  end
  if updating_preview then
    return
  end

  current_preview_idx = idx
  local entry = action_cache[idx]
  if not entry then
    return
  end

  local ns = vim.api.nvim_create_namespace "lemon_diagnostic"
  local preview_start = action_start_line + #action_cache
  local preview_ft = nil
  local preview_code_info = nil

  local function render_preview(diff_lines, diff_extmarks)
    if current_preview_idx ~= idx then
      return
    end
    if not diag_buf or not vim.api.nvim_buf_is_valid(diag_buf) then
      return
    end

    local cfg = require("lemon.config").get()
    local columns = vim.api.nvim_get_option_value("columns", {})
    local max_width = math.floor(columns * cfg.hover.max_width)
    local sign_width = 2
    local cur_width = vim.api.nvim_win_get_width(diag_win)
    local max_content_len = cur_width - sign_width
    for _, l in ipairs(diff_lines) do
      local w = vim.fn.strdisplaywidth(l)
      if w > max_content_len then
        max_content_len = w
      end
    end
    local new_width = math.min(max_content_len + sign_width + cfg.hover.pad_right, max_width)
    new_width = math.max(new_width, cur_width)

    vim.bo[diag_buf].modifiable = true

    local total = vim.api.nvim_buf_line_count(diag_buf)
    if total > preview_start then
      vim.api.nvim_buf_set_lines(diag_buf, preview_start, total, false, {})
    end

    local separator = string.rep("─", new_width - 2)
    local preview_block = { separator }
    for _, l in ipairs(diff_lines) do
      table.insert(preview_block, l)
    end

    vim.api.nvim_buf_set_lines(diag_buf, preview_start, preview_start, false, preview_block)
    vim.bo[diag_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(diag_buf, ns, preview_start, -1)
    vim.api.nvim_buf_set_extmark(diag_buf, ns, preview_start, 0, {
      end_col = #separator,
      hl_group = "FloatBorder",
    })
    extmarks_ui.apply(diag_buf, "lemon_diagnostic", diff_extmarks, diff_lines, preview_start + 1)
    diff_ui.apply_syntax(diag_buf, preview_code_info, preview_ft, preview_start + 1)

    local new_total = vim.api.nvim_buf_line_count(diag_buf)
    local editor_lines = vim.api.nvim_get_option_value("lines", {})
    local max_height = math.floor(editor_lines * cfg.hover.max_height)
    local new_height = math.min(new_total, max_height)
    new_height = math.max(new_height, action_start_line + #action_cache + 1)
    vim.api.nvim_win_set_config(diag_win, { height = new_height, width = new_width })

    updating_preview = false
  end

  if diff_cache[idx] then
    preview_ft = diff_cache[idx].ft
    preview_code_info = diff_cache[idx].code_info
    render_preview(diff_cache[idx].lines, diff_cache[idx].extmarks)
    return
  end

  if resolve_cache[idx] then
    local resolved = resolve_cache[idx]
    if not resolved.edit then
      local lines = { "No preview available — Enter to execute" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
      return
    end
    local diffs =
      diff_ui.compute(resolved.edit, vim.lsp.get_client_by_id(entry.client_id).offset_encoding or "utf-16", 3)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff_ui.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      render_preview(lines, ext)
    end
    return
  end

  local action = entry.action

  if action.edit then
    resolve_cache[idx] = action
    local client = vim.lsp.get_client_by_id(entry.client_id)
    local encoding = client and client.offset_encoding or "utf-16"
    local diffs = diff_ui.compute(action.edit, encoding, 3)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff_ui.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      render_preview(lines, ext)
    end
    return
  end

  updating_preview = true
  local loading_lines = { "Resolving..." }
  local loading_ext =
    { { sign = { icon = glyph.ui.loading, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
  render_preview(loading_lines, loading_ext)
  updating_preview = true

  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    updating_preview = false
    return
  end

  client:request("codeAction/resolve", action, function(err, resolved)
    vim.schedule(function()
      if err or not resolved then
        resolve_cache[idx] = action
        local lines = { "Resolve failed" }
        local ext = {
          {
            sign = { icon = glyph.ui.error, hl = "DiagnosticError" },
            line_hl = "DiagnosticError",
            text_hl = "DiagnosticError",
          },
        }
        diff_cache[idx] = { lines = lines, extmarks = ext }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      resolve_cache[idx] = resolved
      local encoding = client.offset_encoding or "utf-16"

      if not resolved.edit then
        local lines = { "No preview available — Enter to execute" }
        local ext =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        diff_cache[idx] = { lines = lines, extmarks = ext }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      local diffs = diff_ui.compute(resolved.edit, encoding, 3)
      if #diffs == 0 then
        local lines = { "No changes detected" }
        local ext =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        diff_cache[idx] = { lines = lines, extmarks = ext }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      local lines, ext, ft, code_info = diff_ui.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      updating_preview = false
      if current_preview_idx == idx then
        render_preview(lines, ext)
      end
    end)
  end, diag_buf)
end

local function make_action_handler(idx, source_bufnr)
  return function()
    execute_action(idx, source_bufnr)
  end
end

local function request_code_actions(source_bufnr, cursor_pos, target_buf)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
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

          action_cache = all_actions

          local current_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
          action_start_line = #current_lines + 1

          local action_lines = { "" }
          local action_extmarks = { {} }
          for i, entry in ipairs(all_actions) do
            local title = entry.action.title or "Action"
            table.insert(action_lines, title)
            local icon = glyph.numeric[i] or glyph.numeric[#glyph.numeric]
            table.insert(
              action_extmarks,
              { sign = { icon = icon, hl = "LemonActionNumber" }, line_hl = "Normal", text_hl = "Normal" }
            )
          end

          vim.bo[target_buf].modifiable = true
          vim.api.nvim_buf_set_lines(target_buf, #current_lines, -1, false, action_lines)
          vim.bo[target_buf].modifiable = false

          extmarks_ui.apply(target_buf, "lemon_diagnostic", action_extmarks, action_lines, #current_lines)

          local new_total = vim.api.nvim_buf_line_count(target_buf)
          local new_height = math.min(new_total, math.floor(vim.api.nvim_get_option_value("lines", {}) * 0.4))
          if diag_win and vim.api.nvim_win_is_valid(diag_win) then
            vim.api.nvim_win_set_config(diag_win, { height = new_height })
          end
        end)
      end
    end, source_bufnr)
  end
end

local function open_styled_float(enter)
  close_float()
  action_cache = {}
  resolve_cache = {}
  diff_cache = {}

  local cfg = require("lemon.config").get()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local lnum = cursor_pos[1] - 1

  local diagnostics = vim.diagnostic.get(source_bufnr, { lnum = lnum })
  if #diagnostics == 0 then
    return
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
    local name = get_client_name(diag.namespace, source_bufnr) or diag.source or "LSP"
    if not providers[name] then
      providers[name] = true
      table.insert(lines, name)
      table.insert(ext_list, { sign = { icon = glyph.ui.server, hl = "LemonTitle" }, line_hl = "LemonTitle" })
    end
  end

  local last_code = nil
  for idx, diag in ipairs(diagnostics) do
    local code = diag.code and tostring(diag.code) or nil
    local same_code = code and code == last_code
    local is_child = same_code

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

  local win_opts = require("lemon.ui.window").compute(lines, {
    max_width = cfg.hover.max_width,
    max_height = cfg.hover.max_height,
    pad_right = cfg.hover.pad_right,
  })

  diag_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(diag_buf, 0, -1, false, lines)
  vim.bo[diag_buf].modifiable = false
  vim.bo[diag_buf].buftype = "nofile"

  diag_win = vim.api.nvim_open_win(diag_buf, enter or false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = win_opts.width,
    height = win_opts.height,
    border = cfg.hover.border,
    style = "minimal",
  })

  vim.api.nvim_set_option_value("winhighlight", "Normal:LemonNormal,FloatBorder:LemonBorder,SignColumn:LemonNormal", { win = diag_win })
  vim.api.nvim_set_option_value("signcolumn", "yes", { win = diag_win })
  vim.api.nvim_set_option_value("wrap", true, { win = diag_win })

  if enter then
    vim.api.nvim_set_current_win(diag_win)
  end

  extmarks_ui.apply(diag_buf, "lemon_diagnostic", ext_list, lines, 0)

  local total_lines_count = vim.api.nvim_buf_line_count(diag_buf)
  local scrollable = total_lines_count > win_opts.height
  if scrollable and cfg.hover.scroll_indicator then
    require("lemon.ui.scrollbar").update(diag_win, total_lines_count)
  end

  vim.api.nvim_buf_set_keymap(diag_buf, "n", cfg.hover.close_key, "", {
    callback = close_float,
    nowait = true,
  })

  vim.api.nvim_buf_set_keymap(diag_buf, "n", "<CR>", "", {
    callback = function()
      local action_idx = get_action_idx_at_cursor()
      if action_idx then
        execute_action(action_idx, source_bufnr)
        return
      end
      if #action_cache > 0 then
        return
      end
      request_code_actions(source_bufnr, cursor_pos, diag_buf)
    end,
    nowait = true,
  })

  for i = 1, 9 do
    vim.keymap.set("n", tostring(i), make_action_handler(i, source_bufnr), {
      buffer = diag_buf,
      nowait = true,
      silent = true,
    })
  end

  local augroup = vim.api.nvim_create_augroup("lemon_diag_close", { clear = true })
  for _, event in ipairs(cfg.hover.close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      buffer = source_bufnr,
      once = true,
      callback = close_float,
    })
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = diag_buf,
    callback = function()
      local action_idx = get_action_idx_at_cursor()
      if action_idx then
        update_action_preview(action_idx)
      elseif current_preview_idx ~= 0 then
        current_preview_idx = 0
        local preview_start = action_start_line + #action_cache
        vim.bo[diag_buf].modifiable = true
        local total = vim.api.nvim_buf_line_count(diag_buf)
        if total > preview_start then
          vim.api.nvim_buf_set_lines(diag_buf, preview_start, total, false, {})
        end
        vim.bo[diag_buf].modifiable = false
        vim.api.nvim_buf_clear_namespace(diag_buf, vim.api.nvim_create_namespace "lemon_diff_syntax", 0, -1)
      end
    end,
  })

  if scrollable and cfg.hover.scroll_indicator then
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = augroup,
      callback = function()
        if diag_win and vim.api.nvim_win_is_valid(diag_win) then
          require("lemon.ui.scrollbar").update(diag_win, vim.api.nvim_buf_line_count(diag_buf))
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(diag_win),
    once = true,
    callback = function()
      close_float()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })

  request_code_actions(source_bufnr, cursor_pos, diag_buf)
end

function M.goto_next()
  vim.diagnostic.jump({ count = 1, float = false })
  vim.schedule(function()
    open_styled_float(true)
  end)
end

function M.goto_prev()
  vim.diagnostic.jump({ count = -1, float = false })
  vim.schedule(function()
    open_styled_float(true)
  end)
end

function M.open_float()
  open_styled_float(true)
end

return M

local M = {}

local glyph = require "lemon.glyph"
local diff = require "lemon.ui.diff"
local extmarks = require "lemon.ui.extmarks"

local action_win = nil
local action_buf = nil
local action_cache = {}
local resolve_cache = {}
local diff_cache = {}
local source_bufnr = nil
local list_count = 0
local current_preview_idx = 0
local updating_preview = false

local function close_float()
  local win, buf = action_win, action_buf
  action_win = nil
  action_buf = nil
  action_cache = {}
  resolve_cache = {}
  diff_cache = {}
  source_bufnr = nil
  list_count = 0
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

local function get_cfg()
  return require("lemon.config").get().code_action
end

local function update_preview(idx)
  if not action_buf or not vim.api.nvim_buf_is_valid(action_buf) then
    return
  end
  if not action_win or not vim.api.nvim_win_is_valid(action_win) then
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

  local ns = vim.api.nvim_create_namespace "lemon_code_action"
  local separator_start = list_count
  local preview_ft = nil
  local preview_code_info = nil

  local function render_preview(diff_lines, diff_extmarks)
    if current_preview_idx ~= idx then
      return
    end
    if not action_buf or not vim.api.nvim_buf_is_valid(action_buf) then
      return
    end

    local cfg = get_cfg()
    local columns = vim.api.nvim_get_option_value("columns", {})
    local max_width = math.floor(columns * cfg.max_width)
    local sign_width = 2
    local cur_width = vim.api.nvim_win_get_width(action_win)
    local max_content_len = cur_width - sign_width
    for _, l in ipairs(diff_lines) do
      local w = vim.fn.strdisplaywidth(l)
      if w > max_content_len then
        max_content_len = w
      end
    end
    local new_width = math.min(max_content_len + sign_width + cfg.pad_right, max_width)
    new_width = math.max(new_width, cur_width)

    vim.bo[action_buf].modifiable = true

    local total = vim.api.nvim_buf_line_count(action_buf)
    if total > separator_start then
      vim.api.nvim_buf_set_lines(action_buf, separator_start, total, false, {})
    end

    local separator = string.rep("─", new_width - 2)
    local preview_block = { separator }
    for _, l in ipairs(diff_lines) do
      table.insert(preview_block, l)
    end

    vim.api.nvim_buf_set_lines(action_buf, separator_start, separator_start, false, preview_block)
    vim.bo[action_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(action_buf, ns, separator_start, -1)
    vim.api.nvim_buf_set_extmark(action_buf, ns, separator_start, 0, {
      end_col = #separator,
      hl_group = "FloatBorder",
    })
    extmarks.apply(action_buf, "lemon_code_action", diff_extmarks, diff_lines, separator_start + 1)
    diff.apply_syntax(action_buf, preview_code_info, preview_ft, separator_start + 1)

    local new_total = vim.api.nvim_buf_line_count(action_buf)
    local editor_lines = vim.api.nvim_get_option_value("lines", {})
    local max_height = math.floor(editor_lines * cfg.max_height)
    local new_height = math.min(new_total, max_height)
    new_height = math.max(new_height, list_count + 1)
    vim.api.nvim_win_set_config(action_win, { height = new_height, width = new_width })

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
    local cfg = get_cfg()
    local diffs =
      diff.compute(resolved.edit, vim.lsp.get_client_by_id(entry.client_id).offset_encoding or "utf-16", cfg.diff_context)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff.build_lines(diffs)
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
    local cfg = get_cfg()
    local diffs = diff.compute(action.edit, encoding, cfg.diff_context)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff.build_lines(diffs)
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

      local cfg = get_cfg()
      local diffs = diff.compute(resolved.edit, encoding, cfg.diff_context)
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

      local lines, ext, ft, code_info = diff.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      updating_preview = false
      if current_preview_idx == idx then
        render_preview(lines, ext)
      end
    end)
  end, source_bufnr)
end

local function apply_action_at(idx)
  local entry = action_cache[idx]
  if not entry then
    return
  end

  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    vim.notify("Lemon: Client not found", vim.log.levels.ERROR)
    return
  end

  close_float()

  local resolved = resolve_cache[idx] or entry.action
  if resolved.edit then
    vim.lsp.util.apply_workspace_edit(resolved.edit, client.offset_encoding or "utf-16")
  end
  if resolved.command then
    local command = type(resolved.command) == "table" and resolved.command or resolved
    client:exec_cmd(command)
  end
end

local function get_cursor_action_idx()
  if not action_win or not vim.api.nvim_win_is_valid(action_win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(action_win)[1]
  if row >= 1 and row <= list_count then
    return row
  end
  return nil
end

local function clamp_cursor()
  if not action_win or not vim.api.nvim_win_is_valid(action_win) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(action_win)[1]
  if row > list_count then
    vim.api.nvim_win_set_cursor(action_win, { list_count, 0 })
  elseif row < 1 then
    vim.api.nvim_win_set_cursor(action_win, { 1, 0 })
  end
end

local function on_cursor_moved()
  clamp_cursor()
  local idx = get_cursor_action_idx()
  if idx then
    update_preview(idx)
  end
end

local function render_ui(actions)
  local cfg = get_cfg()
  action_cache = actions
  list_count = #actions

  local lines = {}
  local ext_list = {}

  for i, entry in ipairs(actions) do
    local title = entry.action.title or "Action"
    table.insert(lines, title)
    local icon = glyph.numeric[i] or glyph.numeric[#glyph.numeric]
    table.insert(
      ext_list,
      { sign = { icon = icon, hl = "LemonActionNumber" }, line_hl = "Normal", text_hl = "Normal" }
    )
  end

  local win_opts = require("lemon.ui.window").compute(lines, {
    max_width = cfg.max_width,
    max_height = cfg.max_height,
    pad_right = cfg.pad_right,
    min_width = 30,
    min_height = #lines + 1,
    extra_height = 2,
  })

  action_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(action_buf, 0, -1, false, lines)
  vim.bo[action_buf].modifiable = false
  vim.bo[action_buf].buftype = "nofile"

  action_win = vim.api.nvim_open_win(action_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = win_opts.width,
    height = win_opts.height,
    border = cfg.border,
    style = "minimal",
  })

  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:LemonNormal,FloatBorder:LemonBorder,SignColumn:LemonNormal",
    { win = action_win }
  )
  vim.api.nvim_set_option_value("signcolumn", "yes", { win = action_win })
  vim.api.nvim_set_option_value("wrap", true, { win = action_win })
  vim.api.nvim_set_option_value("cursorline", true, { win = action_win })
  vim.api.nvim_set_current_win(action_win)

  extmarks.apply(action_buf, "lemon_code_action", ext_list, lines, 0)

  vim.keymap.set("n", cfg.close_key, close_float, { buffer = action_buf, nowait = true, silent = true })
  vim.keymap.set("n", cfg.back_key, close_float, { buffer = action_buf, nowait = true, silent = true })

  vim.keymap.set("n", cfg.confirm_key, function()
    local idx = get_cursor_action_idx()
    if idx then
      apply_action_at(idx)
    end
  end, { buffer = action_buf, nowait = true, silent = true })

  for i = 1, math.min(9, #actions) do
    vim.keymap.set("n", tostring(i), function()
      if action_cache[i] then
        apply_action_at(i)
      end
    end, { buffer = action_buf, nowait = true, silent = true })
  end

  local augroup = vim.api.nvim_create_augroup("lemon_code_action_close", { clear = true })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = action_buf,
    callback = on_cursor_moved,
  })

  for _, event in ipairs(cfg.close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      buffer = source_bufnr,
      once = true,
      callback = close_float,
    })
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(action_win),
    once = true,
    callback = function()
      close_float()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })

  vim.api.nvim_win_set_cursor(action_win, { 1, 0 })
  update_preview(1)
end

function M.code_action()
  close_float()

  source_bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  local clients = vim.lsp.get_clients { bufnr = source_bufnr, method = "textDocument/codeAction" }
  if #clients == 0 then
    vim.notify("Lemon: No LSP clients support code actions", vim.log.levels.INFO)
    return
  end

  local lnum = cursor_pos[1] - 1
  local col = cursor_pos[2]
  local diagnostics = vim.diagnostic.get(source_bufnr, { lnum = lnum })

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(source_bufnr),
    range = {
      start = { line = lnum, character = col },
      ["end"] = { line = lnum, character = col },
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
          if #all_actions == 0 then
            vim.notify("Lemon: No code actions available", vim.log.levels.INFO)
            return
          end
          render_ui(all_actions)
        end)
      end
    end, source_bufnr)
  end
end

return M

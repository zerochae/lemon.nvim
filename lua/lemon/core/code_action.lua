local M = {}

local glyph = require "lemon.glyph"

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
    vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace "lemon_code_action_syntax", 0, -1)
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

local function compute_diff_for_edit(workspace_edit, encoding)
  local result = {}
  local changes = workspace_edit.changes or {}

  if workspace_edit.documentChanges then
    for _, change in ipairs(workspace_edit.documentChanges) do
      if change.textDocument and change.edits then
        changes[change.textDocument.uri] = change.edits
      end
    end
  end

  for uri, edits in pairs(changes) do
    local filepath = vim.uri_to_fname(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    local was_loaded = vim.api.nvim_buf_is_loaded(bufnr)

    if not was_loaded then
      vim.fn.bufload(bufnr)
    end

    local old_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local old_text = table.concat(old_lines, "\n") .. "\n"

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, old_lines)
    vim.lsp.util.apply_text_edits(edits, scratch, encoding)
    local new_lines = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)
    local new_text = table.concat(new_lines, "\n") .. "\n"
    vim.api.nvim_buf_delete(scratch, { force = true })

    if not was_loaded then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    if old_text ~= new_text then
      local cfg = get_cfg()
      local diff = vim.diff(old_text, new_text, { result_type = "unified", ctxlen = cfg.diff_context })
      if diff and #diff > 0 then
        table.insert(result, { filepath = filepath, diff = diff })
      end
    end
  end

  return result
end

local function build_diff_lines(diffs)
  local lines = {}
  local extmarks = {}
  local ft = nil
  local del_lines = {}
  local del_offsets = {}
  local add_lines = {}
  local add_offsets = {}

  for _, file_diff in ipairs(diffs) do
    if not ft then
      ft = vim.filetype.match { filename = file_diff.filepath }
    end

    local short_path = vim.fn.fnamemodify(file_diff.filepath, ":~:.")
    local fname = vim.fn.fnamemodify(file_diff.filepath, ":t")
    local ext = vim.fn.fnamemodify(file_diff.filepath, ":e")
    local file_icon, file_hl = glyph.ui.file, "LemonDiffFile"
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
      local di, dh = devicons.get_icon(fname, ext, { default = true })
      if di then
        file_icon, file_hl = di, dh
      end
    end
    table.insert(lines, short_path)
    table.insert(
      extmarks,
      { sign = { icon = file_icon, hl = file_hl }, line_hl = "LemonDiffFile", text_hl = "LemonDiffFile" }
    )

    for diff_line in file_diff.diff:gmatch "[^\n]+" do
      if diff_line:match "^%-%-%-" or diff_line:match "^%+%+%+" then
      elseif diff_line:match "^@@" then
        local del_start, del_count, add_start, add_count = diff_line:match "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@"
        del_count = tonumber(del_count) or 1
        add_count = tonumber(add_count) or 1
        local parts = {}
        if del_count > 0 then
          table.insert(parts, string.format("%s %d:%d", glyph.diff.hunk_del, del_start or 0, del_count))
        end
        if add_count > 0 then
          table.insert(parts, string.format("%s %d:%d", glyph.diff.hunk_add, add_start or 0, add_count))
        end
        local hunk_text = table.concat(parts, "  ")
        table.insert(lines, hunk_text)
        table.insert(extmarks, {
          sign = { icon = glyph.diff.hunk_sign, hl = "LemonDiffHunk" },
          line_hl = "LemonDiffHunk",
          text_hl = "LemonDiffHunk",
        })
      elseif diff_line:match "^%+" then
        table.insert(lines, diff_line:sub(2))
        table.insert(extmarks, { sign = { icon = glyph.diff.add, hl = "LemonDiffAddSign" }, line_hl = "LemonDiffAdd" })
        table.insert(add_lines, diff_line:sub(2))
        table.insert(add_offsets, #lines - 1)
      elseif diff_line:match "^%-" then
        table.insert(lines, diff_line:sub(2))
        table.insert(
          extmarks,
          { sign = { icon = glyph.diff.delete, hl = "LemonDiffDeleteSign" }, line_hl = "LemonDiffDelete" }
        )
        table.insert(del_lines, diff_line:sub(2))
        table.insert(del_offsets, #lines - 1)
      else
        local content = diff_line:sub(1, 1) == " " and diff_line:sub(2) or diff_line
        table.insert(lines, diff_line)
        table.insert(extmarks, {})
        table.insert(del_lines, content)
        table.insert(del_offsets, #lines - 1)
        table.insert(add_lines, content)
        table.insert(add_offsets, #lines - 1)
      end
    end
  end

  local code_info = nil
  if #del_lines > 0 or #add_lines > 0 then
    code_info = {
      del = #del_lines > 0 and { text = table.concat(del_lines, "\n"), offsets = del_offsets } or nil,
      add = #add_lines > 0 and { text = table.concat(add_lines, "\n"), offsets = add_offsets } or nil,
    }
  end

  return lines, extmarks, ft, code_info
end

local function apply_extmarks(buf, ext_list, lines, offset)
  local ns = vim.api.nvim_create_namespace "lemon_code_action"
  for i, ext in ipairs(ext_list) do
    local row = offset + i - 1
    local opts = {}
    if ext.sign then
      opts.sign_text = ext.sign.icon
      opts.sign_hl_group = ext.sign.hl
    end
    if ext.line_hl then
      opts.line_hl_group = ext.line_hl
    end
    if ext.text_hl then
      local line_text = lines[i] or ""
      if #line_text > 0 then
        opts.end_col = #line_text
        opts.hl_group = ext.text_hl
      end
    end
    if next(opts) then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
    end
  end
end

local function apply_syntax_highlights(buf, code_info, ft, buf_offset)
  local syntax_ns = vim.api.nvim_create_namespace "lemon_code_action_syntax"
  vim.api.nvim_buf_clear_namespace(buf, syntax_ns, 0, -1)

  if not code_info or not ft then
    return
  end

  local lang = vim.treesitter.language.get_lang(ft)
  if not lang then
    return
  end

  local ok2, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok2 or not query then
    return
  end

  local groups = {}
  if code_info.del then
    table.insert(groups, code_info.del)
  end
  if code_info.add then
    table.insert(groups, code_info.add)
  end

  for _, group in ipairs(groups) do
    local ok, parser = pcall(vim.treesitter.get_string_parser, group.text, lang)
    if ok and parser then
      local trees = parser:parse()
      if trees and #trees > 0 then
        local captures = {}
        for id, node in query:iter_captures(trees[1]:root(), group.text) do
          local name = "@" .. query.captures[id]
          local sr, sc, er, ec = node:range()
          local key = sr .. ":" .. sc .. ":" .. er .. ":" .. ec
          captures[key] = { name = name, sr = sr, sc = sc, er = er, ec = ec }
        end
        for _, cap in pairs(captures) do
          local buf_sr = group.offsets[cap.sr + 1]
          local buf_er = group.offsets[cap.er + 1]
          if buf_sr and buf_er then
            pcall(vim.api.nvim_buf_set_extmark, buf, syntax_ns, buf_offset + buf_sr, cap.sc, {
              end_row = buf_offset + buf_er,
              end_col = cap.ec,
              hl_group = cap.name,
              priority = 50,
            })
          end
        end
      end
    end
  end
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
    apply_extmarks(action_buf, diff_extmarks, diff_lines, separator_start + 1)
    apply_syntax_highlights(action_buf, preview_code_info, preview_ft, separator_start + 1)

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
      local extmarks =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = extmarks }
      render_preview(lines, extmarks)
      return
    end
    local diffs =
      compute_diff_for_edit(resolved.edit, vim.lsp.get_client_by_id(entry.client_id).offset_encoding or "utf-16")
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local extmarks =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = extmarks }
      render_preview(lines, extmarks)
    else
      local lines, extmarks, ft, code_info = build_diff_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = extmarks, ft = ft, code_info = code_info }
      render_preview(lines, extmarks)
    end
    return
  end

  local action = entry.action

  if action.edit then
    resolve_cache[idx] = action
    local client = vim.lsp.get_client_by_id(entry.client_id)
    local encoding = client and client.offset_encoding or "utf-16"
    local diffs = compute_diff_for_edit(action.edit, encoding)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local extmarks =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      diff_cache[idx] = { lines = lines, extmarks = extmarks }
      render_preview(lines, extmarks)
    else
      local lines, extmarks, ft, code_info = build_diff_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = extmarks, ft = ft, code_info = code_info }
      render_preview(lines, extmarks)
    end
    return
  end

  updating_preview = true
  local loading_lines = { "Resolving..." }
  local loading_extmarks =
    { { sign = { icon = glyph.ui.loading, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
  render_preview(loading_lines, loading_extmarks)
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
        local extmarks = {
          {
            sign = { icon = glyph.ui.error, hl = "DiagnosticError" },
            line_hl = "DiagnosticError",
            text_hl = "DiagnosticError",
          },
        }
        diff_cache[idx] = { lines = lines, extmarks = extmarks }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, extmarks)
        end
        return
      end

      resolve_cache[idx] = resolved
      local encoding = client.offset_encoding or "utf-16"

      if not resolved.edit then
        local lines = { "No preview available — Enter to execute" }
        local extmarks =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        diff_cache[idx] = { lines = lines, extmarks = extmarks }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, extmarks)
        end
        return
      end

      local diffs = compute_diff_for_edit(resolved.edit, encoding)
      if #diffs == 0 then
        local lines = { "No changes detected" }
        local extmarks =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        diff_cache[idx] = { lines = lines, extmarks = extmarks }
        updating_preview = false
        if current_preview_idx == idx then
          render_preview(lines, extmarks)
        end
        return
      end

      local lines, extmarks, ft, code_info = build_diff_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      diff_cache[idx] = { lines = lines, extmarks = extmarks, ft = ft, code_info = code_info }
      updating_preview = false
      if current_preview_idx == idx then
        render_preview(lines, extmarks)
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
  local extmarks = {}

  for i, entry in ipairs(actions) do
    local title = entry.action.title or "Action"
    table.insert(lines, title)
    local icon = glyph.numeric[i] or glyph.numeric[#glyph.numeric]
    table.insert(
      extmarks,
      { sign = { icon = icon, hl = "LemonActionNumber" }, line_hl = "Normal", text_hl = "Normal" }
    )
  end

  local columns = vim.api.nvim_get_option_value("columns", {})
  local editor_lines = vim.api.nvim_get_option_value("lines", {})
  local max_width = math.floor(columns * cfg.max_width)
  local max_height = math.floor(editor_lines * cfg.max_height)

  local max_content_len = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_content_len then
      max_content_len = w
    end
  end

  local sign_width = 2
  local width = math.min(max_content_len + sign_width, max_width) + cfg.pad_right
  width = math.max(width, 30)

  local height = math.min(#lines + 2, max_height)
  height = math.max(height, #lines + 1)

  action_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(action_buf, 0, -1, false, lines)
  vim.bo[action_buf].modifiable = false
  vim.bo[action_buf].buftype = "nofile"

  action_win = vim.api.nvim_open_win(action_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
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

  local ns = vim.api.nvim_create_namespace "lemon_code_action"
  apply_extmarks(action_buf, extmarks, lines, 0)

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

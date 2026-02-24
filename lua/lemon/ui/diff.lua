local M = {}

local glyph = require "lemon.glyph"

function M.compute(workspace_edit, encoding, ctxlen)
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
      local diff = vim.diff(old_text, new_text, { result_type = "unified", ctxlen = ctxlen or 3 })
      if diff and #diff > 0 then
        table.insert(result, { filepath = filepath, diff = diff })
      end
    end
  end

  return result
end

function M.build_lines(diffs)
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

function M.apply_syntax(buf, code_info, ft, buf_offset)
  local syntax_ns = vim.api.nvim_create_namespace "lemon_diff_syntax"
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

return M

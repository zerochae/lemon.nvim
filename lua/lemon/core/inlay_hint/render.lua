local M = {}

local format = require "lemon.core.inlay_hint.format"
local iconify = require "lemon.core.inlay_hint.iconify"

local function get_cfg()
  return require("lemon.config").get().inlay_hint
end

local function cwidth(cks)
  local w = 0
  for _, c in ipairs(cks) do
    w = w + vim.fn.strdisplaywidth(c[1])
  end
  return w
end

local function wrap_chunks(cks, max_w)
  local total = cwidth(cks)
  if total <= max_w or max_w <= 0 then
    return { cks }
  end
  local lines = { {} }
  local lw = 0
  for _, chunk in ipairs(cks) do
    local text = chunk[1]
    local hl = chunk[2]
    local w = vim.fn.strdisplaywidth(text)
    if lw + w <= max_w then
      table.insert(lines[#lines], { text, hl })
      lw = lw + w
    elseif w <= max_w then
      table.insert(lines, { { text, hl } })
      lw = w
    else
      local remaining = text
      while remaining ~= "" do
        local avail = max_w - lw
        if avail <= 0 then
          table.insert(lines, {})
          lw = 0
          avail = max_w
        end
        local nchars = vim.fn.strchars(remaining)
        local taken = 0
        local pw = 0
        for ci = 0, nchars - 1 do
          local ch = vim.fn.strcharpart(remaining, ci, 1)
          local cw = vim.fn.strdisplaywidth(ch)
          if pw + cw > avail and taken > 0 then
            break
          end
          taken = taken + 1
          pw = pw + cw
        end
        if taken == 0 then
          break
        end
        local part = vim.fn.strcharpart(remaining, 0, taken)
        table.insert(lines[#lines], { part, hl })
        lw = lw + pw
        remaining = vim.fn.strcharpart(remaining, taken)
      end
    end
  end
  return lines
end

function M.render(bufnr, state, ns)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not state or not state.enabled then
    return
  end

  local cfg = get_cfg()

  local visible_start = vim.fn.line "w0" - 1
  local visible_end = vim.fn.line "w$" - 1

  vim.api.nvim_buf_clear_namespace(bufnr, ns, visible_start, visible_end + 1)

  local hints_by_pos = {}
  for _, client_hints in pairs(state.client_hints) do
    for lnum, hints in pairs(client_hints) do
      if lnum >= visible_start and lnum <= visible_end then
        for _, hint in ipairs(hints) do
          local col = hint._col or 0
          local key = lnum .. ":" .. col
          if not hints_by_pos[key] then
            hints_by_pos[key] = { lnum = lnum, col = col, hints = {} }
          end
          table.insert(hints_by_pos[key].hints, hint)
        end
      end
    end
  end

  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  local current_line
  if cfg.only_current_line then
    current_line = cursor_lnum
  end

  local render_entries = {}
  local line_inline_widths = {}

  for key, pos in pairs(hints_by_pos) do
    if not current_line or pos.lnum == current_line then
      local chunks = {}
      local use_eol = false
      local on_cursor = pos.lnum == cursor_lnum
      local expand_data = nil

      for _, hint in ipairs(pos.hints) do
        local result = format.format_hint(hint, cfg)
        if result then
          for _, chunk in ipairs(result.chunks) do
            table.insert(chunks, chunk)
          end
          if result.eol then
            use_eol = true
          end
          if on_cursor and result.expand then
            expand_data = result.expand
          end
        end
      end

      line_inline_widths[pos.lnum] = (line_inline_widths[pos.lnum] or 0) + cwidth(chunks)

      table.insert(render_entries, {
        key = key,
        pos = pos,
        chunks = chunks,
        use_eol = use_eol,
        expand_data = expand_data,
      })
    end
  end

  for _, entry in ipairs(render_entries) do
    local pos = entry.pos
    local chunks = entry.chunks

    if #chunks > 0 then
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if pos.lnum >= line_count then
        goto continue_render
      end
      local line = vim.api.nvim_buf_get_lines(bufnr, pos.lnum, pos.lnum + 1, false)[1]
      local col = line and math.min(pos.col, #line) or 0
      vim.api.nvim_buf_set_extmark(bufnr, ns, pos.lnum, col, {
        virt_text = chunks,
        virt_text_pos = entry.use_eol and "eol" or cfg.position,
        hl_mode = "combine",
        priority = 2047,
      })
    end
    ::continue_render::
  end

  local expand_line_offset = 0

  for _, entry in ipairs(render_entries) do
    local expand_data = entry.expand_data
    if expand_data then
      local pos = entry.pos
      local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      local win_width = vim.api.nvim_win_get_width(0) - (wininfo and wininfo.textoff or 0)
      local leftcol = vim.fn.winsaveview().leftcol or 0
      local line_count = vim.api.nvim_buf_line_count(bufnr)

      local function calc_win_col()
        local line_text = vim.api.nvim_buf_get_lines(bufnr, pos.lnum, pos.lnum + 1, false)[1] or ""
        local line_w = vim.fn.strdisplaywidth(line_text)
        local iw = line_inline_widths[pos.lnum] or 0
        return math.max(line_w + iw - leftcol + 2, math.floor(win_width * (cfg.expand_offset or 0.6)))
      end

      local function render_expand_list(prefix_chunks, item_chunk_list)
        local win_col = calc_win_col()
        local prefix_w = cwidth(prefix_chunks)
        local item_col = win_col + prefix_w
        local avail = win_width - item_col

        local render_lines = {}
        for _, ichunks in ipairs(item_chunk_list) do
          local border = ichunks[1]
          local content = {}
          for ci = 2, #ichunks do
            table.insert(content, ichunks[ci])
          end
          local border_w = vim.fn.strdisplaywidth(border[1])
          local wrapped = wrap_chunks(content, avail - border_w)
          for _, wline in ipairs(wrapped) do
            local full = { border }
            for _, c in ipairs(wline) do
              table.insert(full, c)
            end
            table.insert(render_lines, full)
          end
        end

        local header_chunks = {}
        for _, c in ipairs(prefix_chunks) do
          table.insert(header_chunks, c)
        end
        for _, c in ipairs(render_lines[1]) do
          table.insert(header_chunks, c)
        end

        local header_lnum = pos.lnum + expand_line_offset
        if header_lnum < line_count then
          vim.api.nvim_buf_set_extmark(bufnr, ns, header_lnum, 0, {
            virt_text = header_chunks,
            virt_text_win_col = expand_line_offset == 0 and win_col or item_col,
            priority = 2047,
            hl_mode = "replace",
          })
        end

        for idx = 2, #render_lines do
          local target_lnum = pos.lnum + expand_line_offset + (idx - 1)
          if target_lnum < line_count then
            vim.api.nvim_buf_set_extmark(bufnr, ns, target_lnum, 0, {
              virt_text = render_lines[idx],
              virt_text_pos = "overlay",
              virt_text_win_col = item_col,
              priority = 2047,
              hl_mode = "replace",
            })
          end
        end

        return #render_lines
      end

      local lines_used = 0

      if expand_data.fields then
        local fields = expand_data.fields
        local obj_hl = expand_data.obj_hl
        local max_name_len = 0
        for _, field in ipairs(fields) do
          max_name_len = math.max(max_name_len, #field.name)
        end

        local prefix = " ← " .. expand_data.icon .. " "
        local border = "│ "

        local field_chunk_list = {}
        for _, field in ipairs(fields) do
          local pn = field.name .. string.rep(" ", max_name_len - #field.name)
          table.insert(field_chunk_list, format.build_field_chunks(field, border, pn, obj_hl))
        end

        lines_used = render_expand_list({ { prefix, obj_hl } }, field_chunk_list)
      elseif expand_data.params then
        local params = expand_data.params
        local base_hl = expand_data.base_hl
        local prefix = " ← " .. expand_data.icon .. " " .. (expand_data.base_name or "") .. " "
        local border = "│ "

        local param_chunk_list = {}
        local hide_icon = expand_data.hide_param_icon
        for _, param in ipairs(params) do
          table.insert(param_chunk_list, format.build_generic_param_chunks(param, border, base_hl, hide_icon))
        end

        lines_used = render_expand_list({ { prefix, base_hl } }, param_chunk_list)
      elseif expand_data.label then
        local win_col = calc_win_col()
        local prefix = " ← " .. expand_data.icon .. " "
        local prefix_w = vim.fn.strdisplaywidth(prefix)
        local avail = win_width - win_col - prefix_w
        local label_chunks = { { iconify.iconify_label(expand_data.label) .. " ", expand_data.base_hl } }
        local wrapped = wrap_chunks(label_chunks, avail)

        local header_lnum = pos.lnum + expand_line_offset
        if header_lnum < line_count then
          local first = { { prefix, expand_data.base_hl } }
          for _, c in ipairs(wrapped[1]) do
            table.insert(first, c)
          end
          vim.api.nvim_buf_set_extmark(bufnr, ns, header_lnum, 0, {
            virt_text = first,
            virt_text_win_col = win_col,
            priority = 2047,
            hl_mode = "replace",
          })
        end

        local item_col = win_col + prefix_w
        for idx = 2, #wrapped do
          local target_lnum = pos.lnum + expand_line_offset + (idx - 1)
          if target_lnum < line_count then
            vim.api.nvim_buf_set_extmark(bufnr, ns, target_lnum, 0, {
              virt_text = wrapped[idx],
              virt_text_pos = "overlay",
              virt_text_win_col = item_col,
              priority = 2047,
              hl_mode = "replace",
            })
          end
        end
        lines_used = #wrapped
      end

      expand_line_offset = expand_line_offset + lines_used
    end
  end
end

return M

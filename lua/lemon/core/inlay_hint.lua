local M = {}

local glyph = require "lemon.glyph"

local ns = vim.api.nvim_create_namespace "lemon_inlay_hint"
local augroup = vim.api.nvim_create_augroup("lemon_inlay_hint", { clear = true })

---@type table<number, { enabled: boolean, client_hints: table<number, table<number, table[]>> }>
local bufstates = {}

local function get_cfg()
  return require("lemon.config").get().inlay_hint
end

local type_patterns = {
  number = {
    "^[iu]%d+$", "^[iu]size$", "^f%d+$",
    "^int%d*$", "^uint%d*$", "^float%d*$", "^double$",
    "^number$", "^Number$", "^byte$",
  },
  string = {
    "^string$", "^String$", "^str$", "^&str$", "^char$",
  },
  boolean = {
    "^bool$", "^boolean$", "^Boolean$",
  },
  null = {
    "^null$", "^nil$", "^None$",
  },
  undefined = {
    "^undefined$", "^void$", "^%(%)$",
  },
  unknown = {
    "^unknown$", "^any$",
  },
  never = {
    "^never$",
  },
  promise = {
    "^Promise<",
  },
  array = {
    "^Vec<", "^%[%]", "^Array<", "^List<", "^Slice<",
    "%[%]$",
  },
  object = {
    "^{",
  },
  ["function"] = {
    "^fn%(", "^Fn%(", "^FnOnce%(", "^FnMut%(", "^func%(", "^Fun<",
    "^%(.*%) =>",
  },
}

local function detect_type(label)
  local icons = glyph.inlay.types
  if not icons then
    return nil, nil
  end
  local stripped = label:gsub("^:%s*", "")

  if icons.array and stripped:find("%[%]$") then
    local element = stripped:gsub("%[%]$", "")
    if element ~= "" then
      local elem_icon = detect_type(element)
      if elem_icon then
        return elem_icon .. icons.array, "array"
      end
    end
  end

  for kind, patterns in pairs(type_patterns) do
    if icons[kind] then
      for _, pat in ipairs(patterns) do
        if stripped:find(pat) then
          return icons[kind], kind
        end
      end
    end
  end
  return nil, nil
end

local function iconify_type(text)
  local icon = detect_type(text)
  if icon then
    return icon
  end
  return text
end

local function compact_inner_objects(text)
  local obj_icon = glyph.inlay.types and glyph.inlay.types.object or ""
  local result = {}
  local i = 1
  local len = #text
  while i <= len do
    local ch = text:sub(i, i)
    if ch == "{" then
      local depth = 1
      local j = i + 1
      local count = 0
      local has_colon = false
      while j <= len and depth > 0 do
        local c = text:sub(j, j)
        if c == "{" then
          depth = depth + 1
        elseif c == "}" then
          depth = depth - 1
        elseif depth == 1 and c == ":" then
          has_colon = true
        elseif depth == 1 and (c == ";" or c == ",") and has_colon then
          count = count + 1
          has_colon = false
        end
        j = j + 1
      end
      if has_colon then
        count = count + 1
      end
      if count > 0 and i > 1 then
        table.insert(result, obj_icon)
      else
        table.insert(result, text:sub(i, j - 1))
      end
      i = j
    else
      table.insert(result, ch)
      i = i + 1
    end
  end
  return table.concat(result)
end

local function iconify_words(text)
  local lt = text:find("<")
  if not lt then
    return text
  end

  local base = text:sub(1, lt - 1)
  local generic = text:sub(lt)
  local fallback = (glyph.inlay.types and glyph.inlay.types.generic) or glyph.inlay.type or ""

  generic = generic:gsub("%f[%w](%w+)%f[%W]", function(word)
    return detect_type(word) or fallback
  end)

  return base .. generic
end

local function iconify_label(text)
  text = text:gsub("(:%s*)%(.-%)%s*=>%s*([%w<>%(%)]+)", function(prefix, ret)
    local fn_icon = glyph.inlay.types and glyph.inlay.types["function"] or ""
    local arrow = glyph.inlay.arrow or "→"
    return prefix .. fn_icon .. " " .. arrow .. " " .. iconify_type(ret)
  end)
  text = text:gsub("(:%s*)([%w]+)([;%s}])", function(prefix, type_name, suffix)
    return prefix .. iconify_type(type_name) .. suffix
  end)
  return text
end

local function split_union(text)
  local parts = {}
  local depth = 0
  local current = ""
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "{" or ch == "<" or ch == "(" then
      depth = depth + 1
      current = current .. ch
    elseif ch == "}" or ch == ">" or ch == ")" then
      depth = depth - 1
      current = current .. ch
    elseif ch == "|" and depth == 0 then
      local trimmed = vim.trim(current)
      if trimmed ~= "" then
        table.insert(parts, trimmed)
      end
      current = ""
    else
      current = current .. ch
    end
  end
  local trimmed = vim.trim(current)
  if trimmed ~= "" then
    table.insert(parts, trimmed)
  end
  return parts
end

local function iconify_union(text, show_text)
  if not text:find("|") then
    return text
  end
  local fallback = (glyph.inlay.types and glyph.inlay.types.generic) or glyph.inlay.type or ""
  local parts = split_union(text)
  if #parts <= 1 then
    return text
  end
  local result = {}
  for _, trimmed in ipairs(parts) do
    local icon = detect_type(trimmed)
    if icon then
      table.insert(result, show_text and (icon .. " " .. trimmed) or icon)
    else
      table.insert(result, show_text and (fallback .. " " .. trimmed) or fallback)
    end
  end
  return table.concat(result, " | ")
end

local function parse_object_fields(label)
  local inner = label:match("^{%s*(.-)%s*}$")
  if not inner or inner == "" then
    return nil
  end

  local fields = {}
  local depth = 0
  local current = ""

  for i = 1, #inner do
    local ch = inner:sub(i, i)
    if ch == "(" or ch == "{" or ch == "<" then
      depth = depth + 1
      current = current .. ch
    elseif ch == ")" or ch == "}" then
      depth = depth - 1
      current = current .. ch
    elseif ch == ">" and current:sub(-1) ~= "=" then
      depth = depth - 1
      current = current .. ch
    elseif (ch == ";" or ch == ",") and depth == 0 then
      local trimmed = vim.trim(current)
      if trimmed ~= "" then
        local name, type_str = trimmed:match("^([%w_]+)%??:%s*(.+)$")
        if name and type_str then
          table.insert(fields, { name = name, type = vim.trim(type_str) })
        end
      end
      current = ""
    else
      current = current .. ch
    end
  end

  local trimmed = vim.trim(current)
  if trimmed ~= "" then
    local name, type_str = trimmed:match("^([%w_]+)%??:%s*(.+)$")
    if name and type_str then
      table.insert(fields, { name = name, type = vim.trim(type_str) })
    end
  end

  return #fields > 0 and fields or nil
end

local function parse_generic_params(label)
  local base_name = label:match("^(.-)%s*<")
  if not base_name then
    return nil, nil
  end

  local start = label:find("<")
  if not start then
    return nil, nil
  end

  local params = {}
  local depth = 0
  local current = ""

  for i = start + 1, #label do
    local ch = label:sub(i, i)
    if ch == "<" or ch == "(" or ch == "{" then
      depth = depth + 1
      current = current .. ch
    elseif ch == ">" then
      if depth == 0 then
        break
      end
      depth = depth - 1
      current = current .. ch
    elseif ch == ")" or ch == "}" then
      depth = depth - 1
      current = current .. ch
    elseif ch == "," and depth == 0 then
      local trimmed = vim.trim(current)
      if trimmed ~= "" then
        table.insert(params, trimmed)
      end
      current = ""
    else
      current = current .. ch
    end
  end

  local trimmed = vim.trim(current)
  if trimmed ~= "" then
    table.insert(params, trimmed)
  end

  return base_name, (#params > 0 and params or nil)
end

local function build_field_chunks(field, border, padded_name, obj_hl)
  local icons = glyph.inlay.types
  local type_icon, type_kind = detect_type(field.type)
  local field_hl = type_kind and ("LemonInlayTypeObjField_" .. type_kind) or obj_hl

  local chunks = {}
  if type_kind == "function" then
    local ret = field.type:match("%)%s*=>%s*(.+)$")
    if ret then
      local ret_icon, ret_kind = detect_type(ret)
      local ret_hl = ret_kind and ("LemonInlayTypeObjField_" .. ret_kind) or field_hl
      local fn_icon = icons and icons["function"] or ""
      table.insert(chunks, { border, obj_hl })
      table.insert(chunks, { padded_name .. "  ", field_hl })
      local arrow = glyph.inlay.arrow or "→"
      table.insert(chunks, { fn_icon .. " ", field_hl })
      table.insert(chunks, { arrow .. " ", "LemonInlayTypeObjOperator" })
      table.insert(chunks, { ret_icon or ret, ret_hl })
    else
      table.insert(chunks, { border, obj_hl })
      table.insert(chunks, { padded_name .. "  ", field_hl })
      table.insert(chunks, { type_icon or field.type, field_hl })
    end
  elseif type_icon then
    table.insert(chunks, { border, obj_hl })
    table.insert(chunks, { padded_name .. "  ", field_hl })
    table.insert(chunks, { type_icon, field_hl })
  else
    table.insert(chunks, { border, obj_hl })
    table.insert(chunks, { padded_name .. "  ", field_hl })
    table.insert(chunks, { iconify_union(field.type, true), field_hl })
  end
  return chunks
end

local function build_generic_param_chunks(param_text, border, base_hl)
  local icons = glyph.inlay.types
  local type_icon, type_kind = detect_type(param_text)
  local param_hl = type_kind and ("LemonInlayTypeObjField_" .. type_kind) or base_hl

  local display_icon = type_icon
    or (icons and icons.generic)
    or glyph.inlay.type
    or ""

  return {
    { border, base_hl },
    { display_icon .. " " .. iconify_label(iconify_union(param_text, true)), param_hl },
  }
end

local function build_function_chunks(label, icon, hl, cfg)
  local ret = label:match("%)%s*=>%s*(.+)$")
  if not ret then
    return nil
  end
  local ret_icon, ret_kind = detect_type(ret)
  local ret_hl = ret_kind and ("LemonInlayTypeFnRet_" .. ret_kind) or hl

  local fn_part
  if cfg.fn_icon then
    fn_part = " " .. icon .. " "
  else
    local params = label:match("^(%(.-%))")
    fn_part = " " .. (params or "") .. " "
  end

  local ret_part
  if ret_icon then
    if cfg.fn_return_text then
      ret_part = ret_icon .. " " .. ret .. " "
    else
      ret_part = ret_icon .. " "
    end
  else
    ret_part = iconify_union(ret, cfg.fn_return_text) .. " "
  end

  local result = {
    chunks = {
      { " ", "" },
      { fn_part, hl },
      { (glyph.inlay.arrow or "→") .. " ", "LemonInlayTypeOperator" },
      { ret_part, ret_hl },
    },
  }

  if ret:find("|") then
    local parts = split_union(ret)
    if #parts > 1 then
      result.expand = {
        icon = icon,
        base_name = (glyph.inlay.arrow or "→"),
        params = parts,
        base_hl = hl,
      }
    end
  elseif ret:find("<") then
    local base_name, params = parse_generic_params(ret)
    if params then
      result.expand = {
        icon = icon,
        base_name = (glyph.inlay.arrow or "→") .. " " .. base_name,
        params = params,
        base_hl = hl,
      }
    end
  elseif not ret_icon and not cfg.fn_return_text then
    result.expand = {
      icon = icon,
      label = ret,
      base_hl = hl,
    }
  end

  return result
end

local function format_hint(hint, cfg)
  local label
  if type(hint.label) == "string" then
    label = hint.label
  elseif type(hint.label) == "table" then
    local parts = {}
    for _, part in ipairs(hint.label) do
      table.insert(parts, part.value)
    end
    label = table.concat(parts)
  else
    return nil
  end

  label = vim.trim(label)
  label = label:gsub("^:%s*", "")
  label = label:gsub(":$", "")
  if label == "" then
    return nil
  end

  local kind = hint.kind
  local is_type = kind == 1
  local is_param = kind == 2

  if is_type and not cfg.show_type_hints then
    return nil
  end
  if is_param and not cfg.show_parameter_hints then
    return nil
  end

  local fmt
  if is_type then
    fmt = cfg.type_format
  elseif is_param then
    fmt = cfg.param_format
  else
    fmt = cfg.type_format
  end

  local text = fmt:gsub("${hint}", label)
  if not is_param then
    text = compact_inner_objects(text)
    if text:find("<") then
      text = iconify_words(text)
      if not cfg.generic_text then
        text = text:match("(<.+)") or text
      end
    end
    if text:find("|") then
      text = iconify_union(text, cfg.type_text)
    end
  end

  local icon, hl
  local type_icon, type_kind
  if is_param then
    if cfg.param_icon then
      local params = glyph.inlay.params
      icon = (params and params[label]) or detect_type(label) or glyph.inlay.param
    else
      icon = ""
    end
    hl = "LemonInlayParam"
  else
    type_icon, type_kind = detect_type(label)
    if cfg.type_icon then
      icon = type_icon or glyph.inlay.type
    else
      icon = ""
    end
    hl = type_kind and ("LemonInlayType_" .. type_kind) or "LemonInlayType"
    if type_kind == "function" then
      return build_function_chunks(label, icon, hl, cfg)
    end
    if type_kind == "object" then
      local threshold = cfg.object_threshold or 0
      if threshold > 0 then
        local fields = parse_object_fields(label)
        if fields and #fields >= threshold then
          return {
            chunks = { { " ", "" }, { " " .. icon .. " ", hl } },
            expand = {
              icon = icon,
              fields = fields,
              obj_hl = hl,
            },
          }
        end
      end
      if cfg.type_text then
        text = iconify_label(text)
      else
        text = ""
      end
    end
    if type_icon and not cfg.type_text then
      text = ""
    end
  end

  local badge
  if icon ~= "" and text ~= "" then
    badge = " " .. icon .. " " .. text .. " "
  elseif icon ~= "" then
    badge = " " .. icon .. " "
  else
    badge = " " .. text .. " "
  end

  local result = {
    chunks = {
      { " ", "" },
      { badge, hl },
    },
  }

  if not is_param then
    if label:find("<") then
      local base_name, params = parse_generic_params(label)
      if params then
        result.expand = {
          icon = icon,
          base_name = base_name,
          params = params,
          base_hl = hl,
        }
      end
    elseif label:find("|") then
      local parts = split_union(label)
      if #parts > 1 then
        result.expand = {
          icon = icon,
          base_name = "",
          params = parts,
          base_hl = hl,
        }
      end
    else
      result.expand = {
        icon = icon,
        label = label,
        base_hl = hl,
      }
    end
  end

  return result
end

local function render(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local state = bufstates[bufnr]
  if not state or not state.enabled then
    return
  end

  local cfg = get_cfg()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local hints_by_pos = {}
  for _, client_hints in pairs(state.client_hints) do
    for lnum, hints in pairs(client_hints) do
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

  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  local current_line
  if cfg.only_current_line then
    current_line = cursor_lnum
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

  local render_entries = {}
  local line_inline_widths = {}

  for key, pos in pairs(hints_by_pos) do
    if not current_line or pos.lnum == current_line then
      local chunks = {}
      local use_eol = false
      local on_cursor = pos.lnum == cursor_lnum
      local expand_data = nil

      for _, hint in ipairs(pos.hints) do
        local result = format_hint(hint, cfg)
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
      local line = vim.api.nvim_buf_get_lines(bufnr, pos.lnum, pos.lnum + 1, false)[1]
      local col = line and math.min(pos.col, #line) or 0
      vim.api.nvim_buf_set_extmark(bufnr, ns, pos.lnum, col, {
        virt_text = chunks,
        virt_text_pos = entry.use_eol and "eol" or cfg.position,
        hl_mode = "combine",
        priority = 2047,
      })
    end
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
        return math.max(
          line_w + iw - leftcol + 2,
          math.floor(win_width * (cfg.expand_offset or 0.6))
        )
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
          table.insert(field_chunk_list, build_field_chunks(field, border, pn, obj_hl))
        end

        lines_used = render_expand_list({ { prefix, obj_hl } }, field_chunk_list)

      elseif expand_data.params then
        local params = expand_data.params
        local base_hl = expand_data.base_hl
        local prefix = " ← " .. expand_data.icon .. " " .. (expand_data.base_name or "") .. " "
        local border = "│ "

        local param_chunk_list = {}
        for _, param in ipairs(params) do
          table.insert(param_chunk_list, build_generic_param_chunks(param, border, base_hl))
        end

        lines_used = render_expand_list({ { prefix, base_hl } }, param_chunk_list)

      elseif expand_data.label then
        local win_col = calc_win_col()
        local prefix = " ← " .. expand_data.icon .. " "
        local prefix_w = vim.fn.strdisplaywidth(prefix)
        local avail = win_width - win_col - prefix_w
        local label_chunks = { { iconify_label(expand_data.label) .. " ", expand_data.base_hl } }
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

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      bufstates[bufnr] = nil
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

  if cfg.only_current_line or (cfg.object_threshold and cfg.object_threshold > 0) then
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        render(bufnr)
      end,
    })
  end

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

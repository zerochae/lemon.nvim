local M = {}

local glyph = require "lemon.glyph"
local iconify = require "lemon.core.inlay_hint.iconify"

local detect_type = iconify.detect_type
local compact_inner_objects = iconify.compact_inner_objects
local iconify_words = iconify.iconify_words
local iconify_label = iconify.iconify_label
local split_union = iconify.split_union
local iconify_union = iconify.iconify_union

function M.parse_object_fields(label)
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

function M.parse_generic_params(label)
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

function M.build_field_chunks(field, border, padded_name, obj_hl)
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

function M.build_generic_param_chunks(param_text, border, base_hl, hide_icon)
  local icons = glyph.inlay.types
  local type_icon, type_kind = detect_type(param_text)
  local param_hl = type_kind and ("LemonInlayTypeObjField_" .. type_kind) or base_hl

  local display
  if hide_icon then
    display = iconify_label(iconify_union(param_text, true))
  else
    local display_icon = type_icon
      or (icons and icons.generic)
      or glyph.inlay.type
      or ""
    display = display_icon .. " " .. iconify_label(iconify_union(param_text, true))
  end

  return {
    { border, base_hl },
    { display, param_hl },
  }
end

function M.build_function_chunks(label, icon, hl, cfg)
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
    local base_name, params = M.parse_generic_params(ret)
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

function M.format_hint(hint, cfg)
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
      return M.build_function_chunks(label, icon, hl, cfg)
    end
    if type_kind == "object" then
      local threshold = cfg.object_threshold or 0
      if threshold > 0 then
        local fields = M.parse_object_fields(label)
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
      local base_name, params = M.parse_generic_params(label)
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
          hide_param_icon = true,
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

return M

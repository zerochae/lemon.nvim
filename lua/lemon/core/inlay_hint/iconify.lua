local M = {}

local glyph = require "lemon.glyph"

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

function M.detect_type(label)
  local icons = glyph.inlay.types
  if not icons then
    return nil, nil
  end
  local stripped = label:gsub("^:%s*", "")

  if icons.array and stripped:find("%[%]$") then
    local element = stripped:gsub("%[%]$", "")
    if element ~= "" then
      local elem_icon = M.detect_type(element)
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

function M.iconify_type(text)
  local icon = M.detect_type(text)
  if icon then
    return icon
  end
  return text
end

function M.compact_inner_objects(text)
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

function M.iconify_words(text)
  local lt = text:find("<")
  if not lt then
    return text
  end

  local base = text:sub(1, lt - 1)
  local generic = text:sub(lt)
  local fallback = (glyph.inlay.types and glyph.inlay.types.generic) or glyph.inlay.type or ""

  generic = generic:gsub("%f[%w](%w+)%f[%W]", function(word)
    return M.detect_type(word) or fallback
  end)

  return base .. generic
end

function M.iconify_label(text)
  text = text:gsub("(:%s*)%(.-%)%s*=>%s*([%w<>%(%)]+)", function(prefix, ret)
    local fn_icon = glyph.inlay.types and glyph.inlay.types["function"] or ""
    local arrow = glyph.inlay.arrow or "→"
    return prefix .. fn_icon .. " " .. arrow .. " " .. M.iconify_type(ret)
  end)
  text = text:gsub("(:%s*)([%w]+)([;%s}])", function(prefix, type_name, suffix)
    return prefix .. M.iconify_type(type_name) .. suffix
  end)
  return text
end

function M.split_union(text)
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

function M.iconify_union(text, show_text)
  if not text:find("|") then
    return text
  end
  local fallback = (glyph.inlay.types and glyph.inlay.types.generic) or glyph.inlay.type or ""
  local parts = M.split_union(text)
  if #parts <= 1 then
    return text
  end
  local result = {}
  for _, trimmed in ipairs(parts) do
    local icon = M.detect_type(trimmed)
    if icon then
      table.insert(result, show_text and (icon .. " " .. trimmed) or icon)
    else
      table.insert(result, show_text and (fallback .. " " .. trimmed) or fallback)
    end
  end
  return table.concat(result, " | ")
end

return M

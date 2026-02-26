local M = {}

local glyph = require "lemon.glyph"

local kind_names = {
  "File",
  "Module",
  "Namespace",
  "Package",
  "Class",
  "Property",
  "Variable",
  "Constant",
  "Enum",
  "Function",
  "Constructor",
  "Method",
  "Type",
  "TypeParameter",
  "Interface",
  "Operator",
  "Number",
  "String",
  "Boolean",
  "Array",
  "Object",
  "Null",
  "EnumMember",
  "Event",
  "Struct",
  "TypeParameter",
}

function M.kind_icon(kind)
  local icons = glyph.get().symbol_kind
  return icons[kind] or glyph.get().ui.symbol_fallback
end

function M.kind_name(kind)
  return kind_names[kind] or "Unknown"
end

function M.cursor_in_range(cursor_line, cursor_col, range)
  if cursor_line < range.start.line or cursor_line > range["end"].line then
    return false
  end
  if cursor_line == range.start.line and cursor_col < range.start.character then
    return false
  end
  if cursor_line == range["end"].line and cursor_col > range["end"].character then
    return false
  end
  return true
end

function M.find_path(symbols, cursor_line, cursor_col)
  local path = {}

  local function walk(nodes)
    for _, sym in ipairs(nodes) do
      local range = sym.range or sym.location and sym.location.range
      if not range then
        goto continue
      end

      if M.cursor_in_range(cursor_line, cursor_col, range) then
        table.insert(path, sym)
        if sym.children and #sym.children > 0 then
          walk(sym.children)
        end
        return
      end
      ::continue::
    end
  end

  walk(symbols)
  return path
end

local scope_kinds = {
  [2] = true, -- Module
  [3] = true, -- Namespace
  [4] = true, -- Package
  [5] = true, -- Class
  [9] = true, -- Enum
  [10] = true, -- Function
  [11] = true, -- Constructor
  [12] = true, -- Method
  [15] = true, -- Interface
  [25] = true, -- Struct
}

function M.find_ending_symbols(symbols, visible_start, visible_end, visible_mode, cursor_line)
  local results = {}

  local function walk(nodes)
    for _, sym in ipairs(nodes) do
      local range = sym.range or sym.location and sym.location.range
      if not range or not scope_kinds[sym.kind] then
        goto continue
      end

      local end_line = range["end"].line
      if end_line >= visible_start and end_line <= visible_end then
        local off_screen = range.start.line < visible_start
        local on_cursor = cursor_line == end_line

        local show = false
        if visible_mode == "hover" then
          show = on_cursor
        elseif visible_mode == "off_screen" then
          show = off_screen
        elseif visible_mode == "always" then
          show = on_cursor or off_screen
        end
        if show then
          table.insert(results, { symbol = sym, end_line = end_line })
        end
      end

      if sym.children and #sym.children > 0 then
        walk(sym.children)
      end
      ::continue::
    end
  end

  walk(symbols)
  return results
end

function M.format_path(path, sep, limit, indicator)
  if #path == 0 then
    return {}
  end

  local items = path
  if limit and limit > 0 and #path > limit then
    items = {}
    table.insert(items, { name = indicator or "...", kind = path[1].kind, _indicator = true })
    for i = #path - limit + 1, #path do
      table.insert(items, path[i])
    end
  end

  local chunks = {}
  for i, sym in ipairs(items) do
    if i > 1 then
      table.insert(chunks, { sep, "LemonScopeSeparator" })
    end
    local icon = sym._indicator and "" or M.kind_icon(sym.kind)
    local text = icon ~= "" and (icon .. " " .. sym.name) or sym.name
    local hl = sym._indicator and "LemonScopeSeparator" or ("LemonScopeKind_" .. sym.kind)
    table.insert(chunks, { text, hl })
  end

  return chunks
end

return M

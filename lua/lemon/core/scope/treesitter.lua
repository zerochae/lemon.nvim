local M = {}

local glyph = require "lemon.glyph"

local scope_node_types = {
  if_statement = true,
  for_statement = true,
  for_in_statement = true,
  while_statement = true,
  do_statement = true,
  switch_statement = true,
  try_statement = true,
  with_statement = true,
  repeat_statement = true,
  if_expression = true,
  for_expression = true,
  while_expression = true,
  match_expression = true,
  loop_expression = true,
  select_statement = true,
  arrow_function = true,
  function_expression = true,
  jsx_element = true,
  tsx_element = true,
}

local keyword_map = {
  arrow_function = "fn",
  function_expression = "fn",
  jsx_element = "jsx",
  tsx_element = "tsx",
}

local function extract_keyword(node_type)
  return keyword_map[node_type] or node_type:gsub("_statement$", ""):gsub("_expression$", "")
end

local function first_line_text(node, bufnr, max_len)
  max_len = max_len or 40
  local start_row = node:start()
  local line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
  if not line then
    return ""
  end
  line = vim.trim(line)
  line = line:gsub("%s+do%s*$", "")
  line = line:gsub("%s+then%s*$", "")
  line = line:gsub("%s*%{%s*$", "")
  line = line:gsub("%s*:%s*$", "")
  if #line > max_len then
    line = line:sub(1, max_len - 1) .. "…"
  end
  return line
end

function M.keyword_icon(keyword)
  local icons = glyph.get().scope_keyword
  if icons then
    return icons[keyword]
  end
  return nil
end

function M.find_scope_nodes(bufnr, visible_start, visible_end, visible_mode, cursor_line)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return {}
  end

  local results = {}

  parser:for_each_tree(function(tree)
    local root = tree:root()

    local function walk(node)
      local start_row, _, end_row, _ = node:range()

      if start_row > visible_end then
        return
      end

      local node_type = node:type()

      if scope_node_types[node_type] then
        if start_row ~= end_row and end_row >= visible_start and end_row <= visible_end then
          local off_screen = start_row < visible_start
          local on_cursor = cursor_line == end_row

          local show = false
          if visible_mode == "hover" then
            show = on_cursor
          elseif visible_mode == "off_screen" then
            show = off_screen
          elseif visible_mode == "always" then
            show = on_cursor or off_screen
          end

          if show then
            local keyword = extract_keyword(node_type)
            table.insert(results, {
              end_line = end_row,
              keyword = keyword,
              text = first_line_text(node, bufnr),
              ts = true,
            })
          end
        end
      end

      for child in node:iter_children() do
        walk(child)
      end
    end

    walk(root)
  end)

  return results
end

return M

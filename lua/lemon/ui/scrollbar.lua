local glyph = require "lemon.glyph"
local M = {}

---@param win number
---@param total_lines number
function M.update(win, total_lines)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local top = vim.api.nvim_win_call(win, function()
    return vim.fn.line "w0"
  end)
  local bot = vim.api.nvim_win_call(win, function()
    return vim.fn.line "w$"
  end)

  local has_above = top > 1
  local has_below = bot < total_lines
  local indicator = ""

  if has_above and has_below then
    indicator = glyph.ui.scroll
  elseif has_above then
    indicator = glyph.ui.scroll_up
  elseif has_below then
    indicator = glyph.ui.scroll_down
  end

  if indicator ~= "" then
    vim.api.nvim_win_set_config(win, {
      footer = { { " " .. indicator .. " ", "LemonTitle" } },
      footer_pos = "right",
    })
  else
    vim.api.nvim_win_set_config(win, { footer = "" })
  end
end

return M

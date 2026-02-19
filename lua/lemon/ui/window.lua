local M = {}

---@param lines string[]
---@param cfg Lemon.Config
---@return { width: number, height: number }
function M.compute(lines, cfg)
  local columns = vim.api.nvim_get_option_value("columns", {})
  local editor_lines = vim.api.nvim_get_option_value("lines", {})
  local max_width = math.floor(columns * cfg.hover.max_width)

  local max_content_len = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_content_len then
      max_content_len = w
    end
  end

  local sign_width = 2
  local width = math.min(max_content_len + sign_width, max_width) + cfg.hover.pad_right
  width = math.max(width, 10)

  local wrap_increase = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > width then
      wrap_increase = wrap_increase + math.ceil(w / width) - 1
    end
  end

  local max_height = math.floor(editor_lines * cfg.hover.max_height)
  local height = math.min(#lines + wrap_increase, max_height)
  height = math.max(height, 1)

  return { width = width, height = height }
end

return M

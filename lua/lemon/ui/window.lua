local M = {}

function M.compute(lines, opts)
  opts = opts or {}
  local max_width_ratio = opts.max_width
  local max_height_ratio = opts.max_height or 0.4
  local pad_right = opts.pad_right or 0
  local min_width = opts.min_width or 10
  local min_height = opts.min_height or 1
  local extra_height = opts.extra_height or 0

  local columns = vim.api.nvim_get_option_value("columns", {})
  local editor_lines = vim.api.nvim_get_option_value("lines", {})
  local sign_width = 2

  local max_content_len = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_content_len then
      max_content_len = w
    end
  end

  local width = max_content_len + sign_width + pad_right
  if max_width_ratio then
    local max_width = math.floor(columns * max_width_ratio)
    width = math.min(width, max_width)
  end
  width = math.max(width, min_width)

  local wrap_increase = 0
  for _, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > width then
      wrap_increase = wrap_increase + math.ceil(w / width) - 1
    end
  end

  local max_height = math.floor(editor_lines * max_height_ratio)
  local height = math.min(#lines + extra_height + wrap_increase, max_height)
  height = math.max(height, min_height)

  return { width = width, height = height }
end

return M

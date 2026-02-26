local M = {}

function M.hex_to_rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

function M.rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

function M.blend(fg_hex, bg_hex, alpha)
  local fg_r, fg_g, fg_b = M.hex_to_rgb(fg_hex)
  local bg_r, bg_g, bg_b = M.hex_to_rgb(bg_hex)
  local r = math.floor(fg_r * alpha + bg_r * (1 - alpha) + 0.5)
  local g = math.floor(fg_g * alpha + bg_g * (1 - alpha) + 0.5)
  local b = math.floor(fg_b * alpha + bg_b * (1 - alpha) + 0.5)
  return M.rgb_to_hex(r, g, b)
end

function M.get_hl_color(name, attr)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  local val = hl[attr]
  if not val then
    return nil
  end
  return string.format("#%06x", val)
end

return M

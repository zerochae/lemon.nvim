local M = {}

local function display_key(raw)
  return raw:gsub("^<(.+)>$", "%1")
end

function M.set(win, keys, opts)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not opts or not opts.enabled then
    return
  end
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, { " " .. key.icon, "LemonFooterIcon" })
    if opts.show_desc then
      table.insert(parts, { " " .. key.desc, "LemonFooterDesc" })
    end
    table.insert(parts, { "[" .. display_key(key.key) .. "]", "LemonFooterKey" })
  end
  table.insert(parts, { " ", "Comment" })
  vim.api.nvim_win_set_config(win, {
    footer = parts,
    footer_pos = "right",
  })
end

function M.clear(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_win_set_config(win, { footer = "" })
end

return M

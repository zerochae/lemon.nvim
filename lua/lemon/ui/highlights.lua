local M = {}

function M.setup()
  local highlights = {
    LemonNormal = { link = "NormalFloat" },
    LemonBorder = { link = "FloatBorder" },
    LemonTitle = { link = "Title" },
    LemonBeacon = { link = "Search" },
  }

  for name, opts in pairs(highlights) do
    local existing = vim.api.nvim_get_hl(0, { name = name })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  local cfg = require("lemon.config").get()
  if cfg.highlights then
    for name, opts in pairs(cfg.highlights) do
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
end

return M

local M = {}

function M.setup()
  local highlights = {
    LemonNormal = { link = "NormalFloat" },
    LemonBorder = { link = "FloatBorder" },
    LemonTitle = { link = "Title" },
    LemonBeacon = { link = "Search" },
    LemonActionNumber = { link = "Number" },
    LemonDiffAdd = { link = "DiffAdd" },
    LemonDiffAddSign = { link = "Added" },
    LemonDiffDelete = { link = "DiffDelete" },
    LemonDiffDeleteSign = { link = "Removed" },
    LemonDiffHunk = { link = "Comment" },
    LemonDiffFile = { link = "Normal" },
    LemonFooterIcon = { link = "Function" },
    LemonFooterDesc = { link = "Comment" },
    LemonFooterKey = { link = "Function" },
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

local M = {}

local config = require("lemon.config")

---@param opts? Lemon.Config
function M.setup(opts)
  config.setup(opts)
  require("lemon.ui.highlights").setup()
end

function M.hover()
  require("lemon.core.hover").hover()
end

function M.definition()
  require("lemon.core.definition").goto_definition()
end

return M

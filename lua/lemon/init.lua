local M = {}

local config = require "lemon.config"

---@param opts? Lemon.Config
function M.setup(opts)
  config.setup(opts)
  require("lemon.glyph").setup(config.get().glyph)
  require("lemon.ui.highlights").setup()
  require("lemon.core.signature_help").setup_auto()
  require("lemon.core.inlay_hint").setup()
  require("lemon.core.scope").setup()
end

function M.hover()
  require("lemon.core.hover").hover()
end

function M.definition()
  require("lemon.core.definition").goto_definition()
end

function M.diagnostic_next()
  require("lemon.core.diagnostic").goto_next()
end

function M.diagnostic_prev()
  require("lemon.core.diagnostic").goto_prev()
end

function M.diagnostic_float()
  require("lemon.core.diagnostic").open_float()
end

function M.code_action()
  require("lemon.core.code_action").code_action()
end

function M.signature_help()
  require("lemon.core.signature_help").signature_help()
end

M.inlay_hint = {
  enable = function(bufnr)
    require("lemon.core.inlay_hint").enable(bufnr)
  end,
  disable = function(bufnr)
    require("lemon.core.inlay_hint").disable(bufnr)
  end,
  toggle = function(bufnr)
    require("lemon.core.inlay_hint").toggle(bufnr)
  end,
}

M.scope = {
  get_data = function(bufnr)
    return require("lemon.core.scope").get_data(bufnr)
  end,
  get_location = function(bufnr)
    return require("lemon.core.scope").get_location(bufnr)
  end,
  is_available = function(bufnr)
    return require("lemon.core.scope").is_available(bufnr)
  end,
  toggle = function()
    require("lemon.core.scope").toggle()
  end,
}

return M

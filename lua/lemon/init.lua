local Lemon = {}

local config = require "lemon.config"

---@param opts? Lemon.Config
function Lemon.setup(opts)
  config.setup(opts)
  require("lemon.glyph").setup(config.get().glyph)
  require("lemon.ui.highlights").setup()
  require("lemon.core.signature_help").setup_auto()
  require("lemon.core.inlay_hint").setup()
  require("lemon.core.scope").setup()
  _G.Lemon = Lemon
end

return setmetatable(Lemon, {
  __index = function(t, k)
    local ok, mod = pcall(require, "lemon.core." .. k)
    if ok then
      rawset(t, k, mod)
      return mod
    end
  end,
})

local g = require("lemon.glyph").tag

---@type table<string, Lemon.TagDef>
return {
  [":param"] = { icon = g.param, hl = "LemonTitle" },
  [":type"] = { icon = g.type, hl = "@type" },
  [":returns?:"] = { icon = g.returns, hl = "@keyword.return" },
  [":rtype:"] = { icon = g.type, hl = "@type" },
  [":raises?:"] = { icon = g.throws, hl = "DiagnosticWarn" },
  ["Args:"] = { icon = g.param, hl = "LemonTitle" },
  ["Returns:"] = { icon = g.returns, hl = "@keyword.return" },
  ["Raises:"] = { icon = g.throws, hl = "DiagnosticWarn" },
  ["Yields:"] = { icon = g.returns, hl = "@keyword.return" },
  ["Note:"] = { icon = g.note, hl = "DiagnosticInfo" },
  ["Examples?:"] = { icon = g.example, hl = "@function" },
  ["Attributes:"] = { icon = g.field, hl = "@variable.member" },
}

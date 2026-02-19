---@type table<string, Lemon.TagDef>
return {
  ["\\param"] = { icon = "󰏪", hl = "LemonTitle" },
  ["\\returns?"] = { icon = "󰌑", hl = "@keyword.return" },
  ["\\brief"] = { icon = "󰧭", hl = "LemonTitle" },
  ["\\throws"] = { icon = "󰚑", hl = "DiagnosticWarn" },
  ["\\see"] = { icon = "󰈈", hl = "@markup.link" },
  ["\\since"] = { icon = "󰔠", hl = "@number" },
  ["\\deprecated"] = { icon = "󰃤", hl = "DiagnosticError" },
  ["\\note"] = { icon = "󰍩", hl = "DiagnosticInfo" },
  ["\\warning"] = { icon = "󰚑", hl = "DiagnosticWarn" },
}

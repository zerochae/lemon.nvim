---@type table<string, Lemon.TagDef>
return {
  [":param"] = { icon = "󰏪", hl = "LemonTitle" },
  [":type"] = { icon = "󰠱", hl = "@type" },
  [":returns?:"] = { icon = "󰌑", hl = "@keyword.return" },
  [":rtype:"] = { icon = "󰠱", hl = "@type" },
  [":raises?:"] = { icon = "󰚑", hl = "DiagnosticWarn" },
  ["Args:"] = { icon = "󰏪", hl = "LemonTitle" },
  ["Returns:"] = { icon = "󰌑", hl = "@keyword.return" },
  ["Raises:"] = { icon = "󰚑", hl = "DiagnosticWarn" },
  ["Yields:"] = { icon = "󰌑", hl = "@keyword.return" },
  ["Note:"] = { icon = "󰍩", hl = "DiagnosticInfo" },
  ["Examples?:"] = { icon = "", hl = "@function" },
  ["Attributes:"] = { icon = "󰜢", hl = "@variable.member" },
}

local M = {}

local defaults = {
  numeric = {
    [1] = "󰎤",
    [2] = "󰎧",
    [3] = "󰎪",
    [4] = "󰎭",
    [5] = "󰎱",
    [6] = "󰎳",
    [7] = "󰎶",
    [8] = "󰎹",
    [9] = "󰎼",
    [10] = "󰎡",
  },

  severity = {
    [1] = { icon = "", hl = "DiagnosticError" },
    [2] = { icon = "", hl = "DiagnosticWarn" },
    [3] = { icon = "", hl = "DiagnosticInfo" },
    [4] = { icon = "", hl = "DiagnosticHint" },
  },

  diff = {
    hunk_del = "",
    hunk_add = "",
    hunk_sign = "",
    add = "󰐖",
    delete = "󰍵",
  },

  tag = {
    param = "󰏪",
    returns = "󰌑",
    brief = "󰧭",
    throws = "󰚑",
    see = "󰈈",
    since = "󰔠",
    deprecated = "󰃤",
    note = "󰍩",
    example = "",
    version = "󰜣",
    link = "󰌹",
    default = "󰁕",
    type = "󰠱",
    type_param = "󰗴",
    field = "󰜢",
    enum = "󰕘",
    interface = "󰜰",
    module = "󰅩",
    func = "󰊕",
    sealed = "󰌾",
    event = "󰀦",
    package = "󰏗",
    label = "󰓹",
    variable = "󰀫",
    experimental = "󰂡",
    public = "󰡁",
    internal = "󰒃",
  },

  footer = {
    enter = "󰌑",
    move = "↕",
    close = "󰅗",
    execute = "󰌑",
    select = "",
  },

  inlay = {
    type = "󰠱",
    param = "󰏪",
    types = {
      number = "󰎠",
      string = "󰉿",
      boolean = "󰨙",
      null = "󰟢",
      undefined = "󰌶",
      unknown = "󰋗",
      never = "󰅙",
      array = "󰅪",
      object = "󰅩",
      ["function"] = "󰊕",
      promise = "󰔟",
      generic = "󰗴",
    },
    arrow = "→",
    params = {},
  },

  ui = {
    server = "󰚗",
    file = "󰈙",
    content = "󰧭",
    code = "󰓹",
    loading = "󰔟",
    info = "󰍻",
    error = "",
    symbol_fallback = "󰈚",
    scroll = "↕",
    scroll_up = "▲",
    scroll_down = "▼",
  },
}

local icons = nil

function M.setup(opts)
  icons = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

local function get()
  if not icons then
    icons = vim.tbl_deep_extend("force", {}, defaults)
  end
  return icons
end

M.get = get

return setmetatable(M, {
  __index = function(_, k)
    return get()[k]
  end,
})

local M = {}

---@type Lemon.Config
M.defaults = {
  hover = {
    border = "single",
    max_width = 0.6,
    max_height = 0.4,
    pad_right = 4,
    scroll_indicator = true,
    close_events = { "CursorMoved", "InsertEnter", "BufLeave" },
    close_key = "q",
    show_server = true,
    show_filetype = true,
    show_symbol = true,
    hide_diagnostic = false,
  },
  definition = {
    beacon = { enabled = true, fade_interval = 60, fade_step = 8 },
    tagstack = true,
  },
  diagnostic = {
    border = "single",
    max_width = 0.6,
    max_height = 0.4,
    pad_right = 4,
    scroll_indicator = true,
    close_events = { "CursorMoved", "InsertEnter", "BufLeave" },
    close_key = "q",
    confirm_key = "<CR>",
    show_server = true,
    show_filetype = true,
    hide_diagnostic = false,
    footer = { enabled = true, show_desc = true },
  },
  code_action = {
    border = "single",
    max_width = 0.6,
    max_height = 0.4,
    pad_right = 4,
    scroll_indicator = true,
    close_events = { "BufLeave" },
    close_key = "q",
    confirm_key = "<CR>",
    back_key = "<BS>",
    diff_context = 3,
    show_server = true,
    show_filetype = true,
    show_code = true,
    hide_diagnostic = false,
    footer = { enabled = true, show_desc = true },
  },
  symbol_icons = {
    ["function"] = "󰊕",
    ["function.call"] = "󰊕",
    ["function.method"] = "󰊕",
    ["function.method.call"] = "󰊕",
    ["function.builtin"] = "󰊕",
    ["constructor"] = "󰡱",
    ["variable"] = "󰀫",
    ["variable.parameter"] = "󰏪",
    ["variable.member"] = "󰜢",
    ["variable.builtin"] = "󰀫",
    ["property"] = "󰜢",
    ["type"] = "󰠱",
    ["type.builtin"] = "󰠱",
    ["module"] = "󰅩",
    ["keyword"] = "󰌆",
    ["constant"] = "󰏿",
    ["constant.builtin"] = "󰏿",
    ["string"] = "󰉿",
    ["number"] = "󰎠",
  },
  parsers = {},
  highlights = {},
  glyph = {},
}

---@type Lemon.Config|nil
M.options = nil

---@param opts? Lemon.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---@return Lemon.Config
function M.get()
  if not M.options then
    M.options = vim.tbl_deep_extend("force", {}, M.defaults)
  end
  return M.options
end

return M

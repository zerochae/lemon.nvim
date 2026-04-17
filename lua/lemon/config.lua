local M = {}

---@type Lemon.Config
M.defaults = {
  hover = {
    border = "single",
    max_height = 0.4,
    pad_right = 4,
    scroll_indicator = true,
    close_events = { "CursorMoved", "InsertEnter", "BufLeave" },
    close_key = "q",
    confirm_key = "<CR>",
    show_server = true,
    show_filetype = true,
    show_symbol = true,
    hide_diagnostic = false,
    conceal = true,
    show_kind_prefix = false,
    footer = { enabled = true, show_desc = true },
  },
  definition = {
    beacon = { enabled = true, fade_interval = 60, fade_step = 8 },
    tagstack = true,
  },
  diagnostic = {
    border = "single",
    max_height = 0.4,
    max_width = 0.8,
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
    max_height = 0.4,
    max_width = 0.8,
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
  signature_help = {
    border = "single",
    max_height = 0.3,
    pad_right = 4,
    scroll_indicator = true,
    close_events = { "InsertLeave", "BufLeave" },
    close_key = "q",
    show_server = true,
    show_filetype = false,
    hide_diagnostic = false,
    conceal = true,
    auto = true,
    footer = { enabled = true, show_desc = true },
  },
  inlay_hint = {
    enabled = true,
    only_current_line = false,
    show_parameter_hints = true,
    show_type_hints = true,
    type_format = "${hint}",
    param_format = "${hint}:",
    hide_in_insert = true,
    position = "inline",
    badge_alpha = 0.07,
    param_icon = true,
    type_icon = true,
    type_text = true,
    fn_icon = true,
    fn_return_text = false,
    generic_text = true,
    object_threshold = 3,
    expand_offset = 0,
  },
  scope = {
    enabled = true,
    separator = " > ",
    depth_limit = 0,
    depth_limit_indicator = "...",
    safe_output = true,
    lazy_update = false,
    biscuit = { enabled = true, visible_mode = "hover", treesitter = true, style = "muted" },
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

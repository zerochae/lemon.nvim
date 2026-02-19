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
  },
  definition = {
    beacon = { enabled = true, fade_interval = 60, fade_step = 8 },
    tagstack = true,
  },
  meta = {
    show_server = true,
    show_filetype = true,
    show_symbol = true,
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

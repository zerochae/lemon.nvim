local M = {}

local data = require "lemon.core.scope.data"

function M.render(bufnr, ns, symbols, winid, visible_mode, cursor_line)
  local visible_start = vim.fn.line("w0", winid) - 1
  local visible_end = vim.fn.line("w$", winid) - 1

  local endings = data.find_ending_symbols(symbols, visible_start, visible_end, visible_mode, cursor_line)

  for _, entry in ipairs(endings) do
    local sym = entry.symbol
    local icon = data.kind_icon(sym.kind)
    local hl = "LemonScopeBiscuit_" .. sym.kind

    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, entry.end_line, 0, {
      virt_text = { { " " .. icon .. " " .. sym.name .. " ", hl } },
      virt_text_pos = "eol",
      priority = 10,
      hl_mode = "combine",
    })
  end
end

return M

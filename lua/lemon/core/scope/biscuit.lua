local M = {}

local data = require "lemon.core.scope.data"
local treesitter = require "lemon.core.scope.treesitter"

local control_flow_names = {
  ["for"] = true,
  ["if"] = true,
  ["while"] = true,
  ["do"] = true,
  ["repeat"] = true,
  ["switch"] = true,
  ["try"] = true,
  ["with"] = true,
  ["select"] = true,
  ["match"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["loop"] = true,
}

function M.render(bufnr, ns, symbols, winid, visible_mode, cursor_line, cfg)
  local visible_start = vim.fn.line("w0", winid) - 1
  local visible_end = vim.fn.line("w$", winid) - 1

  local lsp_entries = data.find_ending_symbols(symbols, visible_start, visible_end, visible_mode, cursor_line)

  local used_lines = {}

  for _, entry in ipairs(lsp_entries) do
    local sym = entry.symbol
    if not control_flow_names[sym.name] then
      used_lines[entry.end_line] = true
      local icon = data.biscuit_icon(sym.kind)
      local hl = "LemonScopeBiscuit_" .. sym.kind

      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, entry.end_line, 0, {
        virt_text = { { " " .. icon .. " " .. sym.name .. " ", hl } },
        virt_text_pos = "eol",
        priority = 10,
        hl_mode = "combine",
      })
    end
  end

  if cfg and cfg.treesitter then
    local ts_entries = treesitter.find_scope_nodes(bufnr, visible_start, visible_end, visible_mode, cursor_line)

    for _, entry in ipairs(ts_entries) do
      if not used_lines[entry.end_line] then
        used_lines[entry.end_line] = true
        local icon = treesitter.keyword_icon(entry.keyword) or ""

        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, entry.end_line, 0, {
          virt_text = { { " " .. icon .. " " .. entry.text .. " ", "LemonScopeBiscuitKeyword" } },
          virt_text_pos = "eol",
          priority = 10,
          hl_mode = "combine",
        })
      end
    end
  end
end

return M

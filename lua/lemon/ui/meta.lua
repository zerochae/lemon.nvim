local M = {}

local glyph = require "lemon.glyph"

local function build_server(meta, server_name)
  if server_name then
    table.insert(meta, { icon = glyph.ui.server, text = server_name, hl = "LemonTitle", line_hl = "LemonTitle" })
  end
end

local function build_filetype(meta, source_bufnr)
  local ft = vim.api.nvim_get_option_value("filetype", { buf = source_bufnr })
  if ft == "" then
    return
  end
  local ft_icon, ft_hl = glyph.ui.file, nil
  local ok_devicon, devicons = pcall(require, "nvim-web-devicons")
  if ok_devicon then
    local fname = vim.api.nvim_buf_get_name(source_bufnr)
    local ext = vim.fn.fnamemodify(fname, ":e")
    local icon, hl = devicons.get_icon(fname, ext, { default = true })
    if icon then
      ft_icon = icon
      ft_hl = hl
    end
  end
  table.insert(meta, { icon = ft_icon, text = ft, hl = ft_hl or "LemonTitle" })
end

local function build_symbol(meta, source_bufnr)
  local cfg = require("lemon.config").get()
  local symbol = vim.fn.expand "<cword>"
  if symbol == "" then
    return
  end
  local symbol_icons = cfg.symbol_icons
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local sym_icon, sym_capture = glyph.ui.symbol_fallback, nil
  local ok, captures = pcall(vim.treesitter.get_captures_at_pos, source_bufnr, row - 1, col)
  if ok and captures then
    for i = #captures, 1, -1 do
      local name = captures[i].capture
      if symbol_icons[name] then
        sym_icon = symbol_icons[name]
        sym_capture = "@" .. name
        break
      end
    end
  end
  table.insert(meta, { icon = sym_icon, text = symbol, hl = sym_capture or "LemonTitle", text_hl = sym_capture })
end

local function build_code(meta, code)
  if code then
    table.insert(meta, { icon = glyph.ui.code, text = tostring(code), hl = "@comment", line_hl = "@comment" })
  end
end

function M.build(source_bufnr, server_name, code, opts)
  local meta = {}
  if opts.show_server then
    build_server(meta, server_name)
  end
  if opts.show_filetype then
    build_filetype(meta, source_bufnr)
  end
  if opts.show_symbol then
    build_symbol(meta, source_bufnr)
  end
  if opts.show_code then
    build_code(meta, code)
  end
  return meta
end

function M.to_lines(meta)
  local lines = {}
  local ext_list = {}
  for _, m in ipairs(meta) do
    table.insert(lines, m.text)
    local ext = { sign = { icon = m.icon, hl = m.hl } }
    if m.line_hl then
      ext.line_hl = m.line_hl
    end
    if m.text_hl then
      ext.text_hl = m.text_hl
    end
    table.insert(ext_list, ext)
  end
  return lines, ext_list
end

return M

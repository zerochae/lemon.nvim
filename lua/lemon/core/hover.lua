local M = {}

local glyph = require("lemon.glyph")

local hover_win = nil
local hover_buf = nil

local function process_contents(contents)
  local lines = {}

  local function add_markup(value)
    for _, line in ipairs(vim.split(value, "\n", { plain = true })) do
      table.insert(lines, line)
    end
  end

  if type(contents) == "string" then
    add_markup(contents)
  elseif type(contents) == "table" then
    if contents.kind then
      add_markup(contents.value or "")
    elseif contents.language then
      table.insert(lines, "```" .. contents.language)
      add_markup(contents.value or "")
      table.insert(lines, "```")
    elseif vim.islist(contents) then
      for i, item in ipairs(contents) do
        if i > 1 then
          table.insert(lines, "---")
        end
        if type(item) == "string" then
          add_markup(item)
        elseif item.language then
          table.insert(lines, "```" .. item.language)
          add_markup(item.value or "")
          table.insert(lines, "```")
        elseif item.value then
          add_markup(item.value)
        end
      end
    end
  end

  local result = {}
  for _, line in ipairs(lines) do
    line = line:gsub("&nbsp;", " ")
    line = line:gsub("&lt;", "<")
    line = line:gsub("&gt;", ">")
    line = line:gsub("&amp;", "&")
    line = line:gsub("<pre>", "")
    line = line:gsub("</pre>", "")
    table.insert(result, line)
  end

  while #result > 0 and result[1]:match "^%s*$" do
    table.remove(result, 1)
  end
  while #result > 0 and result[#result]:match "^%s*$" do
    table.remove(result)
  end

  return result
end

local function close_hover()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_win_close(hover_win, true)
  end
  if hover_buf and vim.api.nvim_buf_is_valid(hover_buf) then
    vim.api.nvim_buf_delete(hover_buf, { force = true })
  end
  hover_win = nil
  hover_buf = nil
end

local function show_hover(contents, server_name, source_bufnr)
  local cfg = require("lemon.config").get()
  local lines = process_contents(contents)
  if #lines == 0 then
    return
  end

  for i = #lines, 1, -1 do
    if lines[i]:match "^%-%-%-+$" then
      table.remove(lines, i)
    end
  end

  local symbol_icons = cfg.symbol_icons

  local function get_symbol_info()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local captures = vim.treesitter.get_captures_at_pos(source_bufnr, row - 1, col)
    for i = #captures, 1, -1 do
      local name = captures[i].capture
      if symbol_icons[name] then
        return symbol_icons[name], "@" .. name
      end
    end
    return glyph.ui.symbol_fallback, nil
  end

  local meta = {}

  if cfg.meta.show_server then
    table.insert(meta, { icon = glyph.ui.server, text = server_name, hl = "LemonTitle" })
  end

  if cfg.meta.show_filetype then
    local ft = vim.api.nvim_get_option_value("filetype", { buf = source_bufnr })
    if ft ~= "" then
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
  end

  if cfg.meta.show_symbol then
    local symbol = vim.fn.expand "<cword>"
    if symbol ~= "" then
      local sym_icon, sym_capture = get_symbol_info()
      table.insert(meta, { icon = sym_icon, text = symbol, hl = sym_capture or "LemonTitle", text_hl = sym_capture })
    end
  end

  table.insert(lines, 1, "")
  for i = #meta, 1, -1 do
    table.insert(lines, 1, meta[i].text)
  end

  local win_opts = require("lemon.ui.window").compute(lines, cfg)

  hover_buf = vim.api.nvim_create_buf(false, true)

  local content_lines = {}
  for i = #meta + 2, #lines do
    table.insert(content_lines, lines[i])
  end
  vim.lsp.util.stylize_markdown(hover_buf, content_lines, {})

  local meta_insert = {}
  for i = 1, #meta do
    table.insert(meta_insert, meta[i].text)
  end
  table.insert(meta_insert, "")
  vim.api.nvim_buf_set_lines(hover_buf, 0, 0, false, meta_insert)
  lines = vim.api.nvim_buf_get_lines(hover_buf, 0, -1, false)

  hover_win = vim.api.nvim_open_win(hover_buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = win_opts.width,
    height = win_opts.height,
    border = cfg.hover.border,
    style = "minimal",
  })

  vim.api.nvim_set_option_value("winhighlight", "Normal:LemonNormal,FloatBorder:LemonBorder,SignColumn:LemonNormal", { win = hover_win })
  vim.api.nvim_set_option_value("signcolumn", "yes", { win = hover_win })
  vim.api.nvim_set_option_value("wrap", true, { win = hover_win })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = hover_win })
  vim.api.nvim_set_option_value("concealcursor", "niv", { win = hover_win })

  vim.treesitter.start(hover_buf, "markdown")

  local ns = vim.api.nvim_create_namespace "lemon_hover"
  for i, m in ipairs(meta) do
    vim.api.nvim_buf_set_extmark(hover_buf, ns, i - 1, 0, {
      sign_text = m.icon,
      sign_hl_group = m.hl,
    })
    if m.text_hl then
      local line_len = #lines[i]
      vim.api.nvim_buf_set_extmark(hover_buf, ns, i - 1, 0, {
        end_col = line_len,
        hl_group = m.text_hl,
      })
    end
  end

  local tag_icons = require("lemon.parsers").get_all_tags()
  local content_start = #meta
  local total_lines = vim.api.nvim_buf_line_count(hover_buf)
  local first_content = true
  for i = content_start, total_lines - 1 do
    local l = lines[i + 1] or ""
    local matched = false
    local stripped = l:gsub("%*", ""):gsub("%s+", " "):gsub("^%s+", "")
    for pattern, tag_cfg in pairs(tag_icons) do
      if stripped:match("^" .. pattern .. "%s") or stripped:match("^" .. pattern .. "$") then
        vim.api.nvim_buf_set_extmark(hover_buf, ns, i, 0, {
          sign_text = tag_cfg.icon,
          sign_hl_group = tag_cfg.hl,
        })
        matched = true
        break
      end
    end
    if not matched and first_content and l ~= "" and not l:match "^```" then
      vim.api.nvim_buf_set_extmark(hover_buf, ns, i, 0, {
        sign_text = glyph.ui.content,
        sign_hl_group = "LemonTitle",
      })
      first_content = false
    end
  end

  local scrollbar = require("lemon.ui.scrollbar")
  local scrollable = total_lines > win_opts.height

  if scrollable and cfg.hover.scroll_indicator then
    scrollbar.update(hover_win, total_lines)
  end

  vim.api.nvim_buf_set_keymap(hover_buf, "n", cfg.hover.close_key, "", {
    callback = close_hover,
    nowait = true,
  })

  local augroup = vim.api.nvim_create_augroup("lemon_hover_close", { clear = true })

  for _, event in ipairs(cfg.hover.close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      buffer = source_bufnr,
      once = true,
      callback = close_hover,
    })
  end

  if scrollable and cfg.hover.scroll_indicator then
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = augroup,
      callback = function()
        if hover_win and vim.api.nvim_win_is_valid(hover_win) then
          scrollbar.update(hover_win, total_lines)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(hover_win),
    once = true,
    callback = function()
      close_hover()
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end,
  })
end

function M.hover()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_set_current_win(hover_win)
    return
  end

  local source_bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = source_bufnr, method = "textDocument/hover" }
  if #clients == 0 then
    return
  end

  local client = clients[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding or "utf-16")

  vim.lsp.buf_request(source_bufnr, "textDocument/hover", params, function(err, result)
    if err or not result or not result.contents then
      return
    end
    local val = result.contents
    if type(val) == "string" and #val == 0 then
      return
    end
    if type(val) == "table" and val.value and #val.value == 0 then
      return
    end

    vim.schedule(function()
      show_hover(result.contents, client.name or "LSP", source_bufnr)
    end)
  end)
end

return M

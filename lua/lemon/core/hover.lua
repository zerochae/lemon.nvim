local M = {}

local glyph = require "lemon.glyph"
local footer = require "lemon.ui.footer"
local FloatPanel = require "lemon.ui.float"

local HoverPanel = setmetatable({}, { __index = FloatPanel })
HoverPanel.__index = HoverPanel

local panel = HoverPanel:new "hover"

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

function HoverPanel:get_config()
  return FloatPanel.get_config(self)
end

function HoverPanel:build_content(contents, server_name)
  local lines = process_contents(contents)
  if #lines == 0 then
    return {}, {}
  end

  for i = #lines, 1, -1 do
    if lines[i]:match "^%-%-%-+$" then
      table.remove(lines, i)
    end
  end

  local meta_lines, meta_ext = self:build_meta(server_name)

  self.buf = vim.api.nvim_create_buf(false, true)

  local all_lines = {}
  for i = 1, #meta_lines do
    all_lines[#all_lines + 1] = meta_lines[i]
  end
  all_lines[#all_lines + 1] = ""
  for _, line in ipairs(lines) do
    all_lines[#all_lines + 1] = line
  end
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, all_lines)
  lines = all_lines

  self._meta_ext = meta_ext
  self._meta_count = #meta_lines

  return lines, {}
end

function HoverPanel:apply_extmarks(_, lines)
  local ns = vim.api.nvim_create_namespace "lemon_hover"
  for i, ext in ipairs(self._meta_ext or {}) do
    vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
      sign_text = ext.sign.icon,
      sign_hl_group = ext.sign.hl,
    })
    if ext.text_hl then
      local line_len = #lines[i]
      vim.api.nvim_buf_set_extmark(self.buf, ns, i - 1, 0, {
        end_col = line_len,
        hl_group = ext.text_hl,
      })
    end
  end

  local tag_icons = require("lemon.parsers").get_all_tags()
  local content_start = self._meta_count
  local total_lines = vim.api.nvim_buf_line_count(self.buf)
  local first_content = true
  for i = content_start, total_lines - 1 do
    local l = lines[i + 1] or ""
    local matched = false
    local stripped = l:gsub("%*", ""):gsub("%s+", " "):gsub("^%s+", "")
    for pattern, tag_cfg in pairs(tag_icons) do
      if stripped:match("^" .. pattern .. "%s") or stripped:match("^" .. pattern .. "$") then
        vim.api.nvim_buf_set_extmark(self.buf, ns, i, 0, {
          sign_text = tag_cfg.icon,
          sign_hl_group = tag_cfg.hl,
        })
        matched = true
        break
      end
    end
    if not matched and first_content and l ~= "" and not l:match "^```" then
      vim.api.nvim_buf_set_extmark(self.buf, ns, i, 0, {
        sign_text = glyph.ui.content,
        sign_hl_group = "LemonTitle",
      })
      first_content = false
    end
  end
end

function HoverPanel:close()
  local src = self.source_bufnr
  FloatPanel.close(self)
  if src and vim.api.nvim_buf_is_valid(src) then
    local cfg = self:get_config()
    pcall(vim.keymap.del, "n", cfg.confirm_key or "<CR>", { buffer = src })
  end
end

local function focus_panel()
  if not panel:is_open() then
    return
  end
  if panel.augroup and panel.source_bufnr then
    pcall(vim.api.nvim_clear_autocmds, { group = panel.augroup, buffer = panel.source_bufnr })
    pcall(vim.api.nvim_clear_autocmds, { group = panel.augroup, event = "WinScrolled" })
  end
  if panel.source_bufnr and vim.api.nvim_buf_is_valid(panel.source_bufnr) then
    local cfg = panel:get_config()
    pcall(vim.keymap.del, "n", cfg.confirm_key or "<CR>", { buffer = panel.source_bufnr })
  end
  vim.api.nvim_set_current_win(panel.win)
  local cfg = panel:get_config()
  footer.set(panel.win, {
    { icon = glyph.footer.move, desc = "move", key = "jk" },
    { icon = glyph.footer.close, desc = "close", key = cfg.close_key },
  }, cfg.footer)
end

function HoverPanel:after_open()
  vim.treesitter.start(self.buf, "markdown")
  local cfg = self:get_config()
  footer.set(self.win, {
    { icon = glyph.footer.enter, desc = "focus", key = cfg.confirm_key or "<CR>" },
  }, cfg.footer)
  vim.keymap.set("n", cfg.confirm_key or "<CR>", focus_panel, {
    buffer = self.source_bufnr,
    nowait = true,
    silent = true,
  })
end

function M.hover()
  if panel:is_open() then
    focus_panel()
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
      panel:show(source_bufnr, result.contents, client.name or "LSP")
    end)
  end)
end

return setmetatable(M, {
  __call = function(_)
    return M.hover()
  end,
})

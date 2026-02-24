local extmarks = require("lemon.ui.extmarks")
local meta_ui = require("lemon.ui.meta")
local scrollbar = require("lemon.ui.scrollbar")
local window = require("lemon.ui.window")

---@class Lemon.FloatPanel
local FloatPanel = {}
FloatPanel.__index = FloatPanel

function FloatPanel:new(name)
  return setmetatable({
    name = name,
    win = nil,
    buf = nil,
    source_bufnr = nil,
    augroup = nil,
    _enter = false,
  }, self)
end

function FloatPanel:is_open()
  return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

function FloatPanel:close()
  local win, buf = self.win, self.buf
  local augroup = self.augroup
  local source = self.source_bufnr
  self.win = nil
  self.buf = nil
  self.source_bufnr = nil
  self.augroup = nil

  if source and vim.api.nvim_buf_is_valid(source) then
    pcall(vim.diagnostic.enable, true, { bufnr = source })
  end

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace("lemon_diff_syntax"), 0, -1)
  end
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
  end
end

function FloatPanel:show(source_bufnr, ...)
  self:close()
  self.source_bufnr = source_bufnr

  local lines, ext_list = self:build_content(...)
  if not lines or #lines == 0 then
    return
  end

  self:open_win(lines)
  if not self:is_open() then
    return
  end

  local cfg = self:get_config()
  if cfg.hide_diagnostic then
    vim.diagnostic.enable(false, { bufnr = source_bufnr })
  end

  self:apply_extmarks(ext_list, lines)

  self:setup_keymaps()
  self:setup_autocmds()
  self:after_open()
end

function FloatPanel:open_win(lines)
  local cfg = self:get_config()
  local win_opts = window.compute(lines, {
    max_width = cfg.max_width,
    max_height = cfg.max_height,
    pad_right = cfg.pad_right,
    min_width = cfg.min_width,
    min_height = cfg.min_height,
    extra_height = cfg.extra_height,
  })

  local enter = cfg.enter or false
  self._enter = enter

  self.win = vim.api.nvim_open_win(self.buf, enter, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = win_opts.width,
    height = win_opts.height,
    border = cfg.border,
    style = "minimal",
  })

  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:LemonNormal,FloatBorder:LemonBorder,SignColumn:LemonNormal",
    { win = self.win }
  )
  vim.api.nvim_set_option_value("signcolumn", "yes", { win = self.win })
  vim.api.nvim_set_option_value("wrap", true, { win = self.win })

  if cfg.conceal then
    vim.api.nvim_set_option_value("conceallevel", 2, { win = self.win })
    vim.api.nvim_set_option_value("concealcursor", "niv", { win = self.win })
  end

  if cfg.cursorline then
    vim.api.nvim_set_option_value("cursorline", true, { win = self.win })
  end

  if enter then
    vim.api.nvim_set_current_win(self.win)
  end
end

function FloatPanel:apply_extmarks(ext_list, lines)
  extmarks.apply(self.buf, "lemon_" .. self.name, ext_list, lines, 0)
end

function FloatPanel:setup_keymaps()
  local cfg = self:get_config()
  local panel = self
  vim.api.nvim_buf_set_keymap(self.buf, "n", cfg.close_key, "", {
    callback = function()
      panel:close()
    end,
    nowait = true,
  })
end

function FloatPanel:setup_autocmds()
  local cfg = self:get_config()
  local panel = self
  local augroup = vim.api.nvim_create_augroup("lemon_" .. self.name .. "_close", { clear = true })
  self.augroup = augroup

  for _, event in ipairs(cfg.close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      buffer = self.source_bufnr,
      once = true,
      callback = function()
        panel:close()
      end,
    })
  end

  local total_lines = vim.api.nvim_buf_line_count(self.buf)
  local win_height = vim.api.nvim_win_get_height(self.win)
  local scrollable = total_lines > win_height

  if scrollable and cfg.scroll_indicator then
    scrollbar.update(self.win, total_lines)
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = augroup,
      callback = function()
        if panel:is_open() then
          scrollbar.update(panel.win, vim.api.nvim_buf_line_count(panel.buf))
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(self.win),
    once = true,
    callback = function()
      panel:close()
    end,
  })
end

function FloatPanel:resize(w, h)
  if not self:is_open() then
    return
  end
  vim.api.nvim_win_set_config(self.win, { width = w, height = h })
end

function FloatPanel:append_lines(lines)
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, -1, -1, false, lines)
  vim.bo[self.buf].modifiable = false
end

function FloatPanel:get_config()
  return require("lemon.config").get()[self.name] or {}
end

function FloatPanel:build_meta(server_name, code)
  local cfg = self:get_config()
  local meta = meta_ui.build(self.source_bufnr, server_name, code, cfg)
  return meta_ui.to_lines(meta)
end

function FloatPanel:build_content(_)
  return {}, {}
end

function FloatPanel:after_open() end

return FloatPanel

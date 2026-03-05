local glyph = require "lemon.glyph"
local diff = require "lemon.ui.diff"
local extmarks = require "lemon.ui.extmarks"

---@class Lemon.PreviewManager
local PreviewManager = {}
PreviewManager.__index = PreviewManager

function PreviewManager:new(panel)
  return setmetatable({
    panel = panel,
    action_cache = {},
    resolve_cache = {},
    diff_cache = {},
    current_idx = 0,
    updating = false,
    list_end_line = 0,
  }, self)
end

function PreviewManager:reset()
  self.action_cache = {}
  self.resolve_cache = {}
  self.diff_cache = {}
  self.current_idx = 0
  self.updating = false
  self.list_end_line = 0
  self.base_width = 0
end

function PreviewManager:attach(actions, list_end_line)
  self.action_cache = actions
  self.list_end_line = list_end_line
  if self.panel:is_open() then
    self.base_width = vim.api.nvim_win_get_width(self.panel.win)
  end
end

function PreviewManager:get_resolved(idx)
  return self.resolve_cache[idx]
end

function PreviewManager:update(idx)
  local panel = self.panel
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    return
  end
  if not panel:is_open() then
    return
  end
  if idx == self.current_idx then
    return
  end
  if self.updating then
    return
  end

  self.current_idx = idx
  local entry = self.action_cache[idx]
  if not entry then
    return
  end

  local ns_name = "lemon_" .. panel.name
  local ns = vim.api.nvim_create_namespace(ns_name)
  local separator_start = self.list_end_line
  local preview_ft = nil
  local preview_code_info = nil
  local preview_mgr = self

  local function render_preview(diff_lines, diff_extmarks)
    if preview_mgr.current_idx ~= idx then
      return
    end
    if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
      return
    end

    local cfg = panel:get_config()
    local columns = vim.api.nvim_get_option_value("columns", {})
    local max_width = cfg.max_width and math.floor(columns * cfg.max_width) or columns
    local sign_width = 2
    local base = preview_mgr.base_width or vim.api.nvim_win_get_width(panel.win)
    local max_content_len = base - sign_width
    for _, l in ipairs(diff_lines) do
      local w = vim.fn.strdisplaywidth(l)
      if w > max_content_len then
        max_content_len = w
      end
    end
    local new_width = math.min(max_content_len + sign_width + (cfg.pad_right or 0), max_width)
    new_width = math.max(new_width, base)

    vim.bo[panel.buf].modifiable = true

    local total = vim.api.nvim_buf_line_count(panel.buf)
    if total > separator_start then
      vim.api.nvim_buf_set_lines(panel.buf, separator_start, total, false, {})
    end

    local separator = string.rep("─", new_width - 2)
    local preview_block = { separator }
    for _, l in ipairs(diff_lines) do
      table.insert(preview_block, l)
    end

    vim.api.nvim_buf_set_lines(panel.buf, separator_start, separator_start, false, preview_block)
    vim.bo[panel.buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(panel.buf, ns, separator_start, -1)
    vim.api.nvim_buf_set_extmark(panel.buf, ns, separator_start, 0, {
      end_col = #separator,
      hl_group = "FloatBorder",
    })
    extmarks.apply(panel.buf, ns_name, diff_extmarks, diff_lines, separator_start + 1)
    diff.apply_syntax(panel.buf, preview_code_info, preview_ft, separator_start + 1)

    local new_total = vim.api.nvim_buf_line_count(panel.buf)
    local editor_lines = vim.api.nvim_get_option_value("lines", {})
    local max_height = math.floor(editor_lines * cfg.max_height)
    local new_height = math.min(new_total, max_height)
    new_height = math.max(new_height, separator_start + 1)
    panel:resize(new_width, new_height)

    preview_mgr.updating = false
  end

  if self.diff_cache[idx] then
    preview_ft = self.diff_cache[idx].ft
    preview_code_info = self.diff_cache[idx].code_info
    render_preview(self.diff_cache[idx].lines, self.diff_cache[idx].extmarks)
    return
  end

  if self.resolve_cache[idx] then
    local resolved = self.resolve_cache[idx]
    if not resolved.edit then
      local lines = { "No preview available — Enter to execute" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      self.diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
      return
    end
    local diff_context = panel:get_config().diff_context or 3
    local diffs =
      diff.compute(resolved.edit, vim.lsp.get_client_by_id(entry.client_id).offset_encoding or "utf-16", diff_context)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      self.diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      self.diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      render_preview(lines, ext)
    end
    return
  end

  local action = entry.action

  if action.edit then
    self.resolve_cache[idx] = action
    local client = vim.lsp.get_client_by_id(entry.client_id)
    local encoding = client and client.offset_encoding or "utf-16"
    local diff_context = panel:get_config().diff_context or 3
    local diffs = diff.compute(action.edit, encoding, diff_context)
    if #diffs == 0 then
      local lines = { "No changes detected" }
      local ext =
        { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
      self.diff_cache[idx] = { lines = lines, extmarks = ext }
      render_preview(lines, ext)
    else
      local lines, ext, ft, code_info = diff.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      self.diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      render_preview(lines, ext)
    end
    return
  end

  self.updating = true
  local loading_lines = { "Resolving..." }
  local loading_ext =
    { { sign = { icon = glyph.ui.loading, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
  render_preview(loading_lines, loading_ext)
  self.updating = true

  local client = vim.lsp.get_client_by_id(entry.client_id)
  if not client then
    self.updating = false
    return
  end

  client:request("codeAction/resolve", action, function(err, resolved)
    vim.schedule(function()
      if err or not resolved then
        preview_mgr.resolve_cache[idx] = action
        local lines = { "Resolve failed" }
        local ext = {
          {
            sign = { icon = glyph.ui.error, hl = "DiagnosticError" },
            line_hl = "DiagnosticError",
            text_hl = "DiagnosticError",
          },
        }
        preview_mgr.diff_cache[idx] = { lines = lines, extmarks = ext }
        preview_mgr.updating = false
        if preview_mgr.current_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      preview_mgr.resolve_cache[idx] = resolved
      local encoding = client.offset_encoding or "utf-16"

      if not resolved.edit then
        local lines = { "No preview available — Enter to execute" }
        local ext =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        preview_mgr.diff_cache[idx] = { lines = lines, extmarks = ext }
        preview_mgr.updating = false
        if preview_mgr.current_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      local diff_context = panel:get_config().diff_context or 3
      local diffs = diff.compute(resolved.edit, encoding, diff_context)
      if #diffs == 0 then
        local lines = { "No changes detected" }
        local ext =
          { { sign = { icon = glyph.ui.info, hl = "DiagnosticInfo" }, line_hl = "Comment", text_hl = "Comment" } }
        preview_mgr.diff_cache[idx] = { lines = lines, extmarks = ext }
        preview_mgr.updating = false
        if preview_mgr.current_idx == idx then
          render_preview(lines, ext)
        end
        return
      end

      local lines, ext, ft, code_info = diff.build_lines(diffs)
      preview_ft = ft
      preview_code_info = code_info
      preview_mgr.diff_cache[idx] = { lines = lines, extmarks = ext, ft = ft, code_info = code_info }
      preview_mgr.updating = false
      if preview_mgr.current_idx == idx then
        render_preview(lines, ext)
      end
    end)
  end, panel.buf)
end

function PreviewManager:clear_preview()
  local panel = self.panel
  if not panel.buf or not vim.api.nvim_buf_is_valid(panel.buf) then
    return
  end
  self.current_idx = 0
  local preview_start = self.list_end_line
  vim.bo[panel.buf].modifiable = true
  local total = vim.api.nvim_buf_line_count(panel.buf)
  if total > preview_start then
    vim.api.nvim_buf_set_lines(panel.buf, preview_start, total, false, {})
  end
  vim.bo[panel.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(panel.buf, vim.api.nvim_create_namespace "lemon_diff_syntax", 0, -1)

  if panel:is_open() then
    local new_height = vim.api.nvim_buf_line_count(panel.buf)
    local base = self.base_width or vim.api.nvim_win_get_width(panel.win)
    panel:resize(base, new_height)
  end
end

return PreviewManager

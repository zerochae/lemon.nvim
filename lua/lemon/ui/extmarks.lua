local M = {}

function M.apply(buf, ns_name, ext_list, lines, offset)
  local ns = vim.api.nvim_create_namespace(ns_name)
  for i, ext in ipairs(ext_list) do
    local row = offset + i - 1
    local opts = {}
    if ext.sign then
      opts.sign_text = ext.sign.icon
      opts.sign_hl_group = ext.sign.hl
    end
    if ext.line_hl then
      opts.line_hl_group = ext.line_hl
    end
    if ext.text_hl then
      local line_text = lines[i] or ""
      if #line_text > 0 then
        opts.end_col = #line_text
        opts.hl_group = ext.text_hl
      end
    end
    if next(opts) then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
    end
  end
end

return M

local M = {}

function M.goto_definition()
  local cfg = require("lemon.config").get()
  local clients = vim.lsp.get_clients { bufnr = 0, method = "textDocument/definition" }
  if #clients == 0 then
    vim.notify("No LSP client supports goto definition", vim.log.levels.WARN)
    return
  end
  local encoding = clients[1].offset_encoding or "utf-16"
  local params = vim.lsp.util.make_position_params(0, encoding)

  vim.cmd "normal! m'"

  local from_bufnr = vim.api.nvim_get_current_buf()
  local from_pos = vim.api.nvim_win_get_cursor(0)
  local from_word = vim.fn.expand "<cword>"

  vim.lsp.buf_request(0, "textDocument/definition", params, function(err, result)
    if err then
      vim.notify("LSP: " .. err.message, vim.log.levels.ERROR)
      return
    end
    if not result or (vim.islist(result) and #result == 0) then
      vim.notify("No definition found", vim.log.levels.INFO)
      return
    end

    local item = vim.islist(result) and result[1] or result
    local uri = item.targetUri or item.uri
    local range = item.targetSelectionRange or item.targetRange or item.range

    if not uri or not range then
      vim.notify("No definition found", vim.log.levels.INFO)
      return
    end

    local target_bufnr = vim.uri_to_bufnr(uri)
    vim.fn.bufload(target_bufnr)

    if cfg.definition.tagstack then
      local tagstack = { { tagname = from_word, from = { from_bufnr, from_pos[1], from_pos[2] + 1, 0 } } }
      vim.fn.settagstack(vim.fn.win_getid(), { items = tagstack }, "t")
    end

    local target_lnum = range.start.line
    local target_col = range.start.character

    if target_bufnr ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_set_current_buf(target_bufnr)
    end
    vim.api.nvim_win_set_cursor(0, { target_lnum + 1, target_col })

    vim.schedule(function()
      require("lemon.core.beacon").beacon(target_bufnr, target_lnum, target_col)
    end)
  end)
end

return M

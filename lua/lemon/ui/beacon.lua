local M = {}

function M.beacon(bufnr, lnum, col)
  local cfg = require("lemon.config").get().definition.beacon
  if not cfg.enabled then
    return
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
  local width = math.max(#line - col, 1)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep(" ", width) })
  local ns = vim.api.nvim_create_namespace("lemon_beacon")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = width, hl_group = "LemonBeacon" })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 0,
    col = 0,
    width = width,
    height = 1,
    style = "minimal",
    focusable = false,
    noautocmd = true,
  })
  vim.api.nvim_set_option_value("winblend", 0, { win = win })

  local blend = 0
  local timer = (vim.uv or vim.loop).new_timer()
  timer:start(
    0,
    cfg.fade_interval,
    vim.schedule_wrap(function()
      blend = blend + cfg.fade_step
      if blend >= 100 or not vim.api.nvim_win_is_valid(win) then
        timer:stop()
        timer:close()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        return
      end
      vim.api.nvim_set_option_value("winblend", blend, { win = win })
    end)
  )
end

return M

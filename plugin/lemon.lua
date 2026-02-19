if vim.g.loaded_lemon then
  return
end
vim.g.loaded_lemon = true

vim.api.nvim_create_user_command("Lemon", function(opts)
  local lemon = require("lemon")
  local args = opts.fargs

  if #args == 0 then
    lemon.hover()
    return
  end

  local subcmd = args[1]

  if subcmd == "hover" then
    lemon.hover()
  elseif subcmd == "definition" then
    lemon.definition()
  else
    vim.notify("[lemon] Unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(arg_lead)
    local subcommands = { "hover", "definition" }
    return vim.tbl_filter(function(s)
      return s:match("^" .. arg_lead)
    end, subcommands)
  end,
  desc = "LSP Easy More On Neovim",
})

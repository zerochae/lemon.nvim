# lemon.nvim

\[L\]SP \[E\]asy \[M\]ore \[O\]n \[N\]eovim

A unified LSP UI layer for Neovim — hover, diagnostics, code actions, signature help, inlay hints, and scope breadcrumbs in one place.

## Features

- **Hover** — styled markdown panel with tag icons and server info
- **Definition** — go-to-definition with beacon animation and tagstack
- **Diagnostic** — floating diagnostic panel with inline code actions and diff preview
- **Code Action** — numbered action list with live diff preview
- **Signature Help** — auto-triggered signature popup with overload cycling
- **Inlay Hint** — richly formatted virtual text with type/param icons and badge styling
- **Scope** — breadcrumb location bar with biscuit annotations via treesitter

## Install

### lazy.nvim

```lua
{
  "zerochae/lemon.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "LspAttach",
  opts = {},
}
```

See [config.lua](lua/lemon/config.lua) for all default values.

### Requirements

- Neovim >= 0.10
- LSP client configured

## Usage

After `setup()`, a global `Lemon` table is registered. All modules are lazy-loaded on first access.

```lua
Lemon.hover()
Lemon.definition()
Lemon.code_action()
Lemon.signature_help()

Lemon.diagnostic.goto_next()
Lemon.diagnostic.goto_prev()
Lemon.diagnostic.open_float()

Lemon.inlay_hint.toggle()
Lemon.inlay_hint.enable(bufnr)
Lemon.inlay_hint.disable(bufnr)

Lemon.scope.toggle()
Lemon.scope.get_data(bufnr)
Lemon.scope.get_location(bufnr)
Lemon.scope.is_available(bufnr)

-- require style works identically
local lemon = require("lemon")
lemon.hover()
```

### Commands

```
:Lemon                  " hover (default)
:Lemon hover
:Lemon definition
:Lemon code_action
:Lemon signature_help
:Lemon inlay_hint       " toggle
:Lemon scope            " toggle
```

### Keymaps example

```lua
vim.keymap.set("n", "K", function() Lemon.hover() end)
vim.keymap.set("n", "gd", function() Lemon.definition() end)
vim.keymap.set("n", "<leader>ca", function() Lemon.code_action() end)
vim.keymap.set("n", "]d", function() Lemon.diagnostic.goto_next() end)
vim.keymap.set("n", "[d", function() Lemon.diagnostic.goto_prev() end)
```

## API

| Function | Description |
| --- | --- |
| `Lemon.setup(opts)` | Initialize with optional config |
| `Lemon.hover()` | Show hover info, focus if already open |
| `Lemon.definition()` | Go to definition with beacon effect |
| `Lemon.code_action()` | Show code actions with diff preview |
| `Lemon.signature_help()` | Show signature help popup |
| `Lemon.diagnostic.goto_next()` | Jump to next diagnostic with float |
| `Lemon.diagnostic.goto_prev()` | Jump to previous diagnostic with float |
| `Lemon.diagnostic.open_float()` | Open diagnostic float at cursor |
| `Lemon.inlay_hint.enable(bufnr)` | Enable inlay hints |
| `Lemon.inlay_hint.disable(bufnr)` | Disable inlay hints |
| `Lemon.inlay_hint.toggle(bufnr)` | Toggle inlay hints |
| `Lemon.scope.toggle()` | Toggle scope breadcrumbs |
| `Lemon.scope.get_data(bufnr)` | Get scope data for buffer |
| `Lemon.scope.get_location(bufnr)` | Get current scope location string |
| `Lemon.scope.is_available(bufnr)` | Check if scope is available |

## Highlights

All groups link to built-in highlights by default. Override via the `highlights` option.

| Group | Default Link |
| --- | --- |
| `LemonNormal` | `NormalFloat` |
| `LemonBorder` | `FloatBorder` |
| `LemonTitle` | `Title` |
| `LemonBeacon` | `Search` |
| `LemonActionNumber` | `Number` |
| `LemonDiffAdd` | `DiffAdd` |
| `LemonDiffDelete` | `DiffDelete` |
| `LemonDiffHunk` | `Comment` |

## Custom Tag Parsers

Icons for doc comment tags in hover. jsdoc, doxygen, and python parsers are built-in.

```lua
require("lemon").setup({
  parsers = {
    ["@mycustomtag"] = { icon = "!", hl = "Special" },
  },
})
```

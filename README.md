# lemon.nvim

\[L\]SP \[E\]asy \[M\]ore \[O\]n \[N\]eovim 🍋

## Features

### Hover

<!-- ![hover](screenshots/hover.png) -->

### Code Action

<!-- ![code_action](screenshots/code_action.png) -->

### Diagnostic

<!-- ![diagnostic](screenshots/diagnostic.png) -->

### Definition

<!-- ![definition](screenshots/definition.png) -->

## Install

### lazy.nvim:

```lua
{
  "zerochae/lemon.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  event = "LspAttach",
  opts = {
    hover = { border = "rounded", max_width = 0.8 },
    definition = { beacon = { enabled = false } },
  },
}
```

See [config.lua](lua/lemon/config.lua) for all default values.

### Requirements

- Neovim >= 0.10
- LSP client configured

## API

| Function                              | Description                                            |
| ------------------------------------- | ------------------------------------------------------ |
| `require("lemon").setup(opts)`        | Initialize with optional config                        |
| `require("lemon").hover()`            | Show hover info. Focus existing window if already open |
| `require("lemon").definition()`       | Go to definition with beacon effect                    |
| `require("lemon").code_action()`      | Show code actions with diff preview                    |
| `require("lemon").diagnostic_next()`  | Jump to next diagnostic and open float                 |
| `require("lemon").diagnostic_prev()`  | Jump to previous diagnostic and open float             |
| `require("lemon").diagnostic_float()` | Open diagnostic float at cursor                        |

## Highlights

All groups link to built-in highlights by default. Override via the `highlights` option.

| Group               | Default Link  |
| ------------------- | ------------- |
| `LemonNormal`       | `NormalFloat` |
| `LemonBorder`       | `FloatBorder` |
| `LemonTitle`        | `Title`       |
| `LemonBeacon`       | `Search`      |
| `LemonActionNumber` | `Number`      |
| `LemonDiffAdd`      | `DiffAdd`     |
| `LemonDiffDelete`   | `DiffDelete`  |
| `LemonDiffHunk`     | `Comment`     |

## Custom Tag Parsers

Icons for doc comment tags in hover. jsdoc, doxygen, and python are built-in.

```lua
require("lemon").setup({
  parsers = {
    ["@mycustomtag"] = { icon = "🔥", hl = "Special" },
  },
})
```

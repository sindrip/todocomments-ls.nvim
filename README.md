# todocomments-ls.nvim

An in-process LSP server for Neovim that highlights TODO-style keywords using diagnostics and document colors. No external binary needed.

Requires Neovim 0.12+.

## Install

With vim.pack:

```lua
vim.pack.add("https://github.com/sindrip/todocomments-ls.nvim")
```

With lazy.nvim:

```lua
{ "sindrip/todocomments-ls.nvim" }
```

## Setup

```lua
vim.lsp.enable("todocomments-ls")
```

## Keywords

| Keyword | Aliases | Severity | Color |
|---|---|---|---|
| **FIX** | FIXME, BUG, FIXIT, ISSUE | Error | DiagnosticError |
| **TODO** | | Info | DiagnosticInfo |
| **HACK** | XXX | Warn | DiagnosticWarn |
| **WARN** | WARNING | Warn | DiagnosticWarn |
| **PERF** | OPTIM, PERFORMANCE | Hint | Identifier |
| **NOTE** | INFO | Hint | DiagnosticHint |
| **TEST** | TESTING, PASSED, FAILED | Info | Identifier |

Keywords are matched in comments (via treesitter) followed by `:` or `(scope):`.

## How it works

todocomments-ls registers as an LSP server that advertises `diagnosticProvider` and `colorProvider`. It scans buffer lines for keyword patterns, verifies they appear inside comments using treesitter, and returns them as LSP diagnostics and document colors.

Colors are resolved from highlight groups at runtime, so they adapt to your colorscheme.

## Alternatives

- [todo-comments.nvim](https://github.com/folke/todo-comments.nvim) — a more feature-rich plugin with sign column icons, telescope/trouble integration, and search commands.

#  Caesar/HeyVL integration for neovim 

A (work-in-progress) `nvim-lspconfig` and `nvim-treesitter` integration for the [Caesar Verifier](https://github.com/moves-rwth/caesar).

- The LSP functionality was ported from the upstream [VSCode extension](https://github.com/moves-rwth/caesar/tree/main/vscode-ext).
- The Tree-Sitter grammar can be found at [kernzerfall/tree-sitter-heyvl](https://github.com/kernzerfall/tree-sitter-heyvl). This was ported from the upstream [LALRPOP parser](https://github.com/moves-rwth/caesar/blob/main/src/front/parser/grammar.lalrpop).

![static/screen.png](static/screen.png)

## Installation

If you use `lazyvim`, just drop `caesar-lazyvim.lua` in your `.config/nvim/lua/plugins` directory, 
or adapt it for your own installation. For other neovim setups, you will have to adapt
the `lazyvim` config yourself.

You may need to run `:TSInstall heyvl` to get syntax highlighting.

**Note**: You need to install Caesar separately, and its executable needs to be in your `$PATH`.

## Features

- `CaesarVerify` command to verify the current buffer.
- `CaesarCounterexample` command to view counterexamples (if available).
- Reverify after writing (saving) buffers.
- Inline explanations (via `custom/computedPre`). Highly recommended to use [lsp_lines.nvim](https://git.sr.ht/~whynothugo/lsp_lines.nvim).
- Tree-Sitter config (among others for syntax highlighting).
- Handles `custom/documentStatus` (✔/✖/... next to proc/coproc/... depending on verification status)
- Statusline integration of `documentStatus` possible (e.g. with [lualine](https://github.com/nvim-lualine/lualine.nvim), see below).

### Statusline integration

For example, using `lazyvim` with [lualine](https://github.com/nvim-lualine/lualine.nvim), you can show the status on the left like this:

```lua
{
  "nvim-lualine/lualine.nvim",
  dependencies = { "kernzerfall/caesar.nvim" },
  opts = function(_, opts)
    table.insert(opts.sections.lualine_c, 1, {
      require("caesar").line_status,
      cond = function()
        return vim.bo.filetype == "heyvl"
      end,
      color = { fg = "#E8E6E3", bg = "#0E4E40" },
      separator = { right = "" },
    })
  end,
}
```

## Frequently Asked Questions

### Why did you make this?

Because I can

### Why don't you use VSCode like a normal person?

See [here](https://www.youtube.com/watch?v=rrAgnnRZMMk).

### Is this complete/correct/...?

Probably not.

### Will you maintain this?

Probably not.



return {
  {
    "kernzerfall/caesar.nvim",
    config = function()
      require("caesar").setup()
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        caesar = {
          -- remove `--explain-vc` to turn off explanations (some @tags don't support them!)
          cmd = { "caesar", "lsp", "--language-server", "--explain-vc" },
          filetypes = { "heyvl" },
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = { "kernzerfall/caesar.nvim" },
    init = function()
      require("caesar").register_parser()
    end,
  },
}

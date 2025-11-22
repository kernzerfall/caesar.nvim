vim.api.nvim_create_user_command("CaesarVerify", function()
  local bufnr = vim.api.nvim_get_current_buf()

  -- get the heyvl client attached to the current buffer
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "caesar" })[1]

  if not client then
    vim.notify("Caesar LSP is not attached to this buffer.", vim.log.levels.ERROR)
    return
  end

  local params = {
    text_document = {
      uri = vim.uri_from_bufnr(bufnr),
      version = vim.lsp.util.buf_versions[bufnr] or 0,
    },
  }

  ---@diagnostic disable for some reason, lua_ls complains about types in the following,
  ---                    but everything works out ok, so
  client.request("custom/verify", params, function(err, _)
    if err then
      vim.notify("Caesar Verification Error: " .. tostring(err.message), vim.log.levels.ERROR)
    end
  end, bufnr)
  ---@diagnostic enable
end, { desc = "Manually trigger Caesar verification" })

-- register the filetype
vim.filetype.add({
  extension = {
    heyvl = "heyvl",
  },
})

local function setup_explanations()
  local ns_id = vim.api.nvim_create_namespace("caesar_explanations")
  vim.api.nvim_set_hl(0, "CaesarVirtualText", { link = "DiagnosticVirtualTextInfo", default = true })

  local function wrap_text(text, max_width)
    local lines = {}
    local current_line = ""
    for word in text:gmatch("%S+") do
      if #current_line + #word + 1 > max_width then
        if #current_line > 0 then
          table.insert(lines, current_line)
        end
        current_line = word
      else
        current_line = (#current_line > 0) and (current_line .. " " .. word) or word
      end
    end
    if #current_line > 0 then
      table.insert(lines, current_line)
    end
    return lines
  end

  -- Function to Render Explanations for the CURRENT Line Only
  local function render_cursor_line_explanations(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Clear any existing Caesar virtual lines first (clean slate)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    -- Retrieve stored data
    local data = vim.b[bufnr].caesar_explanations
    if not data then
      return
    end

    -- Get current cursor line (0-indexed)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    -- Check if we have explanations specifically for this line
    local items = data[cursor_line]
    if not items or type(items) ~= "table" then
      return
    end

    -- window width calculations
    local win_width = vim.api.nvim_win_get_width(0)
    local content_width = math.max(40, win_width - 10)

    -- Render all items attached to this line
    for _, item in ipairs(items) do
      local range = item[1]
      local is_block = item[2]
      local explanations = item[3]

      local col = range.start.character
      if is_block then
        col = col + 4
      end
      local padding = string.rep(" ", col)
      local virt_lines = {}

      for i = #explanations, 1, -1 do
        local expl = explanations[i]
        local raw_text = expl[1]
        local available_width = content_width - col - 2

        local wrapped_lines = wrap_text(raw_text, available_width)

        if #wrapped_lines > 0 then
          table.insert(virt_lines, { { padding .. "▷ " .. wrapped_lines[1], "CaesarVirtualText" } })
        end
        for i = 2, #wrapped_lines do
          table.insert(virt_lines, { { padding .. "  " .. wrapped_lines[i], "CaesarVirtualText" } })
        end
      end

      if #virt_lines > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, cursor_line, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })
      end
    end
  end

  -- Autocommand to Trigger Render on Cursor Move
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = vim.api.nvim_create_augroup("CaesarHover", { clear = true }),
    pattern = "*.heyvl",
    callback = function(args)
      render_cursor_line_explanations(args.buf)
    end,
  })

  -- LSP Handler (Stores data instead of rendering directly)
  vim.lsp.handlers["custom/computedPre"] = function(err, result, ctx, _)
    if err then
      return
    end
    if not result or not result.pres then
      return
    end

    local bufnr = vim.uri_to_bufnr(result.document.uri)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- PROCESS & STORE DATA: Group by line number
    local lookup = {}
    for _, item in ipairs(result.pres) do
      local range = item[1]
      local start_line = range.start.line

      if not lookup[start_line] then
        lookup[start_line] = {}
      end
      table.insert(lookup[start_line], item)
    end

    -- Save to buffer-local variable
    vim.b[bufnr].caesar_explanations = lookup

    -- Trigger an immediate render for the current line (in case we are already on one)
    render_cursor_line_explanations(bufnr)
  end
end

-- final config for treesitter and lsp
return {
  {
    "nvim-treesitter/nvim-treesitter",
    init = function()
      -- register the language with treesitter
      vim.treesitter.language.register("heyvl", "heyvl")

      -- this adds the grammar to treesitter
      -- note: this autocmd is the NEW method for adding stuff after the rewrite
      -- (on the github repo, the rewrite sits on the NON-DEFAULT `main` branch!)
      vim.api.nvim_create_autocmd("User", {
        pattern = "TSUpdate",
        callback = function()
          require("nvim-treesitter.parsers").heyvl = {
            install_info = {
              url = "https://github.com/kernzerfall/tree-sitter-heyvl",
              files = { "src/parser.c" },
              queries = "queries/",
              revision = "619fa849941274be1b0c37613935622b36f6754e",
            },
            tier = 2, -- tier: unstable
            maintainers = { "@kernzerfall" },
            filetype = "heyvl",
          }
        end,
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        caesar = {
          cmd = { "caesar", "lsp", "--language-server", "--explain-vc" },
          filetypes = { "heyvl" },
        },
      },
    },
    init = function()
      -- Handle explanations
      setup_explanations()

      -- Reverify after writing a buffer
      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.heyvl",
        callback = function()
          vim.cmd("CaesarVerify")
        end,
      })
    end,
  },
}

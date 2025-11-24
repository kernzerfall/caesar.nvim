local M = {}

-- register the filetype
vim.filetype.add({
	extension = {
		heyvl = "heyvl",
	},
})

-- setup the custom/verify command
local function setup_verify()
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
end

-- handle explanations (custom/computedPre)
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
				for j = 2, #wrapped_lines do
					table.insert(virt_lines, { { padding .. "  " .. wrapped_lines[j], "CaesarVirtualText" } })
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

	-- LSP Handler for computedPre (Stores data instead of rendering directly)
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

-- LSP Handler for documentStatus
local function setup_document_status()
	local ns_status = vim.api.nvim_create_namespace("caesar_status")

	-- You can customize these colors or link them to standard groups
	vim.api.nvim_set_hl(0, "CaesarStatusVerified", { link = "DiagnosticOk", default = true })
	vim.api.nvim_set_hl(0, "CaesarStatusFailed", { link = "DiagnosticError", default = true })
	vim.api.nvim_set_hl(0, "CaesarStatusUnknown", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "CaesarStatusTimeout", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "CaesarStatusOngoing", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "CaesarStatusTodo", { link = "Comment", default = true })

	-- Mapping from Caesar status strings to Icons & Highlights
	local status_map = {
		verified = { icon = "✔", hl = "CaesarStatusVerified" },
		failed = { icon = "✖", hl = "CaesarStatusFailed" },
		unknown = { icon = "?", hl = "CaesarStatusUnknown" },
		timeout = { icon = "⏱", hl = "CaesarStatusTimeout" },
		ongoing = { icon = "…", hl = "CaesarStatusOngoing" },
		todo = { icon = "·", hl = "CaesarStatusTodo" },
	}

	vim.lsp.handlers["custom/documentStatus"] = function(err, result, ctx, _)
		if err then
			return
		end
		if not result or not result.document then
			return
		end

		local bufnr = vim.uri_to_bufnr(result.document.uri)
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		-- Clear previous status signs
		vim.api.nvim_buf_clear_namespace(bufnr, ns_status, 0, -1)

		-- The payload contains:
		-- verify_statuses: List of [Range, StatusString]
		-- status_counts:   List of [StatusString, Count] (Useful for statusline)
		-- status_type:     "ongoing" | "done" | ... (Overall document status)

		if result.verify_statuses then
			for _, item in ipairs(result.verify_statuses) do
				local range = item[1]
				local status_str = item[2] -- "verified", "failed", etc.
				local config = status_map[status_str:lower()]

				if config then
					local start_line = range.start.line
					-- Place a sign in the gutter using extmarks
					vim.api.nvim_buf_set_extmark(bufnr, ns_status, start_line, 0, {
						sign_text = config.icon,
						sign_hl_group = config.hl,
						-- High priority to ensure it sits "on top" of other signs if needed
						priority = 50,
					})
				end
			end
		end

		vim.b[bufnr].caesar_status_type = result.status_type
		vim.b[bufnr].caesar_status_counts = result.status_counts
	end
end

function M.parser_default_config()
	return {
		install_info = {
			url = "https://github.com/kernzerfall/tree-sitter-heyvl",
			files = { "src/parser.c" },
			queries = "queries/",
			branch = "master",
		},
		tier = 2, -- tier: unstable
		maintainers = { "@kernzerfall" },
		filetype = "heyvl",
	}
end

function M.register_parser(parser_config)
	-- register the language with treesitter
	vim.treesitter.language.register("heyvl", "heyvl")

	-- this adds the grammar to treesitter
	-- note: this autocmd is the NEW method for adding stuff after the rewrite
	-- (on the github repo, the rewrite sits on the NON-DEFAULT `main` branch!)
	vim.api.nvim_create_autocmd("User", {
		pattern = "TSUpdate",
		callback = function()
			require("nvim-treesitter.parsers").heyvl = parser_config or M.parser_default_config()
		end,
	})
end

function M.colours_default()
	return {
		declaration_condition = { fg = "#E86D77" },
		declaration_var = { link = "@keyword" },
		declaration = { fg = "#90BB64" },
	}
end

local function setup_colours(opts)
	local hl = vim.api.nvim_set_hl
	hl(0, "@keyword.declaration.condition", opts.declaration_condition)
	hl(0, "@keyword.declaration.var", opts.declaration_var)
	hl(0, "@keyword.declaration", opts.declaration)
end

function M.setup(opts)
	setup_explanations()
	setup_verify()
	setup_document_status()
	setup_colours(opts and opts.hl or M.colours_default())

	-- Reverify after writing a buffer
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = "*.heyvl",
		callback = function()
			vim.cmd("CaesarVerify")
		end,
	})
end

-- Status output for statuslines (e.g. lualine)
function M.line_status()
	local counts = vim.b.caesar_status_counts
	if not counts or vim.tbl_isempty(counts) then
		return ""
	end

	local icons = {
		verified = "✔",
		failed = "✖",
		unknown = "?",
		timeout = "⏱",
		ongoing = "…",
		todo = "·",
	}

	local parts = {}
	for _, item in ipairs(counts) do
		local status = item[1]:lower()
		local count = item[2]
		if icons[status] then
			table.insert(parts, icons[status] .. " " .. count)
		end
	end
	return "Caesar[" .. table.concat(parts, " ") .. "]"
end

return M

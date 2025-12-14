local M = {}

M.config = require("neopg.config")
M.env_parser = require("neopg.env_parser")

-- Lazy load modules to avoid circular dependencies
local function get_executor()
	return require("neopg.executor")
end

local function get_history()
	return require("neopg.history")
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Initialize configuration
	M.config.setup(opts)
	local config = M.config.get()

	-- Set up keymaps for SQL files
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "sql", "pgsql" },
		callback = function()
			local buf = vim.api.nvim_get_current_buf()

			-- Run paragraph
			if config.sql_keymaps.run_paragraph then
				vim.keymap.set("n", config.sql_keymaps.run_paragraph, function()
					get_executor().run_paragraph()
				end, { buffer = buf, desc = "Run SQL paragraph with neopg" })
			end

			-- Run visual selection
			if config.sql_keymaps.run_selection then
				vim.keymap.set("v", config.sql_keymaps.run_selection, function()
					get_executor().run_selection()
				end, { buffer = buf, desc = "Run SQL selection with neopg" })
			end

			-- Reset connection
			if config.sql_keymaps.reset_connection then
				vim.keymap.set("n", config.sql_keymaps.reset_connection, function()
					M.config.clear_config()
				end, { buffer = buf, desc = "Reset SQL connection" })
			end

			-- Query history
			if config.keymaps.history then
				vim.keymap.set("n", config.keymaps.history, function()
					get_history().show_picker()
				end, { buffer = buf, desc = "Show query history" })
			end
		end,
	})

	-- Create user commands
	vim.api.nvim_create_user_command("NeopgRunParagraph", function()
		get_executor().run_paragraph()
	end, { desc = "Run SQL paragraph under cursor" })

	vim.api.nvim_create_user_command("NeopgRunSelection", function()
		get_executor().run_selection()
	end, { desc = "Run selected SQL", range = true })

	vim.api.nvim_create_user_command("NeopgResetConnection", function()
		M.config.clear_config()
	end, { desc = "Reset database connection" })

	vim.api.nvim_create_user_command("NeopgHistory", function()
		get_history().show_picker()
	end, { desc = "Show query history" })

	vim.api.nvim_create_user_command("NeopgClearHistory", function()
		get_history().clear()
	end, { desc = "Clear query history" })
end

return M

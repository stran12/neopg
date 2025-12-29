local M = {}

-- State for the raw output viewer
M.state = nil

-- Create the viewer state
local function create_state(result)
	return {
		result = result,
		bufnr = nil,
		winnr = nil,
		ns_id = vim.api.nvim_create_namespace("neopg_raw"),
	}
end

-- Setup keymaps for the raw output buffer
local function setup_keymaps(state)
	local buf = state.bufnr
	local opts = { buffer = buf, noremap = true, silent = true }

	-- Re-run command
	vim.keymap.set("n", "r", function()
		local executor = require("neopg.executor")
		executor.rerun_query()
	end, opts)

	-- Help
	vim.keymap.set("n", "?", function()
		M.show_help()
	end, opts)
end

-- Render raw output in current window
function M.render(result)
	-- Create state
	M.state = create_state(result)
	local state = M.state

	-- Create buffer (listed=true for buffer navigation)
	state.bufnr = vim.api.nvim_create_buf(true, true)
	state.winnr = vim.api.nvim_get_current_win()

	-- Switch to the new buffer in current window
	vim.api.nvim_set_current_buf(state.bufnr)

	-- Prepare content
	local lines = {}

	-- Add header with command info
	table.insert(lines, "-- Meta-command: " .. result.query)
	if result.execution_time then
		table.insert(lines, string.format("-- Execution time: %.3fs", result.execution_time))
	end
	table.insert(lines, "-- Press '?' for help")
	table.insert(lines, "")

	-- Add output lines
	if result.output and result.output ~= "" then
		for line in result.output:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end
	else
		table.insert(lines, "(No output)")
	end

	-- Set buffer content
	vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)

	-- Buffer options
	vim.api.nvim_buf_set_option(state.bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "hide")
	vim.api.nvim_buf_set_option(state.bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(state.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(state.bufnr, "filetype", "neopg_raw")
	vim.api.nvim_buf_set_name(state.bufnr, "neopg://meta-command")

	-- Window options
	vim.api.nvim_win_set_option(state.winnr, "number", true)
	vim.api.nvim_win_set_option(state.winnr, "relativenumber", false)
	vim.api.nvim_win_set_option(state.winnr, "signcolumn", "no")
	vim.api.nvim_win_set_option(state.winnr, "cursorline", true)
	vim.api.nvim_win_set_option(state.winnr, "wrap", false)
	vim.api.nvim_win_set_option(state.winnr, "list", false)

	-- Clean up state when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = state.bufnr,
		callback = function()
			M.state = nil
		end,
	})

	-- Setup keymaps
	setup_keymaps(state)

	-- Position cursor after header
	vim.api.nvim_win_set_cursor(state.winnr, { 5, 0 })
end

-- Close the viewer (kept for programmatic use)
function M.close()
	if not M.state then
		return
	end

	local state = M.state
	local executor = require("neopg.executor")
	local source_bufnr = executor.get_source_bufnr()

	-- Delete the buffer
	if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
		vim.api.nvim_buf_delete(state.bufnr, { force = true })
	end

	-- Clear state
	M.state = nil

	-- Return to source buffer if it exists
	if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
		vim.api.nvim_set_current_buf(source_bufnr)
	end
end

-- Show help popup
function M.show_help()
	local help_lines = {
		"NeoPG - Meta-Command Viewer",
		"",
		"Navigation:",
		"  j/k       Move down/up",
		"  Ctrl-d/u  Half page down/up",
		"  Ctrl-f/b  Full page down/up",
		"  gg/G      First/last line",
		"",
		"Actions:",
		"  r         Re-run command",
		"  ?         Show this help",
		"",
		"Use normal buffer commands to close/switch",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)

	local width = 35
	local height = #help_lines
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})

	-- Close on any key
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
	vim.keymap.set("n", "?", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
end

return M

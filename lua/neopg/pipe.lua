local M = {}

-- State for the output floating window
M.output_win = nil
M.output_buf = nil

-- Close the output window if it exists
local function close_output_window()
	if M.output_win and vim.api.nvim_win_is_valid(M.output_win) then
		vim.api.nvim_win_close(M.output_win, true)
	end
	M.output_win = nil
	M.output_buf = nil
end

-- Calculate optimal window dimensions
local function calculate_window_size(content_lines)
	local max_width = math.floor(vim.o.columns * 0.8)
	local max_height = math.floor(vim.o.lines * 0.8)

	-- Calculate content width
	local content_width = 40 -- minimum
	for _, line in ipairs(content_lines) do
		content_width = math.max(content_width, #line)
	end

	local width = math.min(content_width + 2, max_width)
	local height = math.min(#content_lines, max_height)

	return width, height
end

-- Display output in a floating window
local function show_output_window(output, exit_code, command)
	close_output_window()

	-- Prepare content lines
	local lines = {}

	-- Header with command info
	table.insert(lines, "Command: " .. command)
	table.insert(lines, "Exit code: " .. tostring(exit_code))
	table.insert(lines, string.rep("-", 40))
	table.insert(lines, "")

	-- stdout
	if output and output ~= "" then
		for line in output:gmatch("[^\r\n]*") do
			table.insert(lines, line)
		end
	end

	-- Handle empty output
	if #lines == 4 then
		table.insert(lines, "(No output)")
	end

	-- Calculate dimensions
	local width, height = calculate_window_size(lines)

	-- Create buffer
	M.output_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(M.output_buf, 0, -1, false, lines)

	-- Buffer options
	vim.api.nvim_buf_set_option(M.output_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(M.output_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.output_buf, "modifiable", false)

	-- Create floating window
	M.output_win = vim.api.nvim_open_win(M.output_buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Pipe Output ",
		title_pos = "center",
	})

	-- Window options for scrolling
	vim.api.nvim_win_set_option(M.output_win, "wrap", false)
	vim.api.nvim_win_set_option(M.output_win, "cursorline", true)

	-- Setup keymaps to close
	local close_keys = { "q", "<Esc>", "|" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, close_output_window, { buffer = M.output_buf })
	end
end

-- Execute command with value piped to stdin (non-interactive)
local function execute_pipe(value, command)
	local result = vim.fn.system(command, value)
	local exit_code = vim.v.shell_error
	show_output_window(result, exit_code, command)
end

-- Execute command interactively with full terminal control
local function execute_pipe_interactive(value, command)
	-- Write value to a temp file for the command to read
	local tmpfile = vim.fn.tempname()
	local file = io.open(tmpfile, "w")
	if not file then
		vim.notify("Failed to create temp file", vim.log.levels.ERROR)
		return
	end
	file:write(value)
	file:close()

	-- Schedule the command to run after vim.ui.input callback completes
	-- This ensures proper terminal handling
	vim.schedule(function()
		-- Use termopen in a fullscreen terminal buffer for interactive programs
		vim.cmd("tabnew")
		local buf = vim.api.nvim_get_current_buf()
		local shell_cmd = string.format("%s < '%s'", command, tmpfile)

		vim.fn.termopen(shell_cmd, {
			on_exit = function()
				-- Clean up temp file and close tab when done
				os.remove(tmpfile)
				vim.schedule(function()
					-- Close the terminal tab if it still exists
					if vim.api.nvim_buf_is_valid(buf) then
						vim.cmd("bdelete!")
					end
				end)
			end,
		})

		-- Enter insert mode to interact with the terminal
		vim.cmd("startinsert")
	end)
end

-- Get cell value from state, with validation
local function get_cell_value(state)
	local row = state.result.rows[state.cursor_row]
	if not row then
		vim.notify("No row at cursor position", vim.log.levels.WARN)
		return nil
	end

	local value = row[state.cursor_col]
	if value == nil or value == "" then
		vim.notify("Cell is empty", vim.log.levels.WARN)
		return nil
	end

	return value
end

-- Pipe current cell value to external command (non-interactive, floating window output)
function M.pipe_cell(state)
	local value = get_cell_value(state)
	if not value then
		return
	end

	vim.ui.input({ prompt = "Pipe to command: " }, function(command)
		if not command or command == "" then
			return
		end
		execute_pipe(value, command)
	end)
end

-- Pipe current cell value to interactive program (full terminal control)
function M.pipe_cell_interactive(state)
	local value = get_cell_value(state)
	if not value then
		return
	end

	vim.ui.input({ prompt = "Pipe to interactive command: " }, function(command)
		if not command or command == "" then
			return
		end
		execute_pipe_interactive(value, command)
	end)
end

return M

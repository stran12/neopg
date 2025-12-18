local M = {}

-- Show error in a floating window with full content visible
function M.error(message, title)
	title = title or "Error"

	-- Split message into lines
	local lines = {}
	for line in message:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	-- Calculate dimensions
	local max_width = 0
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, #line)
	end

	-- Constrain to reasonable size
	local width = math.min(max_width + 2, math.floor(vim.o.columns * 0.8))
	local height = math.min(#lines, math.floor(vim.o.lines * 0.6))

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})

	-- Set error highlight
	vim.api.nvim_win_set_option(win, "winhl", "Normal:ErrorMsg,FloatBorder:ErrorMsg")

	-- Close on q, Esc, or Enter
	local close_keys = { "q", "<Esc>", "<CR>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			vim.api.nvim_win_close(win, true)
		end, { buffer = buf })
	end
end

return M

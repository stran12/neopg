local M = {}

local renderer = require("neopg.renderer")

-- Helper to clamp value between min and max
local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

-- Get visible row count
local function get_visible_rows(state)
	if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
		return 20
	end
	local win_height = vim.api.nvim_win_get_height(state.winnr)
	return win_height - 3 -- header + separator + statusline
end

-- Calculate how many non-pinned columns can fit in the available width
local function get_visible_col_count(state)
	if not state.winnr or not vim.api.nvim_win_is_valid(state.winnr) then
		return 5 -- fallback
	end

	local win_width = vim.api.nvim_win_get_width(state.winnr)
	local pinned = state.pinned_columns or 0

	-- Calculate width used by pinned columns
	local pinned_width = 1 -- leading border
	for i = 1, pinned do
		if not state.hidden_columns[i] then
			pinned_width = pinned_width + state.column_widths[i] + 1 -- +1 for separator
		end
	end

	-- Available width for non-pinned columns
	local available = win_width - pinned_width

	-- Count how many columns fit
	local count = 0
	local used = 0
	for i = state.view_col, #state.result.columns do
		if not state.hidden_columns[i] then
			local col_width = state.column_widths[i] + 1 -- +1 for separator
			if used + col_width <= available then
				used = used + col_width
				count = count + 1
			else
				break
			end
		end
	end

	return math.max(1, count)
end

-- Ensure cursor is visible in viewport
local function ensure_cursor_visible(state)
	local visible_rows = get_visible_rows(state)

	-- Vertical scrolling
	if state.cursor_row < state.view_row then
		state.view_row = state.cursor_row
	elseif state.cursor_row >= state.view_row + visible_rows then
		state.view_row = state.cursor_row - visible_rows + 1
	end

	-- Horizontal scrolling
	local pinned = state.pinned_columns or 0

	-- If cursor is in pinned area, no need to scroll horizontally
	if state.cursor_col <= pinned then
		return
	end

	-- Cursor is in non-pinned area
	-- view_col is the first non-pinned column shown after pinned columns

	-- Calculate the last visible column in current viewport
	local visible_count = get_visible_col_count(state)
	local last_visible_col = state.view_col + visible_count - 1

	-- If cursor is before the viewport, scroll left to show it
	if state.cursor_col < state.view_col then
		state.view_col = state.cursor_col
	-- If cursor is after the viewport, scroll right to show it
	elseif state.cursor_col > last_visible_col then
		-- Scroll so cursor is at the right edge of visible area
		state.view_col = state.cursor_col - visible_count + 1
		-- Make sure we don't go below pinned+1
		if state.view_col <= pinned then
			state.view_col = pinned + 1
		end
	end
end

-- Movement functions
function M.move_left(state)
	if state.cursor_col > 1 then
		-- Find previous non-hidden column
		local new_col = state.cursor_col - 1
		while new_col >= 1 and state.hidden_columns[new_col] do
			new_col = new_col - 1
		end
		if new_col >= 1 then
			state.cursor_col = new_col
			ensure_cursor_visible(state)
			renderer.refresh()
		end
	end
end

function M.move_right(state)
	local num_cols = #state.result.columns
	if state.cursor_col < num_cols then
		-- Find next non-hidden column
		local new_col = state.cursor_col + 1
		while new_col <= num_cols and state.hidden_columns[new_col] do
			new_col = new_col + 1
		end
		if new_col <= num_cols then
			state.cursor_col = new_col
			ensure_cursor_visible(state)
			renderer.refresh()
		end
	end
end

function M.move_up(state)
	if state.cursor_row > 1 then
		state.cursor_row = state.cursor_row - 1
		ensure_cursor_visible(state)
		renderer.refresh()
	end
end

function M.move_down(state)
	local num_rows = #state.result.rows
	if state.cursor_row < num_rows then
		state.cursor_row = state.cursor_row + 1
		ensure_cursor_visible(state)
		renderer.refresh()
	end
end

function M.skip_cols_right(state)
	local config = require("neopg.config").get()
	local skip = config.column_skip_count
	local num_cols = #state.result.columns

	local new_col = state.cursor_col
	local skipped = 0
	while skipped < skip and new_col < num_cols do
		new_col = new_col + 1
		if not state.hidden_columns[new_col] then
			skipped = skipped + 1
		end
	end

	state.cursor_col = new_col
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.skip_cols_left(state)
	local config = require("neopg.config").get()
	local skip = config.column_skip_count

	local new_col = state.cursor_col
	local skipped = 0
	while skipped < skip and new_col > 1 do
		new_col = new_col - 1
		if not state.hidden_columns[new_col] then
			skipped = skipped + 1
		end
	end

	state.cursor_col = new_col
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.first_col(state)
	-- Find first non-hidden column
	local new_col = 1
	while new_col <= #state.result.columns and state.hidden_columns[new_col] do
		new_col = new_col + 1
	end
	state.cursor_col = new_col
	-- Reset horizontal viewport to show columns from the beginning
	local pinned = state.pinned_columns or 0
	state.view_col = pinned + 1
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.last_col(state)
	-- Find last non-hidden column
	local new_col = #state.result.columns
	while new_col >= 1 and state.hidden_columns[new_col] do
		new_col = new_col - 1
	end
	state.cursor_col = new_col
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.first_row(state)
	state.cursor_row = 1
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.last_row(state)
	state.cursor_row = #state.result.rows
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.top_visible(state)
	state.cursor_row = state.view_row
	renderer.refresh()
end

function M.middle_visible(state)
	local visible_rows = get_visible_rows(state)
	local middle = state.view_row + math.floor(visible_rows / 2)
	state.cursor_row = clamp(middle, 1, #state.result.rows)
	renderer.refresh()
end

function M.bottom_visible(state)
	local visible_rows = get_visible_rows(state)
	local bottom = state.view_row + visible_rows - 1
	state.cursor_row = clamp(bottom, 1, #state.result.rows)
	renderer.refresh()
end

function M.skip_rows_down(state)
	local config = require("neopg.config").get()
	local skip = config.row_skip_count
	local num_rows = #state.result.rows

	state.cursor_row = clamp(state.cursor_row + skip, 1, num_rows)
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.skip_rows_up(state)
	local config = require("neopg.config").get()
	local skip = config.row_skip_count

	state.cursor_row = clamp(state.cursor_row - skip, 1, #state.result.rows)
	ensure_cursor_visible(state)
	renderer.refresh()
end

function M.half_page_down(state)
	local visible_rows = get_visible_rows(state)
	local half = math.floor(visible_rows / 2)
	local num_rows = #state.result.rows

	state.cursor_row = clamp(state.cursor_row + half, 1, num_rows)
	state.view_row = clamp(state.view_row + half, 1, math.max(1, num_rows - visible_rows + 1))
	renderer.refresh()
end

function M.half_page_up(state)
	local visible_rows = get_visible_rows(state)
	local half = math.floor(visible_rows / 2)

	state.cursor_row = clamp(state.cursor_row - half, 1, #state.result.rows)
	state.view_row = clamp(state.view_row - half, 1, state.view_row)
	renderer.refresh()
end

function M.page_down(state)
	local visible_rows = get_visible_rows(state)
	local num_rows = #state.result.rows

	state.cursor_row = clamp(state.cursor_row + visible_rows, 1, num_rows)
	state.view_row = clamp(state.view_row + visible_rows, 1, math.max(1, num_rows - visible_rows + 1))
	renderer.refresh()
end

function M.page_up(state)
	local visible_rows = get_visible_rows(state)

	state.cursor_row = clamp(state.cursor_row - visible_rows, 1, #state.result.rows)
	state.view_row = clamp(state.view_row - visible_rows, 1, state.view_row)
	renderer.refresh()
end

-- Column width adjustment
function M.expand_column(state)
	local col = state.cursor_col
	if state.column_widths[col] then
		state.column_widths[col] = state.column_widths[col] + 2
		renderer.refresh()
	end
end

function M.shrink_column(state)
	local col = state.cursor_col
	if state.column_widths[col] and state.column_widths[col] > 4 then
		state.column_widths[col] = state.column_widths[col] - 2
		renderer.refresh()
	end
end

function M.reset_columns(state)
	state.column_widths = vim.deepcopy(state.result.column_widths)
	renderer.refresh()
end

-- Column visibility
function M.hide_column(state)
	local col = state.cursor_col
	-- Don't hide if it's the only visible column
	local visible_count = 0
	for i = 1, #state.result.columns do
		if not state.hidden_columns[i] then
			visible_count = visible_count + 1
		end
	end

	if visible_count > 1 then
		state.hidden_columns[col] = true
		-- Move to next visible column
		M.move_right(state)
		if state.cursor_col == col then
			M.move_left(state)
		end
		renderer.refresh()
	end
end

function M.show_all_columns(state)
	state.hidden_columns = {}
	renderer.refresh()
end

-- Pin current column (make all columns up to and including current pinned)
function M.pin_column(state)
	local col = state.cursor_col
	state.pinned_columns = col
	-- Reset view_col to be after pinned
	state.view_col = col + 1
	if state.view_col > #state.result.columns then
		state.view_col = #state.result.columns
	end
	renderer.refresh()
end

-- Unpin all columns
function M.unpin_column(state)
	state.pinned_columns = 0
	state.view_col = 1
	renderer.refresh()
end

function M.toggle_column_info(state)
	local col = state.cursor_col
	local col_name = state.result.columns[col]
	local width = state.column_widths[col]

	-- Get sample values from first few rows
	local samples = {}
	for i = 1, math.min(5, #state.result.rows) do
		local val = state.result.rows[i][col]
		if val and val ~= "" then
			table.insert(samples, val)
		end
	end

	local info_lines = {
		"Column: " .. col_name,
		"Index: " .. col,
		"Width: " .. width,
		"Sample values:",
	}
	for _, sample in ipairs(samples) do
		table.insert(info_lines, "  " .. sample)
	end

	-- Show in floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, info_lines)

	local width = 40
	local height = #info_lines
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		width = width,
		height = height,
		col = 1,
		row = 1,
		style = "minimal",
		border = "rounded",
	})

	-- Close on any key
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
end

-- Visual line mode for multi-row selection
function M.start_visual_line(state)
	-- Store the start row for visual selection
	state.visual_start_row = state.cursor_row
	state.visual_mode = true
end

-- Get visual selection range
function M.get_visual_range(state)
	if not state.visual_mode or not state.visual_start_row then
		return state.cursor_row, state.cursor_row
	end

	local start_row = math.min(state.visual_start_row, state.cursor_row)
	local end_row = math.max(state.visual_start_row, state.cursor_row)
	return start_row, end_row
end

-- Exit visual mode
function M.exit_visual_mode(state)
	state.visual_mode = false
	state.visual_start_row = nil
end

return M

local M = {}

-- Highlight groups
local hl_groups = {
	NeopgHeader = { link = "Title" },
	NeopgHeaderPinned = { link = "Title", bold = true },
	NeopgHeaderSep = { link = "Comment" },
	NeopgCell = { link = "Normal" },
	NeopgCellPinned = { link = "Normal", bold = true },
	NeopgCellCurrent = { bg = "#3c3836", bold = true },
	NeopgCellNull = { link = "Comment" },
	NeopgBorder = { link = "Comment" },
	NeopgPinnedSep = { fg = "#665c54" },
	NeopgStatusLine = { link = "StatusLine" },
	NeopgSearchMatch = { link = "Search" },
}

-- State for the current pager
M.state = nil

-- Setup highlight groups
local function setup_highlights()
	for name, opts in pairs(hl_groups) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

-- Create the pager state
local function create_state(result)
	local config = require("neopg.config").get()
	return {
		result = result,
		bufnr = nil,
		winnr = nil,
		tabnr = nil,
		-- Cursor position (1-indexed, data coordinates)
		cursor_row = 1,
		cursor_col = 1,
		-- Viewport (which row/col is at top-left of visible area)
		-- view_col is the first NON-PINNED column to show
		view_row = 1,
		view_col = config.pinned_columns + 1,
		-- Column widths (can be adjusted by user)
		column_widths = vim.deepcopy(result.column_widths),
		-- Hidden columns
		hidden_columns = {},
		-- Pinned columns count
		pinned_columns = config.pinned_columns,
		-- Search state
		search_pattern = nil,
		search_matches = {},
		-- Namespace for extmarks
		ns_id = vim.api.nvim_create_namespace("neopg"),
	}
end

-- Get list of visible columns (pinned + scrolled viewport)
local function get_visible_columns(state)
	local visible = {}
	local num_cols = #state.result.columns

	-- First add pinned columns
	for i = 1, math.min(state.pinned_columns, num_cols) do
		if not state.hidden_columns[i] then
			table.insert(visible, { idx = i, pinned = true })
		end
	end

	-- Then add columns from viewport
	for i = state.view_col, num_cols do
		if not state.hidden_columns[i] and i > state.pinned_columns then
			table.insert(visible, { idx = i, pinned = false })
		end
	end

	return visible
end

-- Calculate the x position for a column in the rendered output
local function get_col_x_position(state, col_idx)
	local visible = get_visible_columns(state)
	local x = 1 -- Start with border

	for _, col in ipairs(visible) do
		if col.idx == col_idx then
			return x
		end
		x = x + state.column_widths[col.idx] + 1 -- +1 for separator
	end
	return x
end

-- Format a cell value with proper width
local function format_cell(value, width)
	value = value or ""
	if #value > width - 2 then
		return " " .. value:sub(1, width - 4) .. ".. "
	end
	-- Left-pad with space, right-pad to width
	local padded = " " .. value
	return padded .. string.rep(" ", width - #padded)
end

-- Render the header line
local function render_header(state)
	local result = state.result
	local visible = get_visible_columns(state)
	local parts = { "" }
	local hl_ranges = {}
	local pos = 0
	local after_pinned = false

	for _, col in ipairs(visible) do
		local i = col.idx
		local width = state.column_widths[i]
		local cell = format_cell(result.columns[i], width)

		-- Add pinned separator if transitioning from pinned to non-pinned
		if not col.pinned and not after_pinned and state.pinned_columns > 0 then
			table.insert(parts, cell)
			after_pinned = true
		else
			table.insert(parts, cell)
		end

		-- Track highlight range
		local hl = col.pinned and "NeopgHeaderPinned" or "NeopgHeader"
		table.insert(hl_ranges, {
			start = pos + 1,
			finish = pos + 1 + width,
			hl = hl,
			col_idx = i,
			pinned = col.pinned,
		})
		pos = pos + 1 + width
	end

	return table.concat(parts, "|"), hl_ranges
end

-- Render a separator line
local function render_separator(state)
	local visible = get_visible_columns(state)
	local parts = { "" }

	for _, col in ipairs(visible) do
		local width = state.column_widths[col.idx]
		table.insert(parts, string.rep("-", width))
	end

	return table.concat(parts, "+") .. "+"
end

-- Render a data row
local function render_row(state, row_idx)
	local result = state.result
	local row = result.rows[row_idx]
	if not row then
		return nil
	end

	local visible = get_visible_columns(state)
	local parts = { "" }
	local hl_ranges = {}
	local pos = 0

	for _, col in ipairs(visible) do
		local i = col.idx
		local value = row[i] or ""
		local width = state.column_widths[i]
		local cell = format_cell(value, width)
		table.insert(parts, cell)

		-- Determine highlight
		local hl = "NeopgCell"
		if row_idx == state.cursor_row and i == state.cursor_col then
			hl = "NeopgCellCurrent"
		elseif col.pinned then
			hl = "NeopgCellPinned"
		elseif value == "" or value:match("^%s*$") or value:upper() == "NULL" then
			hl = "NeopgCellNull"
		end

		table.insert(hl_ranges, {
			start = pos + 1,
			finish = pos + 1 + width,
			hl = hl,
			row = row_idx,
			col = i,
		})
		pos = pos + 1 + width
	end

	return table.concat(parts, "|"), hl_ranges
end

-- Check if a column is currently visible
local function is_column_visible(state, col_idx)
	-- Pinned columns are always visible
	if col_idx <= state.pinned_columns then
		return true
	end
	-- Check if in viewport
	return col_idx >= state.view_col
end

-- Render the statusline
local function render_statusline(state)
	local result = state.result
	local config = require("neopg.config").get()

	if not config.show_statusline then
		return nil
	end

	local parts = {}

	-- Position
	table.insert(parts, string.format("Row %d of %d", state.cursor_row, #result.rows))
	table.insert(parts, string.format("Col %d of %d", state.cursor_col, #result.columns))

	-- Execution time
	if result.execution_time then
		table.insert(parts, string.format("(%.3fs)", result.execution_time))
	end

	-- Truncation warning
	if result.was_limited then
		table.insert(parts, "[LIMIT " .. result.limit .. "]")
	end

	return " " .. table.concat(parts, " | ")
end

-- Update the buffer content
local function update_buffer(state)
	if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
		return
	end

	local lines = {}
	local all_hl_ranges = {}

	-- Header
	local header, header_hl = render_header(state)
	table.insert(lines, header)
	for _, hl in ipairs(header_hl) do
		hl.line = 0
		table.insert(all_hl_ranges, hl)
	end

	-- Separator
	local sep = render_separator(state)
	table.insert(lines, sep)

	-- Data rows
	local win_height = vim.api.nvim_win_get_height(state.winnr)
	local visible_rows = win_height - 3 -- header + separator + statusline

	local start_row = state.view_row
	local end_row = math.min(start_row + visible_rows - 1, #state.result.rows)

	for row_idx = start_row, end_row do
		local row_line, row_hl = render_row(state, row_idx)
		if row_line then
			table.insert(lines, row_line)
			local line_idx = #lines - 1
			for _, hl in ipairs(row_hl) do
				hl.line = line_idx
				table.insert(all_hl_ranges, hl)
			end
		end
	end

	-- Statusline
	local statusline = render_statusline(state)
	if statusline then
		table.insert(lines, statusline)
	end

	-- Set buffer content
	vim.api.nvim_buf_set_option(state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(state.bufnr, "modifiable", false)

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(state.bufnr, state.ns_id, 0, -1)

	-- Apply highlights
	for _, hl in ipairs(all_hl_ranges) do
		vim.api.nvim_buf_add_highlight(state.bufnr, state.ns_id, hl.hl, hl.line, hl.start, hl.finish)
	end

	-- Highlight search matches (only for visible cells)
	if state.search_pattern and #state.search_matches > 0 then
		local visible_cols = get_visible_columns(state)
		local visible_col_set = {}
		for _, col in ipairs(visible_cols) do
			visible_col_set[col.idx] = true
		end

		for _, match in ipairs(state.search_matches) do
			-- Check if match is in visible row range AND visible column set
			if match.row >= start_row and match.row <= end_row and visible_col_set[match.col] then
				local line_idx = match.row - start_row + 2 -- +2 for header and separator
				local col_x = get_col_x_position(state, match.col)
				local width = state.column_widths[match.col]
				vim.api.nvim_buf_add_highlight(
					state.bufnr,
					state.ns_id,
					"NeopgSearchMatch",
					line_idx,
					col_x,
					col_x + width
				)
			end
		end
	end
end

-- Setup keymaps for the pager buffer
local function setup_keymaps(state)
	local config = require("neopg.config").get()
	local km = config.keymaps
	local buf = state.bufnr
	local opts = { buffer = buf, noremap = true, silent = true }

	-- Get modules
	local navigator = require("neopg.navigator")
	local search = require("neopg.search")
	local yank = require("neopg.yank")
	local export = require("neopg.export")
	local executor = require("neopg.executor")

	-- Quit
	vim.keymap.set("n", km.quit, function()
		M.close()
	end, opts)

	-- Navigation
	vim.keymap.set("n", km.move_left, function()
		navigator.move_left(state)
	end, opts)
	vim.keymap.set("n", km.move_right, function()
		navigator.move_right(state)
	end, opts)
	vim.keymap.set("n", km.move_up, function()
		navigator.move_up(state)
	end, opts)
	vim.keymap.set("n", km.move_down, function()
		navigator.move_down(state)
	end, opts)
	vim.keymap.set("n", km.skip_cols_right, function()
		navigator.skip_cols_right(state)
	end, opts)
	vim.keymap.set("n", km.skip_cols_left, function()
		navigator.skip_cols_left(state)
	end, opts)
	vim.keymap.set("n", km.first_col, function()
		navigator.first_col(state)
	end, opts)
	vim.keymap.set("n", km.first_col_alt, function()
		navigator.first_col(state)
	end, opts)
	vim.keymap.set("n", km.last_col, function()
		navigator.last_col(state)
	end, opts)
	vim.keymap.set("n", km.first_row, function()
		navigator.first_row(state)
	end, opts)
	vim.keymap.set("n", km.last_row, function()
		navigator.last_row(state)
	end, opts)
	vim.keymap.set("n", km.top_visible, function()
		navigator.top_visible(state)
	end, opts)
	vim.keymap.set("n", km.middle_visible, function()
		navigator.middle_visible(state)
	end, opts)
	vim.keymap.set("n", km.bottom_visible, function()
		navigator.bottom_visible(state)
	end, opts)
	vim.keymap.set("n", km.skip_rows_down, function()
		navigator.skip_rows_down(state)
	end, opts)
	vim.keymap.set("n", km.skip_rows_up, function()
		navigator.skip_rows_up(state)
	end, opts)
	vim.keymap.set("n", km.half_page_down, function()
		navigator.half_page_down(state)
	end, opts)
	vim.keymap.set("n", km.half_page_up, function()
		navigator.half_page_up(state)
	end, opts)
	vim.keymap.set("n", km.page_down, function()
		navigator.page_down(state)
	end, opts)
	vim.keymap.set("n", km.page_up, function()
		navigator.page_up(state)
	end, opts)

	-- Search
	vim.keymap.set("n", km.search, function()
		search.start_search(state)
	end, opts)
	vim.keymap.set("n", km.search_next, function()
		search.next_match(state)
	end, opts)
	vim.keymap.set("n", km.search_prev, function()
		search.prev_match(state)
	end, opts)
	vim.keymap.set("n", km.search_current_cell, function()
		search.search_current_cell(state)
	end, opts)
	vim.keymap.set("n", km.clear_search, function()
		search.clear_search(state)
	end, opts)

	-- Yank
	vim.keymap.set("n", km.yank_cell, function()
		yank.yank_cell(state)
	end, opts)
	vim.keymap.set("n", km.yank_row, function()
		yank.yank_row(state)
	end, opts)
	vim.keymap.set("n", km.yank_row_alt, function()
		yank.yank_row(state)
	end, opts)
	vim.keymap.set("v", "y", function()
		yank.yank_selection(state)
	end, opts)

	-- Pipe
	local pipe = require("neopg.pipe")
	vim.keymap.set("n", km.pipe_cell, function()
		pipe.pipe_cell(state)
	end, opts)
	vim.keymap.set("n", km.pipe_cell_interactive, function()
		pipe.pipe_cell_interactive(state)
	end, opts)

	-- Export
	vim.keymap.set("n", km.export_csv, function()
		export.export_csv(state)
	end, opts)
	vim.keymap.set("n", km.export_json, function()
		export.export_json(state)
	end, opts)
	vim.keymap.set("n", km.export_sql, function()
		export.export_sql(state)
	end, opts)

	-- Column width adjustment
	vim.keymap.set("n", km.expand_column, function()
		navigator.expand_column(state)
	end, opts)
	vim.keymap.set("n", km.shrink_column, function()
		navigator.shrink_column(state)
	end, opts)
	vim.keymap.set("n", km.reset_columns, function()
		navigator.reset_columns(state)
	end, opts)

	-- Column visibility
	vim.keymap.set("n", km.hide_column, function()
		navigator.hide_column(state)
	end, opts)
	vim.keymap.set("n", km.show_all_columns, function()
		navigator.show_all_columns(state)
	end, opts)
	vim.keymap.set("n", km.toggle_column_info, function()
		navigator.toggle_column_info(state)
	end, opts)

	-- Pinned columns
	vim.keymap.set("n", km.pin_column, function()
		navigator.pin_column(state)
	end, opts)
	vim.keymap.set("n", km.unpin_column, function()
		navigator.unpin_column(state)
	end, opts)

	-- Re-run
	vim.keymap.set("n", km.rerun_query, function()
		executor.rerun_query()
	end, opts)
	vim.keymap.set("n", km.rerun_no_limit, function()
		executor.rerun_no_limit()
	end, opts)

	-- Help
	vim.keymap.set("n", km.show_help, function()
		M.show_help()
	end, opts)

	-- Visual line mode for multi-row selection
	vim.keymap.set("n", "V", function()
		navigator.start_visual_line(state)
	end, opts)

	-- Sort/Filter (buffer-local commands)
	vim.api.nvim_buf_create_user_command(buf, "Sort", function()
		local sort_filter = require("neopg.sort_filter")
		sort_filter.sort_by_column(state)
	end, { desc = "Sort by current column" })

	vim.api.nvim_buf_create_user_command(buf, "Filter", function(cmd_opts)
		local sort_filter = require("neopg.sort_filter")
		if cmd_opts.args and cmd_opts.args ~= "" then
			-- Direct filter with argument
			state.filter_pattern = cmd_opts.args
			sort_filter.filter_by_pattern(state)
		else
			sort_filter.filter_by_pattern(state)
		end
	end, { desc = "Filter by pattern", nargs = "?" })

	vim.api.nvim_buf_create_user_command(buf, "ClearFilter", function()
		local sort_filter = require("neopg.sort_filter")
		sort_filter.clear_filter(state)
	end, { desc = "Clear filter" })

	-- History from pager
	local history = require("neopg.history")
	vim.keymap.set("n", km.history, function()
		history.show_picker()
	end, opts)
end

-- Render results in a new tab
function M.render(result)
	setup_highlights()

	-- Create state
	M.state = create_state(result)
	local state = M.state

	-- Create new tab
	vim.cmd("tabnew")
	state.tabnr = vim.api.nvim_get_current_tabpage()
	state.winnr = vim.api.nvim_get_current_win()

	-- Create buffer
	state.bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(state.winnr, state.bufnr)

	-- Buffer options
	vim.api.nvim_buf_set_option(state.bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(state.bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(state.bufnr, "filetype", "neopg")
	vim.api.nvim_buf_set_name(state.bufnr, "neopg://results")

	-- Window options
	vim.api.nvim_win_set_option(state.winnr, "number", false)
	vim.api.nvim_win_set_option(state.winnr, "relativenumber", false)
	vim.api.nvim_win_set_option(state.winnr, "signcolumn", "no")
	vim.api.nvim_win_set_option(state.winnr, "cursorline", false)
	vim.api.nvim_win_set_option(state.winnr, "wrap", false)
	vim.api.nvim_win_set_option(state.winnr, "list", false)

	-- Setup keymaps
	setup_keymaps(state)

	-- Initial render
	update_buffer(state)
end

-- Close the pager
function M.close()
	if not M.state then
		return
	end

	local state = M.state
	local executor = require("neopg.executor")
	local source_bufnr = executor.get_source_bufnr()

	-- Close the tab
	if state.tabnr and vim.api.nvim_tabpage_is_valid(state.tabnr) then
		-- Get windows in the tab
		local wins = vim.api.nvim_tabpage_list_wins(state.tabnr)
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
	end

	-- Clear state
	M.state = nil

	-- Return to source buffer if it exists
	if source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
		-- Find a window showing the source buffer, or create one
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == source_bufnr then
				vim.api.nvim_set_current_win(win)
				return
			end
		end
	end
end

-- Refresh the display (called by navigator/search/etc)
function M.refresh()
	if M.state then
		update_buffer(M.state)
	end
end

-- Get current state
function M.get_state()
	return M.state
end

-- Show help popup
function M.show_help()
	local config = require("neopg.config").get()
	local km = config.keymaps

	local help_lines = {
		"NeoPG - PostgreSQL Result Pager",
		"",
		"Navigation:",
		string.format("  %s/%s/%s/%s  Move cell", km.move_left, km.move_down, km.move_up, km.move_right),
		string.format("  %s/%s      Skip %d columns", km.skip_cols_right, km.skip_cols_left, config.column_skip_count),
		string.format("  %s/%s      First/last column", km.first_col, km.last_col),
		string.format("  %s/%s      First/last row", km.first_row, km.last_row),
		string.format("  %s/%s      Skip %d rows", km.skip_rows_down, km.skip_rows_up, config.row_skip_count),
		"",
		"Search:",
		string.format("  %s        Search", km.search),
		string.format("  %s/%s      Next/prev match", km.search_next, km.search_prev),
		string.format("  %s        Search current cell", km.search_current_cell),
		"",
		"Yank:",
		string.format("  %s        Yank cell to clipboard", km.yank_cell),
		string.format("  %s       Yank row as CSV", km.yank_row),
		"  V + y    Yank selected rows as CSV",
		"",
		"Export:",
		string.format("  %s  Export as CSV", km.export_csv),
		string.format("  %s  Export as JSON", km.export_json),
		string.format("  %s  Export as SQL", km.export_sql),
		"",
		"Columns:",
		string.format("  %s/%s      Expand/shrink column", km.expand_column, km.shrink_column),
		string.format("  %s        Reset column widths", km.reset_columns),
		string.format("  %s       Hide column", km.hide_column),
		string.format("  %s       Show all columns", km.show_all_columns),
		"",
		"Other:",
		string.format("  %s        Re-run query", km.rerun_query),
		string.format("  %s        Re-run without LIMIT", km.rerun_no_limit),
		string.format("  %s        Quit", km.quit),
	}

	-- Create floating window for help
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)

	local width = 45
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

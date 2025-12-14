local M = {}

local renderer = require("neopg.renderer")

-- Helper to ensure cursor is visible (replicates navigator logic)
local function ensure_cursor_visible(state)
	-- Vertical scrolling
	local win_height = 20
	if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
		win_height = vim.api.nvim_win_get_height(state.winnr)
	end
	local visible_rows = win_height - 3

	if state.cursor_row < state.view_row then
		state.view_row = state.cursor_row
	elseif state.cursor_row >= state.view_row + visible_rows then
		state.view_row = state.cursor_row - visible_rows + 1
	end

	-- Horizontal scrolling
	local pinned = state.pinned_columns or 0

	if state.cursor_col <= pinned then
		return
	end

	-- Calculate visible column count
	local win_width = 80
	if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
		win_width = vim.api.nvim_win_get_width(state.winnr)
	end

	local pinned_width = 1
	for i = 1, pinned do
		if not state.hidden_columns[i] then
			pinned_width = pinned_width + state.column_widths[i] + 1
		end
	end

	local available = win_width - pinned_width
	local count = 0
	local used = 0
	for i = state.view_col, #state.result.columns do
		if not state.hidden_columns[i] then
			local col_width = state.column_widths[i] + 1
			if used + col_width <= available then
				used = used + col_width
				count = count + 1
			else
				break
			end
		end
	end
	local visible_count = math.max(1, count)
	local last_visible_col = state.view_col + visible_count - 1

	if state.cursor_col < state.view_col then
		state.view_col = state.cursor_col
	elseif state.cursor_col > last_visible_col then
		state.view_col = state.cursor_col - visible_count + 1
		if state.view_col <= pinned then
			state.view_col = pinned + 1
		end
	end
end

-- Start search mode
function M.start_search(state)
	vim.ui.input({ prompt = "Search: " }, function(pattern)
		if not pattern or pattern == "" then
			return
		end

		state.search_pattern = pattern
		M.find_all_matches(state)

		if #state.search_matches > 0 then
			-- Jump to first match
			M.jump_to_match(state, 1)
		else
			renderer.refresh()
		end
	end)
end

-- Find all matches in the ENTIRE dataset
function M.find_all_matches(state)
	state.search_matches = {}

	if not state.search_pattern or state.search_pattern == "" then
		return
	end

	local pattern = state.search_pattern:lower()

	-- Search ALL rows and columns
	for row_idx, row in ipairs(state.result.rows) do
		for col_idx, value in ipairs(row) do
			if not state.hidden_columns[col_idx] then
				local cell_value = (value or ""):lower()
				if cell_value:find(pattern, 1, true) then
					table.insert(state.search_matches, {
						row = row_idx,
						col = col_idx,
						value = value,
					})
				end
			end
		end
	end
end

-- Jump to a specific match by index and move viewport
function M.jump_to_match(state, match_idx)
	if #state.search_matches == 0 then
		return
	end

	-- Wrap around
	if match_idx < 1 then
		match_idx = #state.search_matches
	elseif match_idx > #state.search_matches then
		match_idx = 1
	end

	state.current_match_idx = match_idx
	local match = state.search_matches[match_idx]

	-- Move cursor to match
	state.cursor_row = match.row
	state.cursor_col = match.col

	-- Move viewport to show the match
	ensure_cursor_visible(state)

	renderer.refresh()
end

-- Go to next match
function M.next_match(state)
	if #state.search_matches == 0 then
		if state.search_pattern then
			M.find_all_matches(state)
			if #state.search_matches > 0 then
				M.jump_to_match(state, 1)
			end
		end
		return
	end

	local current_idx = state.current_match_idx or 0
	M.jump_to_match(state, current_idx + 1)
end

-- Go to previous match
function M.prev_match(state)
	if #state.search_matches == 0 then
		if state.search_pattern then
			M.find_all_matches(state)
			if #state.search_matches > 0 then
				M.jump_to_match(state, #state.search_matches)
			end
		end
		return
	end

	local current_idx = state.current_match_idx or 2
	M.jump_to_match(state, current_idx - 1)
end

-- Search for current cell value
function M.search_current_cell(state)
	local row = state.result.rows[state.cursor_row]
	if not row then
		return
	end

	local value = row[state.cursor_col]
	if not value or value == "" then
		return
	end

	state.search_pattern = value
	M.find_all_matches(state)

	if #state.search_matches > 0 then
		-- Find current position in matches
		for i, match in ipairs(state.search_matches) do
			if match.row == state.cursor_row and match.col == state.cursor_col then
				state.current_match_idx = i
				break
			end
		end
	end

	renderer.refresh()
end

-- Clear search highlighting
function M.clear_search(state)
	state.search_pattern = nil
	state.search_matches = {}
	state.current_match_idx = nil
	renderer.refresh()
end

return M

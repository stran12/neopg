local M = {}

-- Sort the current results by re-querying with ORDER BY
function M.sort_by_column(state)
	local col_idx = state.cursor_col
	local col_name = state.result.columns[col_idx]

	if not col_name then
		return
	end

	-- Toggle sort direction
	local direction = "ASC"
	if state.sort_column == col_idx and state.sort_direction == "ASC" then
		direction = "DESC"
	end

	state.sort_column = col_idx
	state.sort_direction = direction

	-- Get the original query and modify it
	local query = state.result.query
	if not query then
		return
	end

	-- Remove existing ORDER BY if present
	local modified_query = query:gsub("%s+ORDER%s+BY%s+[^;]+", "")
	-- Remove trailing semicolon
	modified_query = modified_query:gsub(";%s*$", "")

	-- Add ORDER BY clause
	modified_query = string.format('%s ORDER BY "%s" %s;', modified_query, col_name, direction)

	-- Re-execute
	local executor = require("neopg.executor")
	executor.execute_query(state.result.connection, modified_query)
end

-- Filter results by re-querying with WHERE LIKE
function M.filter_by_pattern(state)
	vim.ui.input({ prompt = "Filter pattern: " }, function(pattern)
		if not pattern or pattern == "" then
			return
		end

		local query = state.result.query
		if not query then
			return
		end

		-- This is a simplified approach - wrapping the original query in a subquery
		-- Remove trailing semicolon
		local base_query = query:gsub(";%s*$", "")

		-- Get current column name for filtering
		local col_name = state.result.columns[state.cursor_col]

		-- Build filtered query
		local filtered_query = string.format(
			'SELECT * FROM (%s) AS subq WHERE "%s"::text ILIKE \'%%%s%%\';',
			base_query,
			col_name,
			pattern:gsub("'", "''") -- Escape single quotes
		)

		-- Store filter state
		state.filter_pattern = pattern
		state.filter_column = state.cursor_col

		-- Re-execute
		local executor = require("neopg.executor")
		executor.execute_query(state.result.connection, filtered_query)
	end)
end

-- Clear filter and show all results
function M.clear_filter(state)
	if not state.result.query then
		return
	end

	state.filter_pattern = nil
	state.filter_column = nil

	local executor = require("neopg.executor")
	executor.execute_query(state.result.connection, state.result.query)
end

return M

local M = {}

-- State for tracking the source buffer
M.source_bufnr = nil
M.last_query = nil
M.last_connection = nil

-- Get the paragraph under cursor (handles SQL statements)
function M.get_paragraph_query()
	local start_line = vim.fn.line(".")
	local end_line = start_line
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local total_lines = #lines

	-- Check if current line is empty
	if lines[start_line] == "" or lines[start_line]:match("^%s*$") then
		return nil
	end

	-- Find start of SQL statement (go up until empty line, start of file, or previous semicolon)
	while start_line > 1 do
		local prev_line = lines[start_line - 1]
		if prev_line == "" or prev_line:match("^%s*$") then
			break
		end
		if prev_line:match(";%s*$") then
			break
		end
		start_line = start_line - 1
	end

	-- Find end of SQL statement (go down until semicolon or empty line)
	while end_line <= total_lines do
		local current_line = lines[end_line]

		if current_line:match(";%s*$") then
			break
		end

		if end_line < total_lines then
			local next_line = lines[end_line + 1]
			if next_line == "" or next_line:match("^%s*$") then
				break
			end
		end

		end_line = end_line + 1
	end

	-- Extract the query
	local query_lines = {}
	for i = start_line, end_line do
		local line = lines[i]
		-- Skip SQL comments but preserve the structure
		if not line:match("^%s*%-%-") then
			table.insert(query_lines, line)
		end
	end

	local query = table.concat(query_lines, "\n")
	query = query:gsub("^%s+", ""):gsub("%s+$", "")

	-- Add semicolon if missing (but not for meta-commands which don't need them)
	local is_meta = query:match("^\\") ~= nil
	if query ~= "" and not query:match(";%s*$") and not is_meta then
		query = query .. ";"
	end

	if query == "" or query == ";" then
		return nil
	end

	return query
end

-- Get visual selection
function M.get_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_line = start_pos[2]
	local end_line = end_pos[2]

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	if #lines == 0 then
		return nil
	end

	if #lines == 1 then
		local start_col = start_pos[3]
		local end_col = end_pos[3]
		lines[1] = lines[1]:sub(start_col, end_col)
	else
		lines[1] = lines[1]:sub(start_pos[3])
		lines[#lines] = lines[#lines]:sub(1, end_pos[3])
	end

	return table.concat(lines, "\n")
end

-- Check if query is a psql meta-command (starts with \)
local function is_meta_command(query)
	local trimmed = query:gsub("^%s+", "")
	return trimmed:match("^\\") ~= nil
end

-- Check if query is a SELECT query
local function is_select_query(query)
	local trimmed = query:gsub("^%s+", ""):upper()
	return trimmed:match("^SELECT") ~= nil or trimmed:match("^WITH") ~= nil
end

-- Check if query has LIMIT clause
local function has_limit(query)
	local upper_query = query:upper()
	return upper_query:match("%sLIMIT%s") ~= nil or upper_query:match("%sLIMIT$") ~= nil
end

-- Add LIMIT to query if not present
local function add_limit(query, limit)
	if has_limit(query) then
		return query, false
	end

	-- Remove trailing semicolon, add LIMIT, add semicolon back
	local trimmed = query:gsub(";%s*$", "")
	return trimmed .. " LIMIT " .. limit .. ";", true
end

-- Execute meta-command with psql (raw output mode)
local function execute_meta_command(connection, query)
	if not connection then
		vim.notify("No database connection configured", vim.log.levels.ERROR)
		return
	end

	if not query or query == "" then
		return
	end

	-- Store for re-run capability
	M.last_query = query
	M.last_connection = connection
	M.source_bufnr = vim.api.nvim_get_current_buf()

	-- Create temp file for command
	local tmpfile = vim.fn.tempname() .. ".sql"
	local file = io.open(tmpfile, "w")
	if not file then
		vim.notify("Failed to create temp file", vim.log.levels.ERROR)
		return
	end
	file:write(query)
	file:close()

	-- Build psql command WITHOUT format options (use default output for meta-commands)
	local psql_cmd = string.format("psql '%s' -f '%s' --no-psqlrc 2>&1", connection.url, tmpfile)

	-- Record start time
	local start_time = vim.loop.hrtime()

	-- Execute psql
	local handle = io.popen(psql_cmd)
	if not handle then
		vim.notify("Failed to execute psql", vim.log.levels.ERROR)
		os.remove(tmpfile)
		return
	end

	local output = handle:read("*a")
	handle:close()

	-- Calculate execution time
	local end_time = vim.loop.hrtime()
	local execution_time = (end_time - start_time) / 1e9

	-- Clean up temp file
	os.remove(tmpfile)

	-- Check for errors (patterns can appear anywhere in output)
	if output:match("ERROR:") or output:match("psql:.-error") or output:match("FATAL:") then
		local notify = require("neopg.notify")
		notify.error(output, "Query Error")
		return
	end

	-- Render raw output
	local raw_renderer = require("neopg.raw_renderer")
	raw_renderer.render({
		output = output,
		query = query,
		execution_time = execution_time,
		connection = connection,
	})
end

-- Execute query with psql and parse results
function M.execute_query(connection, query, opts)
	opts = opts or {}
	local config = require("neopg.config").get()

	if not connection then
		vim.notify("No database connection configured", vim.log.levels.ERROR)
		return
	end

	if not query or query == "" then
		return
	end

	-- Route meta-commands to raw renderer
	if is_meta_command(query) then
		execute_meta_command(connection, query)
		return
	end

	-- Store for re-run capability
	M.last_query = query
	M.last_connection = connection
	M.source_bufnr = vim.api.nvim_get_current_buf()

	-- Add LIMIT if configured and not present (only for SELECT queries)
	local final_query = query
	local was_limited = false
	if not opts.no_limit and config.default_limit and config.default_limit > 0 and is_select_query(query) then
		final_query, was_limited = add_limit(query, config.default_limit)
	end

	-- Create temp file for query
	local tmpfile = vim.fn.tempname() .. ".sql"
	local file = io.open(tmpfile, "w")
	if not file then
		vim.notify("Failed to create temp file", vim.log.levels.ERROR)
		return
	end
	file:write(final_query)
	file:close()

	-- Build psql command with aligned output format
	local psql_cmd = string.format(
		"psql '%s' -f '%s' --no-psqlrc -P border=2 -P format=aligned 2>&1",
		connection.url,
		tmpfile
	)

	-- Record start time
	local start_time = vim.loop.hrtime()

	-- Execute psql synchronously (we'll make this async later if needed)
	local handle = io.popen(psql_cmd)
	if not handle then
		vim.notify("Failed to execute psql", vim.log.levels.ERROR)
		os.remove(tmpfile)
		return
	end

	local output = handle:read("*a")
	local success, _, exit_code = handle:close()

	-- Calculate execution time
	local end_time = vim.loop.hrtime()
	local execution_time = (end_time - start_time) / 1e9 -- Convert to seconds

	-- Clean up temp file
	os.remove(tmpfile)

	-- Check for errors (patterns can appear anywhere in output)
	if output:match("ERROR:") or output:match("psql:.-error") or output:match("FATAL:") then
		local notify = require("neopg.notify")
		notify.error(output, "Query Error")
		return
	end

	-- For non-select queries, show affected rows
	if not is_select_query(query) then
		local affected = output:match("INSERT %d+ (%d+)")
			or output:match("UPDATE (%d+)")
			or output:match("DELETE (%d+)")
		if affected then
			vim.notify(string.format("%s rows affected (%.3fs)", affected, execution_time), vim.log.levels.INFO)
		else
			vim.notify(string.format("Query executed (%.3fs)", execution_time), vim.log.levels.INFO)
		end
		return
	end

	-- Parse the output
	local parser = require("neopg.parser")
	local result = parser.parse(output)

	if not result or #result.rows == 0 then
		vim.notify("Query returned no results", vim.log.levels.INFO)
		return
	end

	-- Add metadata
	result.execution_time = execution_time
	result.was_limited = was_limited
	result.limit = config.default_limit
	result.query = query
	result.connection = connection

	-- Save to history
	local history = require("neopg.history")
	history.add_entry({
		query = query,
		timestamp = os.time(),
		execution_time = execution_time,
		row_count = #result.rows,
		connection_key = connection.key,
	})


	-- Render results
	local renderer = require("neopg.renderer")
	renderer.render(result)
end

-- Run query from current paragraph
function M.run_paragraph()
	local env_parser = require("neopg.env_parser")
	local config = require("neopg.config")

	local query = M.get_paragraph_query()
	if not query then
		return
	end

	local buffer_dir = vim.fn.expand("%:p:h")
	local connections = env_parser.discover_connections(buffer_dir)
	if #connections == 0 then
		return
	end

	config.get_connection(connections, function(connection)
		if not connection then
			return
		end
		M.execute_query(connection, query)
	end)
end

-- Run visual selection
function M.run_selection()
	local env_parser = require("neopg.env_parser")
	local config = require("neopg.config")

	-- Exit visual mode first to get correct marks
	vim.cmd("normal! ")

	local query = M.get_visual_selection()
	if not query then
		return
	end

	local buffer_dir = vim.fn.expand("%:p:h")
	local connections = env_parser.discover_connections(buffer_dir)
	if #connections == 0 then
		return
	end

	config.get_connection(connections, function(connection)
		if not connection then
			return
		end
		M.execute_query(connection, query)
	end)
end

-- Re-run the last query
function M.rerun_query(opts)
	opts = opts or {}
	if not M.last_query or not M.last_connection then
		return
	end

	M.execute_query(M.last_connection, M.last_query, opts)
end

-- Re-run without limit
function M.rerun_no_limit()
	M.rerun_query({ no_limit = true })
end

-- Get the source buffer
function M.get_source_bufnr()
	return M.source_bufnr
end

return M

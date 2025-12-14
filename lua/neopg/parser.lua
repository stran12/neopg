local M = {}

-- Parse psql bordered output into structured data
-- psql with border=2 produces output like:
-- +----+-------+--------+
-- | id | name  | value  |
-- +----+-------+--------+
-- |  1 | foo   | bar    |
-- |  2 | baz   | qux    |
-- +----+-------+--------+
-- (2 rows)

function M.parse(output)
	local result = {
		columns = {},
		rows = {},
		column_widths = {},
		raw_output = output,
	}

	local lines = {}
	for line in output:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines < 3 then
		return nil
	end

	-- Find the header separator line (first line starting with +)
	local header_start = nil
	local data_start = nil
	local data_end = nil

	for i, line in ipairs(lines) do
		if line:match("^%+%-") then
			if not header_start then
				header_start = i
			elseif not data_start then
				data_start = i + 1
			else
				data_end = i - 1
				break
			end
		end
	end

	if not header_start or not data_start then
		-- Try parsing unaligned output as fallback
		return M.parse_unaligned(output)
	end

	-- Parse header (line after first separator)
	local header_line = lines[header_start + 1]
	if not header_line then
		return nil
	end

	-- Extract column names and their positions
	local col_positions = {}
	local pos = 1
	for segment in header_line:gmatch("|([^|]+)") do
		local col_name = segment:match("^%s*(.-)%s*$") -- trim whitespace
		local start_pos = pos
		local end_pos = pos + #segment
		table.insert(result.columns, col_name)
		table.insert(col_positions, { start = start_pos, length = #segment })
		table.insert(result.column_widths, #segment)
		pos = end_pos + 1
	end

	if #result.columns == 0 then
		return nil
	end

	-- Parse data rows
	if data_end then
		for i = data_start, data_end do
			local line = lines[i]
			if line and line:match("^|") then
				local row = {}
				local col_idx = 1
				for segment in line:gmatch("|([^|]+)") do
					local value = segment:match("^%s*(.-)%s*$") -- trim whitespace
					-- Track actual content width for column sizing
					if result.column_widths[col_idx] and #value > result.column_widths[col_idx] then
						result.column_widths[col_idx] = #value
					end
					table.insert(row, value)
					col_idx = col_idx + 1
				end
				if #row > 0 then
					table.insert(result.rows, row)
				end
			end
		end
	end

	-- Calculate optimal column widths based on content
	for i, col in ipairs(result.columns) do
		result.column_widths[i] = math.max(#col, result.column_widths[i] or 0)
		-- Add padding
		result.column_widths[i] = result.column_widths[i] + 2
	end

	-- Check for max width
	for i, width in ipairs(result.column_widths) do
		result.column_widths[i] = math.min(width, 50) -- Cap at 50 chars
	end

	return result
end

-- Parse unaligned psql output (fallback)
function M.parse_unaligned(output)
	local result = {
		columns = {},
		rows = {},
		column_widths = {},
		raw_output = output,
	}

	local lines = {}
	for line in output:gmatch("[^\r\n]+") do
		-- Skip row count line
		if not line:match("^%(%d+ rows?%)") then
			table.insert(lines, line)
		end
	end

	if #lines < 1 then
		return nil
	end

	-- First line is headers (pipe-separated)
	local header_line = lines[1]
	for col in header_line:gmatch("([^|]+)") do
		local col_name = col:match("^%s*(.-)%s*$")
		table.insert(result.columns, col_name)
		table.insert(result.column_widths, #col_name + 2)
	end

	if #result.columns == 0 then
		return nil
	end

	-- Remaining lines are data
	for i = 2, #lines do
		local line = lines[i]
		local row = {}
		local col_idx = 1
		for value in line:gmatch("([^|]*)") do
			local trimmed = value:match("^%s*(.-)%s*$")
			table.insert(row, trimmed)
			if result.column_widths[col_idx] then
				result.column_widths[col_idx] = math.max(result.column_widths[col_idx], #trimmed + 2)
			end
			col_idx = col_idx + 1
		end
		if #row > 0 then
			table.insert(result.rows, row)
		end
	end

	return result
end

-- Get cell value at position
function M.get_cell(result, row_idx, col_idx)
	if not result or not result.rows then
		return nil
	end
	local row = result.rows[row_idx]
	if not row then
		return nil
	end
	return row[col_idx]
end

-- Get column name
function M.get_column_name(result, col_idx)
	if not result or not result.columns then
		return nil
	end
	return result.columns[col_idx]
end

return M

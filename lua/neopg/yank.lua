local M = {}

local navigator = require("neopg.navigator")

-- Escape a value for CSV (RFC 4180)
local function csv_escape(value)
	if not value then
		return ""
	end

	value = tostring(value)

	-- Check if escaping is needed
	if value:find('[,"\r\n]') then
		-- Double any existing quotes and wrap in quotes
		value = '"' .. value:gsub('"', '""') .. '"'
	end

	return value
end

-- Convert a row to CSV format
local function row_to_csv(row, hidden_columns)
	local values = {}
	for i, value in ipairs(row) do
		if not hidden_columns or not hidden_columns[i] then
			table.insert(values, csv_escape(value))
		end
	end
	return table.concat(values, ",")
end

-- Convert multiple rows to CSV with header
local function rows_to_csv(result, start_row, end_row, hidden_columns, include_header)
	local lines = {}

	-- Add header if requested
	if include_header then
		local header_values = {}
		for i, col in ipairs(result.columns) do
			if not hidden_columns or not hidden_columns[i] then
				table.insert(header_values, csv_escape(col))
			end
		end
		table.insert(lines, table.concat(header_values, ","))
	end

	-- Add data rows
	for row_idx = start_row, end_row do
		local row = result.rows[row_idx]
		if row then
			table.insert(lines, row_to_csv(row, hidden_columns))
		end
	end

	return table.concat(lines, "\n")
end

-- Yank current cell to system clipboard
function M.yank_cell(state)
	local row = state.result.rows[state.cursor_row]
	if not row then
		return
	end

	local value = row[state.cursor_col] or ""

	-- Copy to system clipboard
	vim.fn.setreg("+", value)
	vim.fn.setreg('"', value)
end

-- Yank current row as CSV
function M.yank_row(state)
	local row = state.result.rows[state.cursor_row]
	if not row then
		return
	end

	local csv = row_to_csv(row, state.hidden_columns)

	-- Copy to system clipboard
	vim.fn.setreg("+", csv)
	vim.fn.setreg('"', csv)
end

-- Yank selected rows (visual mode)
function M.yank_selection(state)
	local start_row, end_row = navigator.get_visual_range(state)

	local csv = rows_to_csv(state.result, start_row, end_row, state.hidden_columns, false)

	-- Copy to system clipboard
	vim.fn.setreg("+", csv)
	vim.fn.setreg('"', csv)

	-- Exit visual mode
	navigator.exit_visual_mode(state)
end

-- Export functions used by yank module
M.csv_escape = csv_escape
M.row_to_csv = row_to_csv
M.rows_to_csv = rows_to_csv

return M

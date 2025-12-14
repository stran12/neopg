local M = {}

local yank = require("neopg.yank")

-- Export to CSV file
function M.export_csv(state)
	vim.ui.input({ prompt = "Export CSV to: ", default = "export.csv" }, function(path)
		if not path or path == "" then
			return
		end

		-- Expand path
		path = vim.fn.expand(path)

		-- Generate CSV content with header
		local csv = yank.rows_to_csv(state.result, 1, #state.result.rows, state.hidden_columns, true)

		-- Write to file
		local file = io.open(path, "w")
		if not file then
			vim.notify("Failed to open file: " .. path, vim.log.levels.ERROR)
			return
		end

		file:write(csv)
		file:close()
	end)
end

-- Convert result to JSON
local function result_to_json(result, hidden_columns)
	local rows = {}

	for _, row in ipairs(result.rows) do
		local obj = {}
		for i, col in ipairs(result.columns) do
			if not hidden_columns or not hidden_columns[i] then
				local value = row[i]
				-- Try to convert numeric strings to numbers
				local num = tonumber(value)
				if num and tostring(num) == value then
					obj[col] = num
				elseif value == "" or value:upper() == "NULL" then
					obj[col] = vim.NIL
				elseif value == "true" or value == "t" then
					obj[col] = true
				elseif value == "false" or value == "f" then
					obj[col] = false
				else
					obj[col] = value
				end
			end
		end
		table.insert(rows, obj)
	end

	return vim.fn.json_encode(rows)
end

-- Export to JSON file
function M.export_json(state)
	vim.ui.input({ prompt = "Export JSON to: ", default = "export.json" }, function(path)
		if not path or path == "" then
			return
		end

		path = vim.fn.expand(path)

		local json = result_to_json(state.result, state.hidden_columns)

		local file = io.open(path, "w")
		if not file then
			vim.notify("Failed to open file: " .. path, vim.log.levels.ERROR)
			return
		end

		file:write(json)
		file:close()
	end)
end

-- Escape a value for SQL
local function sql_escape(value)
	if not value or value == "" or value:upper() == "NULL" then
		return "NULL"
	end

	-- Check if it's a number
	local num = tonumber(value)
	if num and tostring(num) == value then
		return value
	end

	-- Check if it's a boolean
	if value == "true" or value == "t" then
		return "TRUE"
	elseif value == "false" or value == "f" then
		return "FALSE"
	end

	-- Escape single quotes by doubling them
	return "'" .. value:gsub("'", "''") .. "'"
end

-- Convert result to SQL INSERT statements
local function result_to_sql(result, table_name, hidden_columns)
	local statements = {}

	-- Get visible columns
	local visible_cols = {}
	for i, col in ipairs(result.columns) do
		if not hidden_columns or not hidden_columns[i] then
			table.insert(visible_cols, '"' .. col .. '"')
		end
	end

	local columns_str = table.concat(visible_cols, ", ")

	for _, row in ipairs(result.rows) do
		local values = {}
		for i, value in ipairs(row) do
			if not hidden_columns or not hidden_columns[i] then
				table.insert(values, sql_escape(value))
			end
		end

		local values_str = table.concat(values, ", ")
		local stmt = string.format("INSERT INTO %s (%s) VALUES (%s);", table_name, columns_str, values_str)
		table.insert(statements, stmt)
	end

	return table.concat(statements, "\n")
end

-- Export to SQL INSERT statements
function M.export_sql(state)
	-- First ask for table name
	vim.ui.input({ prompt = "Table name: ", default = "table_name" }, function(table_name)
		if not table_name or table_name == "" then
			return
		end

		-- Then ask for file path
		vim.ui.input({ prompt = "Export SQL to: ", default = "export.sql" }, function(path)
			if not path or path == "" then
				return
			end

			path = vim.fn.expand(path)

			local sql = result_to_sql(state.result, table_name, state.hidden_columns)

			local file = io.open(path, "w")
			if not file then
				vim.notify("Failed to open file: " .. path, vim.log.levels.ERROR)
				return
			end

			file:write(sql)
			file:close()
		end)
	end)
end

return M

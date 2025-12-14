local M = {}

-- Parse a single .env file and extract DATABASE_URLs
function M.parse_env_file(filepath)
	local connections = {}
	local file = io.open(filepath, "r")
	if not file then
		return connections
	end

	for line in file:lines() do
		-- Skip comments and empty lines
		if not line:match("^#") and line:match("%S") then
			-- Look for DATABASE_URL or any variable containing DATABASE_URL
			local key, value = line:match("^([%w_]*DATABASE_URL[%w_]*)%s*=%s*(.+)$")
			if key and value then
				-- Remove quotes if present
				value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
				-- Only add PostgreSQL URLs
				if value:match("^postgres") or value:match("^postgresql") then
					table.insert(connections, {
						key = key,
						url = value,
						file = filepath,
					})
				end
			end
		end
	end

	file:close()
	return connections
end

-- Recursively search for .env files in parent directories
function M.find_env_files(start_dir)
	local env_files = {}
	local current_dir = start_dir or vim.fn.expand("%:p:h")

	-- If no buffer is loaded, fallback to cwd
	if current_dir == "" then
		current_dir = vim.fn.getcwd()
	end

	while current_dir ~= "/" and current_dir ~= "" do
		-- Stop at project root (where .git exists)
		if vim.fn.isdirectory(current_dir .. "/.git") == 1 then
			-- Check for .env files in the project root
			local patterns = { ".env", ".env.local", ".env.development", ".env.production", ".env.staging" }

			for _, pattern in ipairs(patterns) do
				local filepath = current_dir .. "/" .. pattern
				if vim.fn.filereadable(filepath) == 1 then
					table.insert(env_files, filepath)
				end
			end
			break
		end

		-- Check for various .env file patterns
		local patterns = { ".env", ".env.local", ".env.development", ".env.production", ".env.staging" }

		for _, pattern in ipairs(patterns) do
			local filepath = current_dir .. "/" .. pattern
			if vim.fn.filereadable(filepath) == 1 then
				table.insert(env_files, filepath)
			end
		end

		-- Move to parent directory
		current_dir = vim.fn.fnamemodify(current_dir, ":h")
	end

	return env_files
end

-- Discover all DATABASE_URLs from .env files
function M.discover_connections(start_dir)
	local all_connections = {}
	local env_files = M.find_env_files(start_dir)

	for _, filepath in ipairs(env_files) do
		local connections = M.parse_env_file(filepath)
		for _, conn in ipairs(connections) do
			table.insert(all_connections, conn)
		end
	end

	-- Error if no connections found
	if #all_connections == 0 then
		vim.notify("No .env file(s) found with PostgreSQL DATABASE_URL variables", vim.log.levels.ERROR)
	end

	return all_connections
end

return M

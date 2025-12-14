local M = {}

-- Get history file path for current project
local function get_history_path()
	local config = require("neopg.config")
	local project_root = config.get_project_root()
	local opts = config.get()
	return project_root .. "/" .. opts.history_file
end

-- Load history from file
local function load_history()
	local path = get_history_path()
	local file = io.open(path, "r")
	if not file then
		return {}
	end

	local content = file:read("*a")
	file:close()

	if not content or content == "" then
		return {}
	end

	local ok, history = pcall(vim.fn.json_decode, content)
	if not ok or type(history) ~= "table" then
		return {}
	end

	return history
end

-- Save history to file
local function save_history(history)
	local path = get_history_path()
	local file = io.open(path, "w")
	if not file then
		return
	end

	local ok, json = pcall(vim.fn.json_encode, history)
	if ok then
		file:write(json)
	end
	file:close()
end

-- Add an entry to history
function M.add_entry(entry)
	local config = require("neopg.config").get()
	local history = load_history()

	-- Add new entry at the beginning
	table.insert(history, 1, entry)

	-- Trim to limit
	while #history > config.history_limit do
		table.remove(history)
	end

	save_history(history)
end

-- Get all history entries
function M.get_entries()
	return load_history()
end

-- Format timestamp for display
local function format_timestamp(timestamp)
	return os.date("%Y-%m-%d %H:%M", timestamp)
end

-- Format query for display (truncate if needed)
local function format_query(query, max_len)
	max_len = max_len or 60
	local single_line = query:gsub("\n", " "):gsub("%s+", " ")
	if #single_line > max_len then
		return single_line:sub(1, max_len - 3) .. "..."
	end
	return single_line
end

-- Show history picker using telescope or vim.ui.select
function M.show_picker()
	local history = load_history()

	if #history == 0 then
		return
	end

	-- Try to use telescope if available
	local has_telescope, telescope = pcall(require, "telescope")
	if has_telescope then
		M.show_telescope_picker(history)
	else
		M.show_select_picker(history)
	end
end

-- Telescope picker
function M.show_telescope_picker(history)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	pickers
		.new({}, {
			prompt_title = "Query History",
			finder = finders.new_table({
				results = history,
				entry_maker = function(entry)
					local display = string.format(
						"%s | %d rows | %.3fs | %s",
						format_timestamp(entry.timestamp),
						entry.row_count or 0,
						entry.execution_time or 0,
						format_query(entry.query, 40)
					)
					return {
						value = entry,
						display = display,
						ordinal = entry.query,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Query",
				define_preview = function(self, entry, status)
					local query = entry.value.query
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(query, "\n"))
					vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "sql")
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						M.execute_history_entry(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Fallback vim.ui.select picker
function M.show_select_picker(history)
	local choices = {}
	for i, entry in ipairs(history) do
		local display = string.format(
			"%d. %s | %d rows | %s",
			i,
			format_timestamp(entry.timestamp),
			entry.row_count or 0,
			format_query(entry.query, 50)
		)
		table.insert(choices, display)
	end

	vim.ui.select(choices, {
		prompt = "Select query to re-run:",
	}, function(choice, idx)
		if not choice then
			return
		end

		local entry = history[idx]
		if entry then
			M.execute_history_entry(entry)
		end
	end)
end

-- Execute a history entry
function M.execute_history_entry(entry)
	local executor = require("neopg.executor")
	local env_parser = require("neopg.env_parser")
	local config = require("neopg.config")

	-- Get connections
	local buffer_dir = vim.fn.expand("%:p:h")
	local connections = env_parser.discover_connections(buffer_dir)

	if #connections == 0 then
		return
	end

	-- Try to find the same connection that was used
	local target_conn = nil
	if entry.connection_key then
		for _, conn in ipairs(connections) do
			if conn.key == entry.connection_key then
				target_conn = conn
				break
			end
		end
	end

	if target_conn then
		executor.execute_query(target_conn, entry.query)
	else
		-- Fall back to connection selection
		config.get_connection(connections, function(connection)
			if connection then
				executor.execute_query(connection, entry.query)
			end
		end)
	end
end

-- Clear history
function M.clear()
	save_history({})
end

return M

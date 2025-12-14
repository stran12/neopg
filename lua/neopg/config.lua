local M = {}

-- Default configuration
M.defaults = {
	-- Navigation
	column_skip_count = 3, -- Columns to skip with 'w'/'b'
	row_skip_count = 5, -- Rows to skip with 'gj'/'gk'

	-- Results
	default_limit = 1000, -- Auto-LIMIT for queries
	warn_on_truncation = true, -- Show warning when results truncated

	-- Display
	highlight_cell = true, -- Highlight current cell
	sticky_header = true, -- Keep header visible
	show_statusline = true, -- Show position/timing in statusline
	pinned_columns = 1, -- Number of columns to pin on the left (like pspg)

	-- History
	history_limit = 100, -- Max queries to store per project
	history_file = ".neopg_history", -- History file name

	-- Keymaps in pager buffer
	keymaps = {
		quit = "q",
		quit_alt = "<Esc><Esc>",
		yank_cell = "y",
		yank_row = "yy",
		yank_row_alt = "Y",
		pipe_cell = "|",
		pipe_cell_interactive = "\\",
		export_csv = "<leader>ec",
		export_json = "<leader>ej",
		export_sql = "<leader>es",
		expand_column = ">",
		shrink_column = "<",
		reset_columns = "=",
		rerun_query = "r",
		rerun_no_limit = "R",
		show_help = "?",
		history = "<leader>h",
		-- Navigation
		move_left = "h",
		move_right = "l",
		move_up = "k",
		move_down = "j",
		skip_cols_right = "w",
		skip_cols_left = "b",
		first_col = "^",
		first_col_alt = "0",
		last_col = "$",
		first_row = "gg",
		last_row = "G",
		top_visible = "H",
		middle_visible = "M",
		bottom_visible = "L",
		skip_rows_down = "gj",
		skip_rows_up = "gk",
		half_page_down = "<C-d>",
		half_page_up = "<C-u>",
		page_down = "<C-f>",
		page_up = "<C-b>",
		-- Search
		search = "/",
		search_next = "n",
		search_prev = "N",
		search_current_cell = "*",
		clear_search = "<Esc>",
		-- Column visibility
		toggle_column_info = "zi",
		hide_column = "zc",
		show_all_columns = "zo",
		-- Pinned columns
		pin_column = "zp",
		unpin_column = "zu",
	},

	-- Keymaps from SQL file
	sql_keymaps = {
		run_paragraph = "<leader>rr",
		run_selection = "<leader>rs",
		reset_connection = "<leader>rc",
	},
}

-- Active configuration (merged with user options)
M.options = {}

-- Initialize global session storage
if vim.g.neopg_connections == nil then
	vim.g.neopg_connections = {}
end

-- Get the project root (where .git is located)
function M.get_project_root()
	local current_dir = vim.fn.getcwd()

	while current_dir ~= "/" and current_dir ~= "" do
		if vim.fn.isdirectory(current_dir .. "/.git") == 1 then
			return current_dir
		end
		current_dir = vim.fn.fnamemodify(current_dir, ":h")
	end

	return vim.fn.getcwd()
end

-- Get session config for current project
function M.get_session_config()
	local project_root = M.get_project_root()
	local connections = vim.g.neopg_connections or {}

	if connections[project_root] then
		return connections[project_root]
	end

	return nil
end

-- Save connection to session storage
function M.save_session_config(connection)
	local project_root = M.get_project_root()
	local connections = vim.g.neopg_connections or {}

	connections[project_root] = {
		connection = connection,
	}

	vim.g.neopg_connections = connections
	return true
end

-- Get or prompt for connection (async with callback)
function M.get_connection(connections, callback)
	local config = M.get_session_config()
	if config and config.connection then
		-- Validate that the connection still exists
		for _, conn in ipairs(connections) do
			if conn.key == config.connection.key and conn.url == config.connection.url then
				if callback then
					callback(config.connection)
				end
				return
			end
		end
	end

	if #connections == 0 then
		if callback then
			callback(nil)
		end
		return
	end

	if #connections == 1 then
		local conn = connections[1]
		M.save_session_config(conn)
		if callback then
			callback(conn)
		end
		return
	end

	-- Multiple connections, let user choose
	local choices = {}
	for i, conn in ipairs(connections) do
		table.insert(choices, string.format("%d. %s (%s)", i, conn.key, vim.fn.fnamemodify(conn.file, ":~:.")))
	end

	vim.ui.select(choices, {
		prompt = "Select database connection:",
	}, function(choice, idx)
		if not choice then
			if callback then
				callback(nil)
			end
			return
		end

		local selected = connections[idx]
		M.save_session_config(selected)
		if callback then
			callback(selected)
		end
	end)
end

-- Clear saved config
function M.clear_config()
	local project_root = M.get_project_root()
	local connections = vim.g.neopg_connections or {}

	if connections[project_root] then
		connections[project_root] = nil
		vim.g.neopg_connections = connections
	end
end

-- Setup configuration
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

-- Get current options
function M.get()
	if vim.tbl_isempty(M.options) then
		return M.defaults
	end
	return M.options
end

return M

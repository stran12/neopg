# NeoPG

A pure Neovim plugin for querying PostgreSQL databases with vim-style cell navigation.

## Overview

NeoPG executes SQL queries from within Neovim and displays results in a navigable grid buffer. Unlike traditional pagers, NeoPG provides cell-by-cell navigation using familiar vim keybindings, with features like search, yank, export, and query history.

**Key Features:**
- Cell-based navigation with vim motions
- Sticky header row
- Search visible cells with `/`
- Yank cells/rows as CSV to clipboard
- Pipe cell values to external programs (jq, bat, etc.)
- Export to CSV, JSON, or SQL INSERT
- Query history with telescope integration
- Sort/filter via database re-query
- Auto-LIMIT with configurable threshold
- Meta-command support (`\dt`, `\d tablename`, etc.)

## Requirements

- Neovim 0.9+
- `psql` (PostgreSQL client) in PATH
- Optional: telescope.nvim (for history picker)

## Installation

### lazy.nvim

```lua
{
  "stran/neopg",
  ft = { "sql", "pgsql" },
  config = function()
    require("neopg").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "stran/neopg",
  config = function()
    require("neopg").setup()
  end,
}
```

### Manual

Clone to your Neovim packages directory:

```bash
git clone https://github.com/stran/neopg ~/.local/share/nvim/site/pack/plugins/start/neopg
```

## Configuration

```lua
require("neopg").setup({
  -- Navigation
  column_skip_count = 3,        -- Columns to skip with 'w'/'b'
  row_skip_count = 5,           -- Rows to skip with 'gj'/'gk'

  -- Results
  default_limit = 1000,         -- Auto-LIMIT for queries (0 to disable)
  warn_on_truncation = true,    -- Show warning when results truncated

  -- Display
  highlight_cell = true,        -- Highlight current cell
  sticky_header = true,         -- Keep header visible
  show_statusline = true,       -- Show position/timing statusline
  pinned_columns = 1,           -- Columns to pin on the left (like pspg)

  -- History
  history_limit = 100,          -- Max queries per project
  history_file = ".neopg_history",

  -- Keymaps (customize any)
  keymaps = {
    yank_cell = "y",
    yank_row = "yy",
    export_csv = "<leader>ec",
    export_json = "<leader>ej",
    export_sql = "<leader>es",
    -- ... see full list in appendix
  },

  -- SQL file keymaps
  sql_keymaps = {
    run_paragraph = "<leader>rr",
    run_selection = "<leader>rs",
    reset_connection = "<leader>rc",
  },
})
```

## Usage

### Database Connection

NeoPG reads database credentials from `.env` files in your project. It searches for variables matching `*DATABASE_URL*`:

```bash
# .env
DATABASE_URL=postgresql://user:pass@localhost:5432/mydb
SHADOW_DATABASE_URL=postgresql://user:pass@localhost:5432/shadow
```

### Running Queries

1. Open a `.sql` file
2. Write your query
3. Press `<leader>rr` to execute the paragraph under cursor

```sql
-- Place cursor here and press <leader>rr
SELECT id, name, email
FROM users
WHERE created_at > '2024-01-01';
```

Or select SQL visually and press `<leader>rs`.

### Meta-Commands

NeoPG supports psql meta-commands like `\dt`, `\d tablename`, `\l`, etc. These are automatically detected and displayed in a raw text viewer:

```sql
-- List all tables
\dt

-- Describe a specific table
\d users

-- List databases
\l
```

Meta-commands open in a scrollable buffer with these keybindings:
- `q` — close viewer
- `r` — re-run command
- `?` — show help
- Standard vim navigation (`j`, `k`, `gg`, `G`, `Ctrl-d`, `Ctrl-u`)

### Navigating Results

Results open in a new buffer with a grid display:

```
| id | name    | email              |
+----+---------+--------------------+
|  1 | Alice   | alice@example.com  |
|  2 | Bob     | bob@example.com    |
|  3 | Charlie | charlie@example.com|

Row 1 of 3 | Col 1 of 3 | (0.042s)
```

Use your normal buffer navigation to switch between query and results:
- `]b`/`[b` — switch between buffers
- `<leader>bd` — close results buffer (or your buffer delete mapping)

Navigate cell-by-cell:
- `h/j/k/l` — move one cell
- `w/b` — skip 3 columns
- `^/$` — first/last column
- `gg/G` — first/last row

### Search

Press `/` to search visible cells:

```
/alice<Enter>
```

Use `n`/`N` to jump between matches. Press `*` to search for the current cell's value.

### Yank to Clipboard

- `y` — yank current cell value
- `yy` — yank entire row as CSV
- `V` + select rows + `y` — yank multiple rows as CSV

### Pipe to External Program

Pipe the current cell's value to an external command:

- `|` — Non-interactive mode (output in floating window)
- `\` — Interactive mode (full terminal control)

**Non-interactive** (`|`) is for commands like `jq .` that transform data:

1. Navigate to a cell (e.g., a JSONB column)
2. Press `|`
3. Enter a command (e.g., `jq .`, `bat -l json`)
4. View formatted output in a floating window
5. Press `q`, `Esc`, or `|` to close

**Interactive** (`\`) is for programs like `jless` that need terminal control:

1. Navigate to a cell
2. Press `\`
3. Enter a command (e.g., `jless`, `less`, `vim -`)
4. Use the program in a fullscreen terminal tab
5. Exit the program to auto-close and return to results

### Export

- `<leader>ec` — export all results to CSV file
- `<leader>ej` — export as JSON
- `<leader>es` — export as SQL INSERT statements

### Sort and Filter

From the results buffer:

```vim
:Sort          " Sort by current column (toggles ASC/DESC)
:Filter alice  " Filter rows where current column contains 'alice'
:ClearFilter   " Remove filter
```

### Query History

Press `<leader>h` to open the query history picker. Select a previous query to re-run it.

## Commands

| Command | Description |
|---------|-------------|
| `:NeopgRunParagraph` | Run SQL paragraph under cursor |
| `:NeopgRunSelection` | Run selected SQL |
| `:NeopgResetConnection` | Clear saved connection |
| `:NeopgHistory` | Show query history |
| `:NeopgClearHistory` | Clear query history |

Buffer-local (in results pager):

| Command | Description |
|---------|-------------|
| `:Sort` | Sort by current column |
| `:Filter {pattern}` | Filter by pattern |
| `:ClearFilter` | Clear filter |

## Appendix

### Keymap Reference

#### SQL File Keymaps

| Key | Action | Config Key |
|-----|--------|------------|
| `<leader>rr` | Run paragraph | `sql_keymaps.run_paragraph` |
| `<leader>rs` | Run selection | `sql_keymaps.run_selection` |
| `<leader>rc` | Reset connection | `sql_keymaps.reset_connection` |

#### Pager Navigation

| Key | Action | Config Key |
|-----|--------|------------|
| `h` | Move left | `keymaps.move_left` |
| `l` | Move right | `keymaps.move_right` |
| `j` | Move down | `keymaps.move_down` |
| `k` | Move up | `keymaps.move_up` |
| `w` | Skip columns right | `keymaps.skip_cols_right` |
| `b` | Skip columns left | `keymaps.skip_cols_left` |
| `^` | First column | `keymaps.first_col` |
| `0` | First column (alt) | `keymaps.first_col_alt` |
| `$` | Last column | `keymaps.last_col` |
| `gg` | First row | `keymaps.first_row` |
| `G` | Last row | `keymaps.last_row` |
| `H` | Top visible row | `keymaps.top_visible` |
| `M` | Middle visible row | `keymaps.middle_visible` |
| `L` | Bottom visible row | `keymaps.bottom_visible` |
| `gj` | Skip rows down | `keymaps.skip_rows_down` |
| `gk` | Skip rows up | `keymaps.skip_rows_up` |
| `<C-d>` | Half page down | `keymaps.half_page_down` |
| `<C-u>` | Half page up | `keymaps.half_page_up` |
| `<C-f>` | Page down | `keymaps.page_down` |
| `<C-b>` | Page up | `keymaps.page_up` |

#### Search

| Key | Action | Config Key |
|-----|--------|------------|
| `/` | Start search | `keymaps.search` |
| `n` | Next match | `keymaps.search_next` |
| `N` | Previous match | `keymaps.search_prev` |
| `*` | Search current cell | `keymaps.search_current_cell` |
| `<Esc>` | Clear search | `keymaps.clear_search` |

#### Yank

| Key | Action | Config Key |
|-----|--------|------------|
| `y` | Yank cell | `keymaps.yank_cell` |
| `yy` | Yank row as CSV | `keymaps.yank_row` |
| `Y` | Yank row as CSV | `keymaps.yank_row_alt` |
| `V` + `y` | Yank selected rows | (visual mode) |

#### Pipe

| Key | Action | Config Key |
|-----|--------|------------|
| `\|` | Pipe cell (floating window) | `keymaps.pipe_cell` |
| `\\` | Pipe cell (interactive) | `keymaps.pipe_cell_interactive` |

#### Export

| Key | Action | Config Key |
|-----|--------|------------|
| `<leader>ec` | Export CSV | `keymaps.export_csv` |
| `<leader>ej` | Export JSON | `keymaps.export_json` |
| `<leader>es` | Export SQL | `keymaps.export_sql` |

#### Column Management

| Key | Action | Config Key |
|-----|--------|------------|
| `>` | Expand column | `keymaps.expand_column` |
| `<` | Shrink column | `keymaps.shrink_column` |
| `=` | Reset widths | `keymaps.reset_columns` |
| `zc` | Hide column | `keymaps.hide_column` |
| `zo` | Show all columns | `keymaps.show_all_columns` |
| `zi` | Column info | `keymaps.toggle_column_info` |
| `zp` | Pin columns up to cursor | `keymaps.pin_column` |
| `zu` | Unpin all columns | `keymaps.unpin_column` |

#### Other

| Key | Action | Config Key |
|-----|--------|------------|
| `r` | Re-run query | `keymaps.rerun_query` |
| `R` | Re-run without LIMIT | `keymaps.rerun_no_limit` |
| `?` | Show help | `keymaps.show_help` |
| `<leader>h` | Query history | `keymaps.history` |

### Module Reference

| Module | Description |
|--------|-------------|
| `neopg` | Main entry point, `setup()` |
| `neopg.config` | Configuration and connection management |
| `neopg.env_parser` | Parse `.env` files for DATABASE_URL |
| `neopg.executor` | Execute queries via psql |
| `neopg.parser` | Parse psql output to structured data |
| `neopg.renderer` | Render results grid in buffer |
| `neopg.raw_renderer` | Render raw meta-command output |
| `neopg.navigator` | Cell navigation and scrolling |
| `neopg.search` | Search functionality |
| `neopg.yank` | Clipboard operations |
| `neopg.pipe` | Pipe cell values to external programs |
| `neopg.export` | Export to CSV/JSON/SQL |
| `neopg.history` | Query history management |
| `neopg.sort_filter` | Sort and filter operations |

### Lua API

```lua
local neopg = require("neopg")

-- Setup with options
neopg.setup(opts)

-- Access submodules
local executor = require("neopg.executor")
executor.run_paragraph()      -- Run SQL under cursor
executor.run_selection()      -- Run visual selection
executor.rerun_query()        -- Re-run last query
executor.rerun_no_limit()     -- Re-run without LIMIT

local history = require("neopg.history")
history.show_picker()         -- Open history picker
history.get_entries()         -- Get all history entries
history.clear()               -- Clear history

local config = require("neopg.config")
config.clear_config()         -- Reset saved connection
config.get()                  -- Get current options
```

## License

MIT

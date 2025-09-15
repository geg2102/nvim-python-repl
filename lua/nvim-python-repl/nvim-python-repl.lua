local api = vim.api

M = {}

M.term = {
    opened = 0,
    winid = nil,
    bufid = nil,
    chanid = nil,
}

-- HELPERS
local visual_selection_range = function()
    local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))
    if start_row < end_row or (start_row == end_row and start_col <= end_col) then
        return start_row - 1, start_col - 1, end_row - 1, end_col
    else
        return end_row - 1, end_col - 1, start_row - 1, start_col
    end
end

local get_statement_definition = function(filetype)
    local node = vim.treesitter.get_node()
    if (node:named() == false) then
        error("Node not recognized. Check to ensure treesitter parser is installed.")
    end
    if filetype == "python" or filetype == "scala" then
        while (
                string.match(node:sexpr(), "import") == nil and
                string.match(node:sexpr(), "statement") == nil and
                string.match(node:sexpr(), "definition") == nil and
                string.match(node:sexpr(), "call_expression") == nil) do
            node = node:parent()
        end
    elseif filetype == "lua" then
        while (
                string.match(node:sexpr(), "for_statement") == nil and
                string.match(node:sexpr(), "if_statement") == nil and
                string.match(node:sexpr(), "while_statement") == nil and
                string.match(node:sexpr(), "assignment_statement") == nil and
                string.match(node:sexpr(), "function_definition") == nil and
                string.match(node:sexpr(), "function_call") == nil and
                string.match(node:sexpr(), "local_declaration") == nil
            ) do
            node = node:parent()
        end
    end
    return node
end

local create_win = function(config, bufid, orig_win)
    local split_dir = 'left'
    if config.split_dir then
        split_dir = config.split_dir
    end
    if config.vsplit then
        split_dir = 'above'
    end
    local win = vim.api.nvim_open_win(bufid, true, {
        split = split_dir,
        win = orig_win
    })
    return win
end

local term_open = function(filetype, config)
    local orig_win = vim.api.nvim_get_current_win()
    if M.term.chanid ~= nil then return end
    local buf = vim.api.nvim_create_buf(true, true)

    local win = create_win(config, buf, orig_win)

    local choice = ''
    if config.prompt_spawn then
        choice = vim.fn.input("REPL spawn command: ")
    else
        if filetype == 'scala' then
            choice = config.spawn_command.scala
        elseif filetype == 'python' then
            choice = config.spawn_command.python
        elseif filetype == 'lua' then
            choice = config.spawn_command.lua
        elseif filetype == 'bash' or filetype == 'sh' then
            choice = config.spawn_command.bash
        else
            choice = vim.fn.input("REPL spawn command: ")
        end
    end
    local chan = vim.fn.termopen(choice, {
        on_exit = function()
            M.term.chanid = nil
            M.term.opened = 0
            M.term.winid = nil
            M.term.bufid = nil
        end
    })
    M.term.chanid = chan
    vim.bo.filetype = 'term'

    -- Block until terminal is ready
    local timeout = 5000 -- 5 seconds timeout
    local interval = 100 -- Check every 100ms
    local success = vim.wait(timeout, function()
        -- Check if terminal buffer has content
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return #lines > 0 and lines[1] ~= ""
    end, interval)

    if not success then
        vim.notify("Terminal initialization timed out", vim.log.levels.WARN)
    end

    -- Additional wait for safety
    vim.wait(20)

    M.term.opened = 1
    M.term.winid = win
    M.term.bufid = buf
    -- Return to original window
    api.nvim_set_current_win(orig_win)
end

local function utf8_safe_sub(line, start_char, end_char)
    local total_chars = vim.fn.strchars(line)
    -- If end_char is past the end, clamp it
    if end_char > total_chars then
        end_char = total_chars
    end
    return vim.fn.strcharpart(line, start_char, end_char - start_char)
end

local function sanitize_utf8_lines(lines)
    local sanitized = {}
    for _, line in ipairs(lines) do
        -- Remove invalid UTF-8 characters (including lone surrogates)
        -- This regex removes any byte sequence that can't be interpreted as valid UTF-8
        -- It replaces them with an empty string
        local ok, clean_line = pcall(vim.fn.strtrans, line)
        if not ok then
            clean_line = "" -- fallback if strtrans fails
        end
        table.insert(sanitized, clean_line)
    end
    return sanitized
end

local function get_minimum_indentation(lines)
    local min_indent = nil
    for _, line in ipairs(lines) do
        local indent = line:match("^(%s*)%S")
        if indent then
            local indent_len = vim.fn.strchars(indent)
            if min_indent == nil or indent_len < min_indent then
                min_indent = indent_len
            end
        end
    end
    return min_indent or 0
end

local function dedent_lines(lines, indent_chars)
    local dedented = {}
    for _, line in ipairs(lines) do
        if line:match("^%s*$") then
            table.insert(dedented, "")
        else
            local total_chars = vim.fn.strchars(line)
            local dedented_line = vim.fn.strcharpart(line, indent_chars, total_chars - indent_chars)
            table.insert(dedented, dedented_line)
        end
    end
    return dedented
end

-- CONSTRUCTING MESSAGE
local construct_message_from_selection = function(start_row, start_col, end_row, end_col)
    local bufnr = api.nvim_get_current_buf()
    if start_row ~= end_row then
        local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
        lines[1] = utf8_safe_sub(lines[1], start_col, vim.fn.strchars(lines[1]))
        -- Only truncate the final line if the selection ends before the end of the line
        if #lines == end_row - start_row + 1 then
            lines[#lines] = utf8_safe_sub(lines[#lines], 0, end_col)
        end
        return lines
    else
        local line = api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
        return line and { utf8_safe_sub(line, start_col, end_col) } or {}
    end
end

local construct_message_from_buffer = function()
    local bufnr = api.nvim_get_current_buf()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    lines = sanitize_utf8_lines(lines)
    return lines
end

local construct_message_from_node = function(filetype)
    local node = get_statement_definition(filetype)
    local bufnr = api.nvim_get_current_buf()
    local start_row, _, end_row, _ = node:range()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)

    -- Handle Python indentation issues
    if filetype == "python" then
        if vim.fn.has('win32') == 1 then
            return table.concat(lines, api.nvim_replace_termcodes("<C-m>", true, false, true))
        else
            local min_indent = get_minimum_indentation(lines)
            local dedented = dedent_lines(lines, min_indent)
            return table.concat(dedented, "\n")
        end
    else
        return vim.treesitter.get_node_text(node, bufnr)
    end
end

local function get_current_markdown_codeblock()
    local bufnr = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(0)) -- 0-indexed
    cursor_row = cursor_row + 1                                -- Convert to 1-indexed

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Pattern for code fence: ^\s*````\s*(\w+)? -> matches ``` or ```python
    local fence_pattern = "^%s*```%s*()"

    -- Step 1: Scan upward to find the opening fence
    local start_line = nil
    local end_line = nil
    local language = "plaintext"

    -- Go up from cursor to find the start fence
    for i = cursor_row - 1, 1, -1 do
        if i <= line_count and lines[i - 1]:match(fence_pattern) then
            language = lines[i - 1]:match("^%s*```%s*(%w+)") or "plaintext"
            start_line = i
            break
        end
        if i == 1 or lines[i - 1]:match("^%s*```") then
            -- Hit another fence or start — not in a valid block
            return nil
        end
    end

    if not start_line then return nil end -- No opening fence found

    -- Step 2: Scan downward to find the closing fence
    for i = start_line + 1, line_count do
        if lines[i - 1]:match("^%s*```%s*$") then
            end_line = i - 1 -- Exclude closing fence
            break
        end
    end

    if not end_line then end_line = line_count end -- In case no closing fence

    -- Step 3: Extract content between fences
    local content_lines = {}
    for i = start_line, end_line - 1 do
        table.insert(content_lines, lines[i])
    end

    local content = table.concat(content_lines, "\n")

    return {
        language = language,
        content = content,
        range = { start_line - 1, end_line } -- 0-indexed for API use
    }
end

-- local construct_message_from_node = function(filetype)
--     local node = get_statement_definition(filetype)
--     local bufnr = api.nvim_get_current_buf()
--     local message = vim.treesitter.get_node_text(node, bufnr)
--     if filetype == "python" then
--         -- For Python, we need to preserve the original indentation
--         local start_row, start_column, end_row, _ = node:range()
--         if vim.fn.has('win32') == 1 then
--             local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
--             message = table.concat(lines, api.nvim_replace_termcodes("<C-m>", true, false, true))
--         end
--         -- For Linux, remove superfluous indentation so nested code is not indented
--         while start_column ~= 0 do
--             -- For empty blank lines
--             message = string.gsub(message, "\n\n+", "\n")
--             -- For nested indents in classes/functions
--             message = string.gsub(message, "\n%s%s%s%s", "\n")
--             start_column = start_column - 4
--         end
--         -- end
--     end
--     return message
-- end

local send_message = function(filetype, message, config)
    if M.term.opened == 0 then
        term_open(filetype, config)
    end
    local line_count = vim.api.nvim_buf_line_count(M.term.bufid)
    vim.api.nvim_win_set_cursor(M.term.winid, { line_count, 0 })
    vim.wait(50)
    local esc = "\27"
    if filetype == "python" or filetype == "lua" then
        -- if vim.fn.has('win32') == 1 then
        --     message = message .. "\r\n"
        -- else
        message = esc .. "[200~" .. message .. esc .. "[201~"
        -- --
        -- message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<esc>[201~", true, false, true)
        -- end
        api.nvim_chan_send(M.term.chanid, message)
    elseif filetype == "scala" then
        if config.spawn_command.scala == "sbt console" then
            -- Use :paste mode with explicit newlines
            message = ":paste\n" .. message .. "\n" .. string.char(4) -- Ctrl-D (End of Transmission)
        else
            -- Wrap in curly braces with literal newlines
            message = "{\n" .. message .. "\n}"
        end
        api.nvim_chan_send(M.term.chanid, message)
    elseif filetype == "bash" or filetype == "sh" then
        api.nvim_chan_send(M.term.chanid, message)
    else
        -- for unknown interpreters, just send the code. may work, may not
        api.nvim_chan_send(M.term.chanid, message)
    end
    if config.execute_on_send then
        vim.wait(20)
        api.nvim_chan_send(M.term.chanid, "\r\r")
    end
end

-- Function to identify cell boundaries
local get_current_cell_range = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local start_row = 0
    local end_row = #lines - 1

    for i = cursor_row, 0, -1 do
        if string.match(lines[i + 1], "^# %%%%") then
            start_row = i + 1
            break
        end
    end

    for i = cursor_row + 1, #lines - 1 do
        if string.match(lines[i + 1], "^# %%%%") then
            end_row = i - 1
            break
        end
    end

    return start_row, end_row
end

-- Function to extract cell content
local construct_message_from_cell = function()
    local start_row, end_row = get_current_cell_range()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    return lines
end

-- Function to send current cell to REPL
M.send_current_cell_to_repl = function(config)
    local filetype = vim.bo.filetype
    local message_lines = construct_message_from_cell()
    local message = table.concat(message_lines, "\n")
    send_message(filetype, message, config)
end

M.send_statement_definition = function(config)
    local filetype = vim.bo.filetype
    local message = construct_message_from_node(filetype)
    send_message(filetype, message, config)
end

M.send_visual_to_repl = function(config)
    local filetype = vim.bo.filetype
    local start_row, start_col, end_row, end_col = visual_selection_range()
    local message = construct_message_from_selection(start_row, start_col, end_row, end_col)
    local concat_message = ""
    if vim.fn.has('win32') == 1 then
        concat_message = table.concat(message, "<C-m>")
    else
        concat_message = table.concat(message, "\n")
    end
    send_message(filetype, concat_message, config)
end

M.send_buffer_to_repl = function(config)
    local filetype = vim.bo.filetype
    local message = construct_message_from_buffer()
    local concat_message = ""
    if vim.fn.has('win32') == 1 then
        concat_message = table.concat(message, "<C-m>")
    else
        concat_message = table.concat(message, "\n")
    end
    send_message(filetype, concat_message, config)
end

M.send_markdown_codeblock_to_repl = function(config)
    local filetype = vim.bo.filetype
    if filetype ~= "markdown" then
        vim.notify("Not a markdown file", vim.log.levels.WARN)
        return
    end

    local codeblock = get_current_markdown_codeblock()
    if not codeblock then
        vim.notify("No fenced code block found", vim.log.levels.WARN)
        return
    end

    local message = vim.split(codeblock.content, '\n', { trimempty = false })
    local concat_message = ""
    if vim.fn.has('win32') == 1 then
        concat_message = table.concat(message, "<C-m>")
    else
        concat_message = table.concat(message, "\n")
    end
    send_message(codeblock.language, concat_message, config)
end

M.open_repl = function(config)
    local filetype = vim.bo.filetype
    term_open(filetype, config)
end

M.toggle_repl_win = function(config)
    vim.print(vim.inspect(M.term))

    -- create if not exists
    if M.term.bufid == nil or M.term.bufid <= 0 then
        M.open_repl(config)
        return
    end

    -- toggle
    if M.term.winid == nil or M.term.winid <= 0 then
        local orig_win = vim.api.nvim_get_current_win()
        M.term.winid = create_win(config, M.term.bufid, orig_win)
    else
        vim.print("hiding repl window "..M.term.winid)
        vim.api.nvim_win_hide(M.term.winid)
        M.term.winid = nil
    end
end

return M

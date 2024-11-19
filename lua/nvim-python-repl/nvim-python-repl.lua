local ts_utils = require("nvim-treesitter.ts_utils")
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
    local node = ts_utils.get_node_at_cursor()
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

local term_open = function(filetype, config)
    local orig_win = vim.api.nvim_get_current_win()
    if M.term.chanid ~= nil then return end
    if config.vsplit then
        api.nvim_command('vsplit')
    else
        api.nvim_command('split')
    end
    local buf = vim.api.nvim_create_buf(true, true)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
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
    M.term.opened = 1
    M.term.winid = win
    M.term.bufid = buf
    -- Return to original window
    api.nvim_set_current_win(orig_win)
end

-- CONSTRUCTING MESSAGE
local construct_message_from_selection = function(start_row, start_col, end_row, end_col)
    local bufnr = api.nvim_get_current_buf()
    if start_row ~= end_row then
        local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
        lines[1] = string.sub(lines[1], start_col + 1)
        -- end_row might be just after the last line. In this case the last line is not truncated.
        if #lines == end_row - start_row then
            lines[#lines] = string.sub(lines[#lines], 1, end_col)
        end
        return lines
    else
        local line = api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
        -- If line is nil then the line is empty
        return line and { string.sub(line, start_col + 1, end_col) } or {}
    end
end

local construct_message_from_buffer = function()
    local bufnr = api.nvim_get_current_buf()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return lines
end

local construct_message_from_node = function(filetype)
    local node = get_statement_definition(filetype)
    local bufnr = api.nvim_get_current_buf()
    local message = vim.treesitter.get_node_text(node, bufnr)
    if filetype == "python" then
        -- For Python, we need to preserve the original indentation
        local start_row, start_column, end_row, _ = node:range()
        if vim.fn.has('win32') == 1 then
            local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
            message = table.concat(lines, api.nvim_replace_termcodes("<cr>", true, false, true))
        else
            -- For Linux, remove superfluous indentation so nested code is not indented
            while start_column ~= 0 do
                -- For empty blank lines
                message = string.gsub(message, "\n\n+", "\n")
                -- For nested indents in classes/functions
                message = string.gsub(message, "\n%s%s%s%s", "\n")
                start_column = start_column - 4
            end
        end
    end
    return message
end

local send_message = function(filetype, message, config)
    if M.term.opened == 0 then
        term_open(filetype, config)
    end
    vim.wait(600)
    if filetype == "python" or filetype == "lua" then
        if vim.fn.has('win32') == 1 then
            message = message .. "\r\n"
        else
            message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
        end
        api.nvim_chan_send(M.term.chanid, message)
    elseif filetype == "scala" then
        if config.spawn_command.scala == "sbt console" then
            message = api.nvim_replace_termcodes(":paste<cr>" .. message .. "<cr><C-d>", true, false, true)
        else
            message = api.nvim_replace_termcodes("{<cr>" .. message .. "<cr>}", true, false, true)
        end
        api.nvim_chan_send(M.term.chanid, message)
    end
    if config.execute_on_send then
        vim.wait(500)
        if vim.fn.has('win32') == 1 then
            vim.wait(200)
            -- For Windows, simulate pressing Enter
            api.nvim_chan_send(M.term.chanid, api.nvim_replace_termcodes("<C-m>", true, false, true))
        else
            api.nvim_chan_send(M.term.chanid, "\r")
        end
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
    local concat_message = table.concat(message, "\n")
    send_message(filetype, concat_message, config)
end

M.send_buffer_to_repl = function(config)
    local filetype = vim.bo.filetype
    local message = construct_message_from_buffer()
    local concat_message = table.concat(message, "\n")
    send_message(filetype, concat_message, config)
end

M.open_repl = function(config)
    local filetype = vim.bo.filetype
    term_open(filetype, config)
end

return M

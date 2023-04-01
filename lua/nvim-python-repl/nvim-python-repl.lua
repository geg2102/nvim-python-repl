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
    if filetype == 'scala' then
        choice = config.spawn_command.scala
    elseif filetype == 'python' then
        choice = config.spawn_command.python
    elseif filetype == 'lua' then
        choice = config.spawn_command.lua
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
        local _, start_column, _, _ = node:range()
        while start_column ~= 0 do
            -- For empty blank lines
            message = string.gsub(message, "\n\n+", "\n")
            -- For nested indents in classes/functions
            message = string.gsub(message, "\n%s%s%s%s", "\n")
            start_column = start_column - 4
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
        message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
    elseif filetype == "scala" then
        if config.spawn_command.scala == "sbt console" then
            message = api.nvim_replace_termcodes(":paste<cr>" .. message .. "<cr><C-d>", true, false, true)
        else
            message = api.nvim_replace_termcodes("{<cr>" .. message .. "<cr>}", true, false, true)
        end
    end
    if config.execute_on_send then
        message = api.nvim_replace_termcodes(message .. "<cr>", true, false, true)
    end
    if M.term.chanid ~= nil then
        api.nvim_chan_send(M.term.chanid, message)
    end
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

return M

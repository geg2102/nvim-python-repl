local ts_utils = require("nvim-treesitter.ts_utils")
local api = vim.api

M = {}

M.term = {
    opened = 0,
    winid = nil,
    bufid = nil,
    chanid = nil,
}

local get_statement_definition = function()
    local node = ts_utils.get_node_at_cursor()
    if (node:named() == false) then
        error("Node not recognized. Check to ensure treesitter parser is installed.")
    end

    while (string.match(node:sexpr(), "statement") == nil and string.match(node:sexpr(), "definition") == nil) do
        node = node:parent()
    end
    return node
end

local select = function ()
    local node = get_statement_definition()
    local bufnr = api.nvim_get_current_buf()
    local text = ts_utils.get_node_text(node, bufnr)
    local _, start_column, _, _ = node:range()
    local message = table.concat(text, "\r")
    while start_column ~= 0 do
        -- For nested indents in classes/functions
        message = string.gsub(message, "\r%s%s%s%s", "\r")
        start_column = start_column - 4
    end
    return message
end

local term_open = function()
    if M.term.chanid ~= nil then return end
    api.nvim_command('vsplit')
    local buf = vim.api.nvim_create_buf(true, true)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win,buf)
    local chan = vim.fn.termopen('ipython', {
        on_exit = function ()
            M.term.chanid = nil
            M.term.opened = 0
            M.term.winid = nil
            M.term.bufid = nil
        end
    })
    vim.bo.filetype = 'term'
    M.term.opened = 1
    M.term.winid = win
    M.term.bufid = buf
    M.term.chanid = chan
end

M.send_statement_definition = function ()
    local message = select()
    if M.term.opened == 0 then
        term_open()
    end
    vim.wait(600)
    message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
    if M.term.chanid ~= nil then
        api.nvim_chan_send(M.term.chanid, message)
    end
end

local visual_selection_range = function()
  local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))
  if start_row < end_row or (start_row == end_row and start_col <= end_col) then
    return start_row - 1, start_col - 1, end_row - 1, end_col
  else
    return end_row - 1, end_col - 1, start_row - 1, start_col
  end
end

local construct_message_from_selection = function (start_row, start_col, end_row, end_col)
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

M.send_visual_to_repl = function ()
    local start_row, start_col, end_row, end_col = visual_selection_range()
    local message = construct_message_from_selection(start_row, start_col, end_row, end_col)
    message = table.concat(message, "\r")
    if M.term.opened == 0 then
        term_open()
    end
    vim.wait(600)
    message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
    if M.term.chanid ~= nil then
        api.nvim_chan_send(M.term.chanid, message)
    end
end

M.send_buffer_to_repl = function()
    local message = construct_message_from_buffer()
    message = table.concat(message, "\r")
    if M.term.opened == 0 then
        term_open()
    end
    vim.wait(600)
    message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
    if M.term.chanid ~= nil then
        api.nvim_chan_send(M.term.chanid, message)
    end
end
return M

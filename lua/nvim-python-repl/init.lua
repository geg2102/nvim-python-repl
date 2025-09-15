local M = {}
local repl = require("nvim-python-repl.nvim-python-repl")
local config = require("nvim-python-repl.config")

function M.setup(options)
    setmetatable(M, {
        __newindex = config.set,
        __index = config.get
    })
    if options ~= nil then
        for k1, v1 in pairs(options) do
            if (type(config.defaults[k1]) == "table") then
                for k2, v2 in pairs(options[k1]) do
                    config.defaults[k1][k2] = v2
                end
            else
                config.defaults[k1] = v1
            end
        end
    end
end

function M.send_current_cell_to_repl()
    repl.send_current_cell_to_repl(M)
end

function M.send_statement_definition()
    repl.send_statement_definition(M)
end

function M.send_visual_to_repl()
    vim.cmd('execute "normal \\<ESC>"')
    repl.send_visual_to_repl(M)
end

function M.send_buffer_to_repl()
    repl.send_buffer_to_repl(M)
end

function M.send_markdown_codeblock_to_repl()
    repl.send_markdown_codeblock_to_repl(M)
end

function M.toggle_execute()
    local original = config.defaults["execute_on_send"]
    config.defaults["execute_on_send"] = not original
    print("execute_on_send=" .. tostring(not original))
end

function M.toggle_vertical()
    local original = config.defaults["vsplit"]
    config.defaults["vsplit"] = not original
    print("vsplit=" .. tostring(not original))
end

function M.toggle_prompt()
    local original = config.defaults["prompt_spawn"]
    config.defaults["prompt_spawn"] = not original
    print("Spawn prompt=" .. tostring(not original))
end

function M.open_repl()
    repl.open_repl(M)
end

function M.toggle_repl_win()
    repl.toggle_repl_win(M)
end

return M

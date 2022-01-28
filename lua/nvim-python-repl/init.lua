local M={}
local repl = require("nvim-python-repl.nvim-python-repl")
local config = require("nvim-python-repl.config")

function M.setup(options)
    setmetatable(M, {
        __newindex = config.set,
        __index = config.get
    })
    if options ~= nil then
        for k, v1 in pairs(options) do
            config.defaults[k] = v1
        end
    end
end

function M.send_statement_definition()
    repl.send_statement_definition(M)
end

function M.send_visual_to_repl()
    repl.send_visual_to_repl(M)
end

function M.send_buffer_to_repl()
    repl.send_buffer_to_repl(M)
end

function M.toggle_execute()
    local original = config.defaults["execute_on_send"]
    config.defaults["execute_on_send"] = not original
    print("execute_on_send=" .. tostring(not original))
end

return M


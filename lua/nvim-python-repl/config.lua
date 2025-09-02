local defaults = {
    execute_on_send = true,
    vsplit = true,
    prompt_spawn = false,
    spawn_command = {
        python = "ipython",
        scala = "sbt console",
        lua = "ilua",
        bash = "bash",
    }
}

local function set(_, key, value)
    defaults[key] = value
end

local function get(_, key)
    return defaults[key]
end

return {
    defaults = defaults,
    get = get,
    set = set
}

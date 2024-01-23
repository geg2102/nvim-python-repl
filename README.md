# nvim-python-repl 
[![asciicast](https://asciinema.org/a/34uNXyyhsDJFDBFSAzzrf9B1b.svg)](https://asciinema.org/a/34uNXyyhsDJFDBFSAzzrf9B1b)

A simple plugin that leverages treesitter to send expressions, statements,
function definitions and class definitions to a REPL. 

The plugin now supports three different filetypes: python, scala and lua. It is
suggested that you have [ipython](https://ipython.org/),
[sbt](https://www.scala-sbt.org), and [ilua](https://github.com/guysv/ilua)
installed in your path respectively. (Scala projects are expecting that the scala file
is opened from the directory containing `build.sbt`).

In addition to sending treesitter objects, there is also support for sending a
selection from visual mode. 

### Usage 

Can be installed with any plugin manager. For example, in lazy you can use 

``` 
...
    {
    "geg2102/nvim-python-repl",
    dependencies = "nvim-treesitter",
    ft = {"python", "lua", "scala"}, 
    config = function()
        require("nvim-python-repl").setup({
            execute_on_send = false,
            vsplit = false,
        })
    end
    }
...

```

Somewhere in your init.lua/init.vim you should place 

``` require("nvim-python-repl").setup() ```

### Keymaps


There are a few keybindings that the user needs to set up. 

```[lua]
vim.keymap.set("n", [your keymap], function() require('nvim-python-repl').send_statement_definition() end, { desc = "Send semantic unit to REPL"})

vim.keymap.set("v", [your keymap], function() require('nvim-python-repl').send_visual_to_repl() end, { desc = "Send visual selection to REPL"})

vim.keymap.set("n", [your keyamp], function() require('nvim-python-repl').send_buffer_to_repl() end, { desc = "Send entire buffer to REPL"})

vim.keymap.set("n", [your keymap], function() require('nvim-python-repl').toggle_execute() end, { desc = "Automatically execute command in REPL after sent"})

vim.keymap.set("n", [your keymap], function() require('nvim-python-repl').toggle_vertical() end, { desc = "Create REPL in vertical or horizontal split"})
```

### Options 
There are a few options. First, whether to execute the given expression on send
and second, whether to send to a vertical split. By default these are set to true. Toggle on send
can be toggled with `<leader>e` or `:ToggleExecuteOnSend`. Whether to send to vertical
by default can be changed with `:ReplToggleVertical` or `:lua
require("nvim-python-repl").toggle_vertical()`. 


There is an also an option to specify which spawn command you want to use for a given repl (passed as table). 

Here is the default setup: 

``` 
require("nvim-python-repl").setup({
    execute_on_send=false, 
    vsplit=false,
    spawn_command={
        python="ipython", 
        scala="sbt console",
        lua="ilua"
    }
}) 
```


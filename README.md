# nvim-python-repl 

[![asciicast](https://asciinema.org/a/460861.svg)](https://asciinema.org/a/460861)

A simple plugin leveraging treesitter to send expressions, statements, function
definitions and class definitions to an ipython REPL. Also supports sending selection
from visual mode. Default keymapping for sending a treesitter object or visual selection
is set to `<leader>n`. Default keymapping for sending the entire buffer is `<leader>nr`.
Can be switched with 

```
vim.api.nvim_set_keymap('n', [your keymap], ":SendPyObject<CR>", {noremap=true, silent=true})
``` 

```
vim.api.nvim_set_keymap('v', [your keymap], ":<C-U>SendPySelection<CR>", {noremap=true, silent=true})
```

```
vim.api.nvim_set_keymap('n', [your keymap], ":SendPyBuffer<CR>", {noremap=true, silent=true})
```

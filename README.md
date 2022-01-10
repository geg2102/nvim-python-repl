# nvim-python-repl 
A simple plugin leveraging treesitter to send expressions, statements, function
definitions and class definitions to an ipython REPL. Also supports sending
selecting from visual mode. Default keymapping is set to `<leader>n`. Can be
switched with 

```vim.api.nvim_set_keymap('n', [your keymap], ":SendPyObject<CR>", {noremap=true, silent=true})```
```vim.api.nvim_set_keymap('v', [your keymap], ":<C-U>SendPySelection<CR>", {noremap=true, silent=true})```

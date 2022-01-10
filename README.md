# nvim-python-repl
A simple plugin leveraging treesitter to send expressions, statements, function definitions and class definitions to an ipython REPL. 
Default keymapping is set to `<leader>n`. Can be switched with 

```vim.api.nvim_set_keymap('n', [your keymap], "<cmd>SendPyObject<CR>", {noremap=true, silent=true})```

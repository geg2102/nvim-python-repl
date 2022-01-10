if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" The send statement/definition command.
command! SendPyObject              lua require("nvim-python-repl").send_statement_definition()
command! SendPySelection           lua require("nvim-python-repl").send_visual_to_repl()

nnoremap <silent> <leader>n :SendPyObject<CR>
vnoremap <silent> <leader>n :<C-U>SendPySelection<CR>

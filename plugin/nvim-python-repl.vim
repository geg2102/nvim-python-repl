if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" The send statement/definition command.
command! SendPyObject              lua require("nvim-python-repl").send_statement_definition()
command! SendPySelection           lua require("nvim-python-repl").send_visual_to_repl()
command! SendPyBuffer              lua require("nvim-python-repl").send_buffer_to_repl()
command! ToggleExecuteOnSend       lua require("nvim-python-repl").toggle_execute()
command! ReplToggleVertical        lua require("nvim-python-repl").toggle_vertical()

nnoremap <silent> <leader>n :SendPyObject<CR>
nnoremap <silent> <leader>e :ToggleExecuteOnSend<CR>
nnoremap <silent> <leader>nr :SendPyBuffer<CR>
vnoremap <silent> <leader>n :<C-U>SendPySelection<CR>

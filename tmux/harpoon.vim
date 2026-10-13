" Buffer setup for the tmux harpoon list popup (sourced by harpoon.sh edit).
" Edit it like any buffer: dd/p to reorder, dd to remove. Line N = slot N.
setlocal number nowrap nospell
let &l:winbar = '%#Title# harpoon %*  h j k l = lines 1-4  ·  <CR> jump  ·  q save+close'

" q / <Esc>: save and close.
nnoremap <buffer><silent> q     <Cmd>silent! write<Bar>qall!<CR>
nnoremap <buffer><silent> <Esc> <Cmd>silent! write<Bar>qall!<CR>

" <CR>: save, close, and jump to the session under the cursor.
nnoremap <buffer><silent> <CR> <Cmd>call writefile([trim(getline('.'))], $HARPOON_PICK)<Bar>silent! write<Bar>qall!<CR>

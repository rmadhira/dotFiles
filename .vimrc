set nocompatible              " be iMproved, required                              
filetype off                  " required                                           
                                                                                   
" git clone https://github.com/gmarik/Vundle.vim.git ~/.vim/bundle/Vundle.vim
" set the runtime path to include Vundle and initialize                            
set rtp+=~/.vim/bundle/Vundle.vim                                                  
call vundle#begin()                                                                
" alternatively, pass a path where Vundle should install plugins                   
"call vundle#begin('~/some/path/here')                                             
                                                                                   
" let Vundle manage Vundle, required                                               
Plugin 'VundleVim/Vundle.vim'                                                      
                                                                                   
" tmux vim navigator                                                               
Plugin 'christoomey/vim-tmux-navigator'                                            
                                                                                   
" Asynchronous Lint Engine                                                         
Plugin 'dense-analysis/ale'                                                        
                                                                                   
" Python PEP8                                                                      
Plugin 'nvie/vim-flake8'                                                           
                                                                                   
" Python autocompletion                                                            
Plugin 'davidhalter/jedi-vim'                                                      
                                                                                   
" Color scheme
Plugin 'gosukiwi/vim-atom-dark'

" All of your Plugins must be added before the following line                      
call vundle#end()            " required                                            
filetype plugin indent on    " required                                            
" To ignore plugin indent changes, instead use:                                    
"filetype plugin on                                                                
"                                                                                  
" Brief help                                                                       
" :PluginList       - lists configured plugins                                     
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache          
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"                                                                                  
" see :h vundle for more details or wiki for FAQ                                   
" Put your non-Plugin stuff after this line                                        
" 

" Syntax highlighting
syntax on

" Show whitespace [ before color scheme]
" All Available colors
" git clone https://github.com/gosukiwi/vim-atom-dark.git
set t_Co=256
colorscheme atom-dark-256

" Code folding
set foldmethod=indent
set foldlevel=99
nnoremap <space> za

"split navigations
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" Tabs and spaces for python files
" au BufNewFile,BufRead *.py
 set tabstop=4
 set softtabstop=4
 set shiftwidth=4
 set textwidth=79
 set expandtab
 set autoindent
 set fileformat=unix
 set colorcolumn=80
 highlight ColorColumn ctermbg=235
 " Highlight cursorline
 set cursorline

" let g:ale linters = { 'python': ['flake8']}

set number


" Quick save : Just hit control Z or something.
" Quick quit
" map sort function to a key

" Easier moving of code blocks
vnoremap < <gv
vnoremap > >gv

" Easier formatting of text
vmap Q gq
vmap Q gqap

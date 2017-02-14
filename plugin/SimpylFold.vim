if exists('g:loaded_SimpylFold')
    finish
endif
let g:loaded_SimpylFold = 1

command! -bang SimpylFoldDocstrings let b:SimpylFold_fold_docstring = <bang>1 | call SimpylFold#Recache()
command! -bang SimpylFoldImports let b:SimpylFold_fold_import = <bang>1 | call SimpylFold#Recache()

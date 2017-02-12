if exists('b:loaded_SimpylFold')
    finish
endif
let b:loaded_SimpylFold = 1

call SimpylFold#SetDefRegex()
setlocal foldexpr=SimpylFold#FoldExpr(v:lnum)
setlocal foldmethod=expr

augroup SimpylFold
    autocmd TextChanged,InsertLeave <buffer> call SimpylFold#Recache()
augroup END

if exists('g:SimpylFold_docstring_preview') && g:SimpylFold_docstring_preview
    setlocal foldtext=foldtext()\ .\ SimpylFold#FoldText()
endif

command! -bang SimpylFoldDocstrings let s:fold_docstrings = <bang>1 | call SimpylFold#Recache()
command! -bang SimpylFoldImports let s:fold_imports = <bang>1 | call SimpylFold#Recache()

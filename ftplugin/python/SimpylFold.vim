if exists('b:loaded_SimpylFold')
    finish
endif
let b:loaded_SimpylFold = 1

call SimpylFold#BufferInit()
setlocal foldexpr=SimpylFold#FoldExpr(v:lnum)
setlocal foldmethod=expr

augroup SimpylFold
    autocmd TextChanged,InsertLeave <buffer> call SimpylFold#Recache()
augroup END

if exists('g:SimpylFold_docstring_preview') && g:SimpylFold_docstring_preview
    setlocal foldtext=foldtext()\ .\ SimpylFold#FoldText()
endif

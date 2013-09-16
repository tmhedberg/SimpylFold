if exists('b:loaded_SimpylFold')
    finish
endif
let b:loaded_SimpylFold = 1

let s:blank_regex = '^\s*$'
let s:def_regex = '^\s*\%(class\|def\) \w\+'

" Determine the number of containing class or function definitions for the
" given line
function! s:NumContainingDefs(lnum)

    " Recall memoized result if it exists in the cache
    if has_key(b:cache_NumContainingDefs, a:lnum)
        return b:cache_NumContainingDefs[a:lnum]
    endif

    let this_ind = indent(a:lnum)

    if this_ind == 0
        return 0
    endif

    " Walk backwards to the previous non-blank line with a lower indent level
    " than this line
    let i = a:lnum - 1
    while 1
        if getline(i) !~ s:blank_regex
            let i_ind = indent(i)
            if i_ind < this_ind
                let ncd = s:NumContainingDefs(i) + (getline(i) =~ s:def_regex)
                break
            elseif i_ind == this_ind && has_key(b:cache_NumContainingDefs, i)
                let ncd = b:cache_NumContainingDefs[i]
                break
            endif
        endif

        let i -= 1

        " If we hit the beginning of the buffer before finding a line with a
        " lower indent level, there must be no definitions containing this
        " line. This explicit check is required to prevent infinite looping in
        " the syntactically invalid pathological case in which the first line
        " or lines has an indent level greater than 0.
        if i <= 1
            let ncd = getline(1) =~ s:def_regex
            break
        endif

    endwhile

    " Memoize the return value to avoid duplication of effort on subsequent
    " lines
    let b:cache_NumContainingDefs[a:lnum] = ncd

    return ncd

endfunction

" Compute fold level for Python code
function! SimpylFold(lnum)

    " If we are starting a new sweep of the buffer (i.e. the current line
    " being folded comes before the previous line that was folded), initialize
    " the cache of results of calls to `s:NumContainingDefs`
    if !exists('b:last_folded_line') || b:last_folded_line > a:lnum
        let b:cache_NumContainingDefs = {}
    endif
    let b:last_folded_line = a:lnum

    " If this line is blank, its fold level is equal to the minimum of its
    " neighbors' fold levels, but if the next line begins a definition, then
    " this line should fold at one level below the next
    let line = getline(a:lnum)
    if line =~ s:blank_regex
        let next_line = nextnonblank(a:lnum)
        if next_line == 0
            return 0
        elseif getline(next_line) =~ s:def_regex
            return SimpylFold(next_line) - 1
        else
            return -1
        endif
    endif

    " Otherwise, its fold level is equal to its number of containing
    " definitions, plus 1, if this line starts a definition of its own
    let this_fl = s:NumContainingDefs(a:lnum) + (line =~ s:def_regex)

    " If the very next line starts a definition with the same fold level as
    " this one, explicitly indicate that a fold ends here
    if getline(a:lnum + 1) =~ s:def_regex && SimpylFold(a:lnum + 1) == this_fl
        return '<' . this_fl
    else
        return this_fl
    endif

endfunction

" Obtain the first line of the docstring for the folded class or function, if
" any exists, for use in the fold text
function! SimpylFoldText()
    let next = nextnonblank(v:foldstart + 1)
    let docstring = getline(next)
    let ds_prefix = '^\s*\%(\%(["'']\)\{3}\|[''"]\ze[^''"]\)'
    if docstring =~ ds_prefix
        let quote_char = docstring[match(docstring, '["'']')]
        let docstring = substitute(docstring, ds_prefix, '', '')
        if docstring =~ s:blank_regex
            let docstring =
                \ substitute(getline(nextnonblank(next + 1)), '^\s*', '', '')
        endif
        let docstring = substitute(docstring, quote_char . '\{,3}$', '', '')
        return ' ' . docstring
    endif
    return ''
endfunction

setlocal foldexpr=SimpylFold(v:lnum)
setlocal foldmethod=expr

if exists('SimpylFold_docstring_preview') && SimpylFold_docstring_preview
    setlocal foldtext=foldtext()\ .\ SimpylFoldText()
endif

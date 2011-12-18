let s:blank_regex = '^\s*$'
let s:def_regex = '^\s*\%(class\|def\) \w\+'

" Determine the number of containing class or function definitions for the
" given line
function! s:NumContainingDefs(lnum)

    let this_ind = indent(a:lnum)

    if this_ind == 0
        return 0
    endif

    " Walk backwards to the previous non-blank line with a lower indent level
    " than this line
    let i = a:lnum - 1
    while (getline(i) =~ s:blank_regex || indent(i) >= this_ind)

        let i -= 1

        " If we hit the beginning of the buffer before finding a line with a
        " lower indent level, there must be no definitions containing this
        " line. This explicit check is required to prevent infinite looping in
        " the syntactically invalid pathological case in which the first line
        " or lines has an indent level greater than 0.
        if i <= 1
            return 0
        endif

    endwhile

    return s:NumContainingDefs(i) + (getline(i) =~ s:def_regex)

endfunction

" Compute fold level for Python code
function! SimpylFold(lnum)

    " If this line is blank, its fold level is equal to the minimum of its
    " neighbors' fold levels, but if the next line begins a definition, then
    " this line should fold at one level below the next
    let line = getline(a:lnum)
    if line =~ s:blank_regex
        let next_line = nextnonblank(a:lnum)
        if getline(next_line) =~ s:def_regex
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

set foldexpr=SimpylFold(v:lnum)
set foldmethod=expr

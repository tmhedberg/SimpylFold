if exists('b:loaded_SimpylFold')
    finish
endif
let b:loaded_SimpylFold = 1

let s:blank_regex = '\v^\s*(\#.*)?$'
if &ft == 'pyrex' || &ft == 'cython'
    let b:def_regex = '\v^\s*%(%(class|%(async\s+)?def|cdef|cpdef|ctypedef)\s+\w+)|cdef\s*:\s*'
else
    let b:def_regex = '\v^\s*%(class|%(async\s+)?def)\s+\w+|if\s*__name__\s*\=\=\s*%("__main__"|''__main__'')\s*:\s*'
endif
let s:multiline_def_end_regex = '):$'
let s:docstring_start_regex = '^\s*[rR]\?\("""\|''''''\)\%(.*\1\s*$\)\@!'
let s:docstring_end_single_regex = '''''''\s*$'
let s:docstring_end_double_regex = '"""\s*$'
let s:import_start_regex = '^\%(from\|import\)'
let s:import_cont_regex = 'from.*\((\)[^)]*$\|.*\(\\\)$'
let s:import_end_paren_regex = ')\s*$'
let s:import_end_esc_regex = '[^\\]$'

if exists('SimpylFold_docstring_level')
    let s:docstring_level = SimpylFold_docstring_level
else
    let s:docstring_level = -1
end

if exists('SimpylFold_import_level')
    let s:import_level = SimpylFold_import_level
else
    let s:import_level = -1
end

function! s:GetLine(lnum)
    let line = getline(a:lnum)
    if line =~ '^\s*):\s*$'
        let line = "    " . line
    endif
    return line
endfunction

function! s:GetIndent(lnum)
    let ind = indent(a:lnum)
    let line = getline(a:lnum)
    if line =~ '^\s*):\s*$'
        let ind = 4 + ind
    endif
    return ind
endfunction

" Returns the next non-blank line, checking for our definition of blank using
" the s:blank_regex variable described above.
function! s:NextNonBlankOrCommentLine(lnum)

    let nnb = a:lnum + 1
    while nnb > 0
        let nnb = nextnonblank(nnb)
        if nnb == 0 || s:GetLine(nnb) !~ s:blank_regex
            return nnb
        endif

        let nnb += 1
    endwhile
    " this return statement should never be reached, since nextnonblank()
    " should never return a negative number.  It returns 0 when it reaches EOF.
    return -2
endfunction

" Determine the number of containing class or function definitions for the
" given line
function! s:NumContainingDefs(lnum)
    " Recall memoized result if it exists in the cache
    if has_key(b:cache_NumContainingDefs, a:lnum)
        return b:cache_NumContainingDefs[a:lnum]
    endif

    let this_ind = s:GetIndent(a:lnum)

    if this_ind == 0
        return 0
    endif

    " Walk backwards to the previous non-blank line with a lower indent level
    " than this line
    let i = a:lnum - 1
    while 1
        if s:GetLine(i) !~ s:blank_regex
            let i_ind = s:GetIndent(i)
            if i_ind < this_ind
                let ncd = s:NumContainingDefs(i) + (s:GetLine(i) =~# b:def_regex)
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
            let ncd = s:GetLine(1) =~# b:def_regex
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
        let b:in_docstring = 0
        let b:in_import = 0
    endif
    let b:last_folded_line = a:lnum

    " If this line is blank, its fold level is equal to the minimum of its
    " neighbors' fold levels, but if the next line begins a definition, then
    " this line should fold at one level below the next
    let line = s:GetLine(a:lnum)
    if line =~ s:blank_regex
        let next_line = s:NextNonBlankOrCommentLine(a:lnum)
        if next_line == 0
            return 0
        elseif s:GetLine(next_line) =~# b:def_regex
            return SimpylFold(next_line) - 1
        else
            return -1
        endif
    endif

    let fold_docstrings =
        \ !exists('g:SimpylFold_fold_docstring') || g:SimpylFold_fold_docstring
    let fold_imports =
        \ !exists('g:SimpylFold_fold_import') || g:SimpylFold_fold_import
    let docstring_match = matchlist(line, s:docstring_start_regex)
    let import_match = matchlist(line, s:import_start_regex)
    let prev_line = s:GetLine(a:lnum - 1)
    if !b:in_docstring &&
        \ (
          \ prev_line =~# b:def_regex ||
          \ prev_line =~ s:multiline_def_end_regex
        \ ) &&
        \ len(docstring_match)

        if s:docstring_level == -1
            let this_fl = s:NumContainingDefs(a:lnum) + fold_docstrings
        else
            let this_fl = s:docstring_level
        end

        let b:in_docstring = 1
        if docstring_match[1] == '"""'
            let b:docstring_end_regex = s:docstring_end_double_regex
        else
            let b:docstring_end_regex = s:docstring_end_single_regex
        endif
    elseif b:in_docstring
        if s:docstring_level == -1
            let this_fl = s:NumContainingDefs(a:lnum) + fold_docstrings
        else
            let this_fl = s:docstring_level
        end

        if line =~ b:docstring_end_regex
            let b:in_docstring = 0
        endif
    elseif b:in_import == 1
        if s:import_level == -1
            let this_fl = s:NumContainingDefs(a:lnum) + fold_imports
        else
            let this_fl = s:import_level
        end

        if line =~ b:import_end_regex
            let b:in_import = 0
        endif
    elseif b:in_import == 0 && len(import_match)
        let b:in_import = 1

        let import_cont_match = matchlist(line, s:import_cont_regex)

        if len(import_cont_match) && import_cont_match[1] == '('
            let b:import_end_regex = s:import_end_paren_regex
        elseif len(import_cont_match) && import_cont_match[2] == '\'
            let b:import_end_regex = s:import_end_esc_regex
        else
            let b:in_import = 0
        end

        if s:import_level == -1
            let this_fl = s:NumContainingDefs(a:lnum) + fold_imports
        else
            let this_fl = s:import_level
        end
    else
        " Otherwise, its fold level is equal to its number of containing
        " definitions, plus 1, if this line starts a definition of its own
        let this_fl = s:NumContainingDefs(a:lnum) + (line =~# b:def_regex)

    endif
    " If the very next line starts a definition with the same fold level as
    " this one, explicitly indicate that a fold ends here
    if s:GetLine(a:lnum + 1) =~# b:def_regex && SimpylFold(a:lnum + 1) == this_fl
        return '<' . this_fl
    else
        return this_fl
    endif

endfunction

" Obtain the first line of the docstring for the folded class or function, if
" any exists, for use in the fold text
function! SimpylFoldText()
    let next = nextnonblank(v:foldstart + 1)
    let docstring = s:GetLine(next)
    let ds_prefix = '^\s*\%(\%(["'']\)\{3}\|[''"]\ze[^''"]\)'
    if docstring =~ ds_prefix
        let quote_char = docstring[match(docstring, '["'']')]
        let docstring = substitute(docstring, ds_prefix, '', '')
        if docstring =~ s:blank_regex
            let docstring =
                \ substitute(s:GetLine(nextnonblank(next + 1)), '^\s*', '', '')
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

let s:blank_re = '^\s*$'
let s:comment_re = '^\s*#'
let s:multi_def_end_re = ')\%(\s*->\s*\S\+[^#]*\)\?:\s*\%(#.*\)\?$'
let s:multi_def_end_solo_re = '^\s*)\%(\s*->\s*\S\+[^#]*\)\?:\s*\%(#.*\)\?$'
let s:docstring_re = '^\s*[bBfFrRuU]\{0,2}\\\@<!\(''''''\|"""\|[''"]\)'
let s:string_start_re = '[bBfFrRuU]\{0,2}\\\@<!\%(''''''\|"""\|[''"]\)'
let s:string_prefix_re = '[bBfFrRuU]\{0,2}'
let s:line_cont_re = '\\$'
let s:import_start_re = '^\s*\%(from\|import\)'
let s:import_cont_re = '\%(from.*\((\)[^)]*\|.*\(\\\)\)$'
let s:import_end_paren_re = ')\s*$'
let s:import_end_esc_re = '[^\\]$'

" Initialize buffer
function! SimpylFold#BufferInit() abort
    if &filetype ==# 'pyrex' || &filetype ==# 'cython'
        let b:SimpylFold_def_re =
            \ '\v^\s*%(%(class|%(async\s+)?def|cdef|cpdef|ctypedef)\s+\w+)|cdef\s*:'
    else
        let b:SimpylFold_def_re =
            \ '\v^\s*%(class|%(async\s+)?def)\s+\w+|if\s+__name__\s*\=\=\s*%("__main__"|''__main__'')\s*:'
    endif

    if !exists('b:SimpylFold_fold_docstring')
        let b:SimpylFold_fold_docstring =
            \ !exists('g:SimpylFold_fold_docstring') || g:SimpylFold_fold_docstring
    endif
    if !exists('b:SimpylFold_fold_import')
        let b:SimpylFold_fold_import =
            \ !exists('g:SimpylFold_fold_import') || g:SimpylFold_fold_import
    endif
    if !exists('b:SimpylFold_fold_blank')
        let b:SimpylFold_fold_blank =
            \ exists('g:SimpylFold_fold_blank') && g:SimpylFold_fold_blank
    endif
endfunction

" Get spaces per indent setting
function! s:indent_spaces() abort
    if &softtabstop > 0
        return &softtabstop
    elseif &softtabstop < 0 && &shiftwidth > 0
        return &shiftwidth
    endif
    return &tabstop
endfunction

" Calculate indent
function! s:indent(line, ind_spaces) abort
    let ind = matchend(a:line, '^ *') / a:ind_spaces
    if ind == 0
        let ind = matchend(a:line, '^\t*')
    endif
    " Fix indent for solo def multiline endings
    if a:line =~# s:multi_def_end_solo_re
        return ind + 1
    endif
    return ind
endfunction

function! s:defs_stack_prune(cache, defs_stack, ind) abort
    for idx in range(len(a:defs_stack))
        let ind_stack = a:cache[(a:defs_stack[idx])]['indent']
        if a:ind == ind_stack
            return a:defs_stack[(idx + 1):]
        elseif a:ind > ind_stack
            return a:defs_stack[(idx):]
        endif
    endfor
    return []
endfunction

" Adjust previous blanks and comments
function! s:blanks_adj(cache, lnum, foldlevel) abort
    if b:SimpylFold_fold_blank
        return
    endif
    let lnum_prev = a:lnum - 1
    while lnum_prev != 0 && (
            \ a:cache[lnum_prev]['is_blank'] || (
                \ a:cache[lnum_prev]['is_comment'] &&
                \ a:cache[lnum_prev]['indent'] <= a:cache[(a:lnum)]['indent']
            \ )
        \ )
        let a:cache[lnum_prev]['foldexpr'] = a:foldlevel
        let lnum_prev -= 1
    endwhile
endfunction

" Check if previous lines are blanks or comments
function! s:are_lines_prev_blank(cache, lnum) abort
    let lnum_prev = a:lnum - 1
    while lnum_prev != 0
        if !a:cache[lnum_prev]['is_blank'] && !a:cache[lnum_prev]['is_comment']
            return 0
        endif
        let lnum_prev -= 1
    endwhile
    return 1
endfunction

" Compatibility shim
" 1.1x slower when `matchstrpos` exists
" 2.5x slower otherwise
let s:exists_matchstrpos = exists('*matchstrpos')
function! s:matchstrpos(expr, pat) abort
    if s:exists_matchstrpos
        return matchstrpos(a:expr, a:pat)
    else
        return [matchstr(a:expr, a:pat), match(a:expr, a:pat), matchend(a:expr, a:pat)]
    endif
endfunction

" Multiline string parsing
" Returns:
"     - bool: In string?
"     - bool: Single quoted?
"     - bool: Found multiple strings?
"     - string: End regex.
"     - string: Everything before first match.
function! s:multi_string(line, first_re, in_string) abort
    " 2x performance for general case
    if a:line !~# '[''"]'
        return [a:in_string, 0, 0, '', '']
    endif

    let string_match = s:matchstrpos(a:line, a:first_re)
    if string_match[1] == -1
        return [a:in_string, 0, 0, '', '']
    endif

    " Anything before first match?
    if string_match[1] >= 1
        let before_first = a:line[:(string_match[1] - 1)]
    else
        let before_first = ''
    endif

    let in_string = a:in_string
    let next_re = ''
    let line_slice = a:line
    let found_ends = 0
    while string_match[1] != -1
        if in_string
            let in_string = 0
            let found_ends += 1
            let next_re = s:string_start_re
        else
            let in_string = 1
            let quotes = string_match[0][matchend(string_match[0], s:string_prefix_re):]
            let next_re = '\\\@<!' . quotes
        endif

        let line_slice = line_slice[(string_match[2]):]
        if empty(line_slice)
            break
        endif
        let string_match = s:matchstrpos(line_slice, next_re)
    endwhile

    if in_string
        " Check if in single quoted string and line continues
        let single_quoted = quotes =~# '^[''"]$'
        if single_quoted && line_slice !~# s:line_cont_re
            return [0, single_quoted, (found_ends >= 1), '', before_first]
        else
            return [1, single_quoted, (found_ends >= 1), next_re, before_first]
        endif
    else
        return [0, 0, (found_ends >= 2), '', before_first]
    endif
endfunction

" Create a new cache
function! s:cache() abort
    let cache = [{}]  " With padding for lnum offset
    let lines = getbufline(bufnr('%'), 1, '$')
    let lnum_last = len(lines)
    call insert(lines, '')  " Padding for lnum offset

    let ind_spaces = s:indent_spaces()

    let defs_stack = []
    let ind_def = -1
    let in_string = 0
    let docstring_start = -1
    let in_import = 0
    let was_import = 0
    for lnum in range(1, lnum_last)
        let line = lines[lnum]

        " Multiline strings
        if in_string
            let foldlevel = len(defs_stack)
            call add(cache, {'is_blank': 0, 'is_comment': 0, 'foldexpr': foldlevel})

            let string_match = s:multi_string(line, string_end_re, 1)
            if string_match[0]
                " Starting new multiline string?
                if string_match[2]
                    let in_string_single = string_match[1]
                    let string_end_re = string_match[3]
                    let docstring_start = -1  " Invalid docstring
                elseif in_string_single && line !~# s:line_cont_re
                    let in_string = 0
                endif
            else
                if docstring_start != -1
                    let foldlevel += 1
                    let cache[docstring_start]['foldexpr'] = '>' . foldlevel
                    for lnum_docstring in range((docstring_start + 1), lnum)
                        let cache[lnum_docstring]['foldexpr'] = foldlevel
                    endfor
                    let docstring_start = -1
                endif
                let in_string = 0
            endif
            continue
        endif

        " Blank lines
        if line =~# s:blank_re
            if lnum == lnum_last
                call add(cache, {'is_blank': 1, 'is_comment': 0, 'foldexpr': 0})
                call s:blanks_adj(cache, lnum, 0)
            else
                call add(cache, {'is_blank': 1, 'is_comment': 0, 'foldexpr': len(defs_stack)})
            endif
            continue
        endif

        let ind = s:indent(line, ind_spaces)

        " Comments
        if line =~# s:comment_re
            call add(cache, {'is_blank': 0, 'is_comment': 1, 'indent': ind})
            let foldlevel = 0
            let defs_stack_len = len(defs_stack)
            for idx in range(defs_stack_len)
                if ind > cache[defs_stack[idx]]['indent']
                    let foldlevel = defs_stack_len - idx
                    break
                endif
            endfor
            let cache[lnum]['foldexpr'] = foldlevel
            call s:blanks_adj(cache, lnum, foldlevel)
            continue
        endif

        call add(cache, {'is_blank': 0, 'is_comment': 0,
            \            'is_def': line =~# b:SimpylFold_def_re, 'indent': ind})

        " Definitions
        if cache[lnum]['is_def']
            if empty(defs_stack)
                let defs_stack = [lnum]
            elseif ind == ind_def
                let defs_stack[0] = lnum
            elseif ind > ind_def
                call insert(defs_stack, lnum)
            elseif ind < ind_def
                let defs_stack = [lnum] + s:defs_stack_prune(cache, defs_stack, ind)
            endif
            let foldlevel = len(defs_stack) - 1
            let ind_def = ind
            call s:blanks_adj(cache, lnum, foldlevel)
            let cache[lnum]['foldexpr'] = '>' . (foldlevel + 1)
            continue
        endif

        " Everything else
        if !empty(defs_stack)
            if ind == ind_def
                let defs_stack = defs_stack[1:]
                let ind_def = cache[defs_stack[0]]['indent']
            elseif ind < ind_def
                let defs_stack = s:defs_stack_prune(cache, defs_stack, ind)
                if !empty(defs_stack)
                    let ind_def = cache[defs_stack[0]]['indent']
                else
                    let ind_def = -1
                endif
            endif
        endif
        let foldlevel = len(defs_stack)

        " Multiline strings start
        let string_match = s:multi_string(line, s:string_start_re, 0)
        if string_match[0]
            let in_string = 1
            let in_string_single = string_match[1]
            let string_end_re = string_match[3]

            " Docstrings
            if b:SimpylFold_fold_docstring && !string_match[2] && string_match[4] =~# s:blank_re
                let lnum_prev = lnum - 1
                if lnum == 1 || s:are_lines_prev_blank(cache, lnum) || (
                        \ !cache[lnum_prev]['is_blank'] && !cache[lnum_prev]['is_comment'] && (
                            \ cache[lnum_prev]['is_def'] ||
                            \ lines[lnum_prev] =~# s:multi_def_end_re
                        \ )
                    \ )
                    let docstring_start = lnum
                endif
            endif

            let cache[lnum]['foldexpr'] = foldlevel
            continue
        endif

        " Imports
        if b:SimpylFold_fold_import
            if in_import
                if line =~# import_end_re
                    let in_import = 0
                endif

                call s:blanks_adj(cache, lnum, foldlevel + 1)
                let cache[lnum]['foldexpr'] = foldlevel + 1
                continue
            elseif match(line, s:import_start_re) != -1
                let import_cont_match = matchlist(line, s:import_cont_re)
                if !empty(import_cont_match)
                    if import_cont_match[1] ==# '('
                        let import_end_re = s:import_end_paren_re
                        let in_import = 1
                    elseif import_cont_match[2] ==# '\'
                        let import_end_re = s:import_end_esc_re
                        let in_import = 1
                    endif
                endif

                if was_import
                    call s:blanks_adj(cache, lnum, foldlevel + 1)
                    let cache[lnum]['foldexpr'] = foldlevel + 1
                else
                    let cache[lnum]['foldexpr'] = '>' . (foldlevel + 1)
                endif
                let was_import = 1
                continue
            else
                let was_import = 0
            endif
        endif

        " Normal
        call s:blanks_adj(cache, lnum, foldlevel)
        let cache[lnum]['foldexpr'] = foldlevel
    endfor

    return cache
endfunction

" Compute foldexpr for Python code
function! SimpylFold#FoldExpr(lnum) abort
    if !exists('b:SimpylFold_cache')
        let b:SimpylFold_cache = s:cache()
    endif
    return b:SimpylFold_cache[(a:lnum)]['foldexpr']
endfunction

" Recache the buffer
function! SimpylFold#Recache() abort
    if exists('b:SimpylFold_cache')
        unlet b:SimpylFold_cache
    endif
endfunction

" Compute foldtext by obtaining the first line of the docstring for
" the folded class or function, if any exists
function! SimpylFold#FoldText() abort
    let lnum = v:foldstart
    let line = getline(lnum)
    let string_match = matchlist(line, s:docstring_re)
    " Docstring folds
    if !empty(string_match)
        let docstring = substitute(line, s:docstring_re, '', '')
        if docstring !~# s:blank_re
            return ''
        endif
        let docstring = getline(nextnonblank(lnum + 1))
    " Definition folds
    else
        let lnum = nextnonblank(lnum + 1)
        let line = getline(lnum)
        let string_match = matchlist(line, s:docstring_re)
        if empty(string_match)
            return ''
        endif
        let docstring = substitute(line, s:docstring_re, '', '')
        if docstring =~# s:blank_re
            let docstring = getline(nextnonblank(lnum + 1))
        endif
    endif
    return ' ' . substitute(docstring, '^\s*\|\s*$\|' . string_match[1] . '\s*$', '', 'g')
endfunction

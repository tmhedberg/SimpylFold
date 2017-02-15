let s:blank_regex = '^\s*$'
let s:comment_regex = '^\s*#'
let s:multiline_def_end_regex = '):$'
let s:multiline_def_end_solo_regex = '^\s*):$'
let s:docstring_prefix_regex = '^\s*[rR]\?\%("""\|''''''\|"\ze[^"]\|''\ze[^'']\)'
let s:docstring_start_regex = '^\s*[rR]\?\("""\|''''''\)\%(.*\1\s*$\)\@!'
let s:docstring_end_single_regex = '''''''\s*$'
let s:docstring_end_double_regex = '"""\s*$'
let s:import_start_regex = '^\%(from\|import\)'
let s:import_cont_regex = 'from.*\((\)[^)]*$\|.*\(\\\)$'
let s:import_end_paren_regex = ')\s*$'
let s:import_end_esc_regex = '[^\\]$'

" Initialize buffer
function! SimpylFold#BufferInit() abort
    if &filetype ==# 'pyrex' || &filetype ==# 'cython'
        let b:SimpylFold_def_regex = '\v^\s*%(%(class|%(async\s+)?def|cdef|cpdef|ctypedef)\s+\w+)|cdef\s*:'
    else
        let b:SimpylFold_def_regex = '\v^\s*%(class|%(async\s+)?def)\s+\w+|if\s+__name__\s*\=\=\s*%("__main__"|''__main__'')\s*:'
    endif

    if !exists('b:SimpylFold_fold_docstring')
        let b:SimpylFold_fold_docstring = !exists('g:SimpylFold_fold_docstring') || g:SimpylFold_fold_docstring
    endif
    if !exists('b:SimpylFold_fold_import')
        let b:SimpylFold_fold_import = !exists('g:SimpylFold_fold_import') || g:SimpylFold_fold_import
    endif
endfunction

" Calculate indent
function! s:indent(line) abort
    let ind = matchend(a:line, '^ *') / &softtabstop
    " Fix indent for solo def multiline endings
    if a:line =~# s:multiline_def_end_solo_regex
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
function! s:blanks_adj(cache, lnum, defs) abort
    let lnum_prev = a:lnum - 1
    while lnum_prev != 0 && (
            \ a:cache[lnum_prev]['is_blank'] || (
                \ a:cache[lnum_prev]['is_comment'] &&
                \ a:cache[lnum_prev]['indent'] <= a:cache[(a:lnum)]['indent']
            \ )
        \ )
        let a:cache[lnum_prev]['foldexpr'] = a:defs
        let lnum_prev -= 1
    endwhile
endfunction

" Create a new cache
function! s:cache() abort
    let cache = [{}]  " With padding for lnum offset
    let lines = getbufline(bufnr('%'), 1, '$')
    let lnum_last = len(lines)
    call insert(lines, '')  " Padding for lnum offset

    let defs_stack = []
    let ind_def = -1
    let in_docstring = 0
    let in_import = 0
    let was_import = 0
    for lnum in range(1, lnum_last)
        let line = lines[lnum]

        " Blank lines
        if line =~# s:blank_regex
            call add(cache, {'is_blank': 1, 'is_comment': 0, 'is_def': 0, 'foldexpr': len(defs_stack)})
            continue
        endif

        let ind = s:indent(lines[lnum])

        " Comments
        if line =~# s:comment_regex
            call add(cache, {'is_blank': 0, 'is_comment': 1, 'is_def': 0, 'indent': ind})
            let defs = 0
            let defs_stack_len = len(defs_stack)
            for idx in range(defs_stack_len)
                if ind > cache[defs_stack[idx]]['indent']
                    let defs = defs_stack_len - idx
                    break
                endif
            endfor
            let cache[lnum]['foldexpr'] = defs
            call s:blanks_adj(cache, lnum, defs)
            continue
        endif

        call add(cache, {'is_blank': 0, 'is_comment': 0,
            \            'is_def': line =~# b:SimpylFold_def_regex, 'indent': ind})

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
            let defs = len(defs_stack) - 1
            let ind_def = ind
            call s:blanks_adj(cache, lnum, defs)
            let cache[lnum]['foldexpr'] = '>' . (defs + 1)
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
        let defs = len(defs_stack)

        " Docstrings
        if b:SimpylFold_fold_docstring
            if in_docstring
                if line =~# docstring_end_regex
                    let in_docstring = 0
                endif

                call s:blanks_adj(cache, lnum, defs + 1)
                let cache[lnum]['foldexpr'] = defs + 1
                continue
            else
                let lnum_prev = lnum - 1
                if !cache[lnum_prev]['is_blank'] && !cache[lnum_prev]['is_comment']
                    let docstring_match = matchlist(line, s:docstring_start_regex)
                    if !empty(docstring_match) &&
                            \ (cache[lnum_prev]['is_def'] ||
                            \  lines[lnum_prev] =~# s:multiline_def_end_regex)
                        let in_docstring = 1

                        if docstring_match[1] ==# '"""'
                            let docstring_end_regex = s:docstring_end_double_regex
                        else
                            let docstring_end_regex = s:docstring_end_single_regex
                        endif

                        let cache[lnum]['foldexpr'] = '>' . (defs + 1)
                        continue
                    endif
                endif
            endif
        endif

        " Imports
        if b:SimpylFold_fold_import
            if in_import
                if line =~# import_end_regex
                    let in_import = 0
                endif

                call s:blanks_adj(cache, lnum, defs + 1)
                let cache[lnum]['foldexpr'] = defs + 1
                continue
            elseif match(line, s:import_start_regex) != -1
                let import_cont_match = matchlist(line, s:import_cont_regex)
                if !empty(import_cont_match)
                    if import_cont_match[1] ==# '('
                        let import_end_regex = s:import_end_paren_regex
                        let in_import = 1
                    elseif import_cont_match[2] ==# '\'
                        let import_end_regex = s:import_end_esc_regex
                        let in_import = 1
                    endif
                endif

                if was_import
                    call s:blanks_adj(cache, lnum, defs + 1)
                    let cache[lnum]['foldexpr'] = defs + 1
                else
                    let cache[lnum]['foldexpr'] = '>' . (defs + 1)
                endif
                let was_import = 1
                continue
            else
                let was_import = 0
            endif
        endif

        " Otherwise, its fold level is equal to its number of parent definitions
        call s:blanks_adj(cache, lnum, defs)
        let cache[lnum]['foldexpr'] = defs
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
    let next = nextnonblank(v:foldstart + 1)
    let docstring = getline(next)
    if docstring =~# s:docstring_prefix_regex
        let quote_char = docstring[match(docstring, '["'']')]
        let docstring = substitute(docstring, s:docstring_prefix_regex, '', '')
        if docstring =~# s:blank_regex
            let docstring = substitute(getline(nextnonblank(next + 1)), '^\s*', '', '')
        endif
        let docstring = substitute(docstring, quote_char . '\{,3}$', '', '')
        return ' ' . docstring
    endif
    return ''
endfunction

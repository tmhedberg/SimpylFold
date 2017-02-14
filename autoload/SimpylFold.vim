let s:non_blank_regex = '^\s*[^[:space:]]'
let s:comment_regex = '^\s*#'
let s:multiline_def_end_regex = '):$'
let s:multiline_def_end_solo_regex = '^\s*):$'
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

" Construct a foldexpr value and cache it
function! s:foldexpr(cache_lnum, foldlevel, is_beginning) abort
    let a:cache_lnum['foldlevel'] = a:foldlevel
    if a:is_beginning
        let a:cache_lnum['foldexpr'] = '>' . a:foldlevel
    else
        let a:cache_lnum['foldexpr'] = a:foldlevel
    endif
endfunction

function! s:defs_stack_prune(cache, defs_stack, ind) abort
    for idx in range(len(a:defs_stack))
        let ind_stack = a:cache[a:defs_stack[idx]]['indent']
        if a:ind == ind_stack
            return a:defs_stack[(idx + 1):]
        elseif a:ind > ind_stack
            return a:defs_stack[(idx):]
        endif
    endfor
endfunction

" Create a new cache
function! s:cache() abort
    let cache = [{}]  " With padding for lnum offset
    let lines = getbufline(bufnr('%'), 1, '$')
    let lnum_last = len(lines)
    call insert(lines, '')  " Padding for lnum offset

    " Cache everything generic
    let non_blanks = []
    let defs_stack = []
    let ind_def = -1
    for lnum in range(1, lnum_last)
        let line = lines[lnum]
        if line =~# s:comment_regex
            let defs_stack_len = len(defs_stack)
            call add(cache, {'is_blank': 0, 'is_comment': 1, 'is_def': 0,
                \            'defs': defs_stack_len, 'foldexpr': defs_stack_len, 'foldlevel': defs_stack_len})
        elseif line !~# s:non_blank_regex
            let defs_stack_len = len(defs_stack)
            call add(cache, {'is_blank': 1, 'is_comment': 0, 'is_def': 0,
                \            'defs': defs_stack_len, 'foldexpr': defs_stack_len, 'foldlevel': defs_stack_len})
        else
            call add(non_blanks, lnum)
            let is_def = line =~# b:SimpylFold_def_regex
            let ind = s:indent(lines[lnum])
            call add(cache, {'is_blank': 0, 'is_comment': 0, 'is_def': is_def, 'indent': ind})

            if is_def
                if empty(defs_stack)
                    let defs_stack = [lnum]
                elseif ind > ind_def
                    call insert(defs_stack, lnum)
                elseif ind < ind_def
                    let defs_stack = [lnum] + s:defs_stack_prune(cache, defs_stack, ind)
                endif
                let cache[lnum]['defs'] = len(defs_stack) - 1
                let ind_def = ind
            else
                if !empty(defs_stack)
                    if ind == ind_def
                        let defs_stack = defs_stack[1:]
                        let ind_def = cache[defs_stack[0]]['indent']
                    elseif ind < ind_def
                        let defs_stack = s:defs_stack_prune(cache, defs_stack, ind)
                        let ind_def = cache[defs_stack[0]]['indent']
                    endif
                endif
                let cache[lnum]['defs'] = len(defs_stack)
            endif

            " Prevent adjacent blanks from merging into previous fold
            let lnum_prev = lnum - 1
            while lnum_prev != 0 && cache[lnum_prev]['is_blank']
                call s:foldexpr(cache[lnum_prev], cache[lnum]['defs'], 0)
                let lnum_prev -= 1
            endwhile
        endif
    endfor

    " Cache non-blanks
    let in_docstring = 0
    let in_import = 0
    for lnum in non_blanks
        let line = lines[lnum]

        " Docstrings
        if b:SimpylFold_fold_docstring
            if in_docstring
                if line =~# docstring_end_regex
                    let in_docstring = 0
                endif

                call s:foldexpr(cache[lnum], cache[lnum]['defs'] + 1, 0)
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

                        call s:foldexpr(cache[lnum], cache[lnum]['defs'] + 1, 1)
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

                call s:foldexpr(cache[lnum], cache[lnum]['defs'] + 1, 0)
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

                call s:foldexpr(cache[lnum], cache[lnum]['defs'] + 1, 0)
                continue
            endif
        endif

        " Otherwise, its fold level is equal to its number of containing
        " definitions, plus 1, if this line starts a definition of its own
        call s:foldexpr(cache[lnum], cache[lnum]['defs'] + cache[lnum]['is_def'], cache[lnum]['is_def'])
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
    let ds_prefix = '^\s*\%(\%(["'']\)\{3}\|[''"]\ze[^''"]\)'
    if docstring =~# ds_prefix
        let quote_char = docstring[match(docstring, '["'']')]
        let docstring = substitute(docstring, ds_prefix, '', '')
        if docstring !~# s:non_blank_regex
            let docstring =
                \ substitute(getline(nextnonblank(next + 1)), '^\s*', '', '')
        endif
        let docstring = substitute(docstring, quote_char . '\{,3}$', '', '')
        return ' ' . docstring
    endif
    return ''
endfunction

" vim_mcp/selection.vim - current visual selection + symbol under cursor

function! vim_mcp#selection#Get() abort
  let l:result = {'success': v:true}
  let l:result.word = expand('<cword>')
  let l:result.bigword = expand('<cWORD>')
  let l:result.cursor = [line('.'), col('.')]
  let l:result.bufnr = bufnr('%')
  let l:result.name = expand('%:p')

  let l:sline = line("'<")
  let l:eline = line("'>")
  if l:sline > 0 && l:eline > 0 && l:eline >= l:sline
    let l:scol = col("'<")
    let l:ecol = col("'>")
    let l:lines = getline(l:sline, l:eline)
    if !empty(l:lines)
      if len(l:lines) == 1
        let l:lines[0] = strpart(l:lines[0], l:scol - 1, l:ecol - l:scol + 1)
      else
        let l:lines[0] = strpart(l:lines[0], l:scol - 1)
        let l:lines[-1] = strpart(l:lines[-1], 0, l:ecol)
      endif
    endif
    let l:result.selection = {'start_line': l:sline, 'end_line': l:eline,
          \ 'text': join(l:lines, "\n")}
  else
    let l:result.selection = v:null
  endif
  return l:result
endfunction

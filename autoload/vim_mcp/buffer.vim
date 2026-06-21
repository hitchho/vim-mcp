" vim_mcp/buffer.vim - read live buffer content (includes unsaved edits)

function! vim_mcp#buffer#GetContent(params) abort
  let l:p = a:params
  let l:bufnr = get(l:p, 'bufnr', 0)
  if l:bufnr == 0 | let l:bufnr = bufnr('%') | endif
  if !bufexists(l:bufnr)
    return {'success': v:false, 'error': 'buffer ' . l:bufnr . ' does not exist'}
  endif
  let l:total = len(getbufline(l:bufnr, 1, '$'))
  let l:start = get(l:p, 'start', 1)
  let l:end = get(l:p, 'end', l:total)
  if l:start < 1 | let l:start = 1 | endif
  if l:end < 0 || l:end > l:total | let l:end = l:total | endif
  let l:lines = getbufline(l:bufnr, l:start, l:end)
  if get(l:p, 'line_numbers', 1)
    let l:out = []
    let l:n = l:start
    for l:line in l:lines
      call add(l:out, l:n . "\t" . l:line)
      let l:n += 1
    endfor
    let l:lines = l:out
  endif
  return {'success': v:true, 'bufnr': l:bufnr, 'name': bufname(l:bufnr),
        \ 'start': l:start, 'end': l:end, 'total': l:total,
        \ 'modified': getbufvar(l:bufnr, '&modified'),
        \ 'text': join(l:lines, "\n")}
endfunction

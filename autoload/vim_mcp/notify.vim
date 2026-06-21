" vim_mcp/notify.vim - surface a message in Vim (HUD feedback / safety beat)

function! vim_mcp#notify#Notify(params) abort
  let l:msg = get(a:params, 'message', '')
  let l:level = get(a:params, 'level', 'info')
  let l:hl = {'info': 'MoreMsg', 'warn': 'WarningMsg', 'error': 'ErrorMsg', 'success': 'MoreMsg'}
  let l:group = get(l:hl, l:level, 'MoreMsg')
  if has('nvim')
    let l:lvl = {'info': 2, 'warn': 3, 'error': 4, 'success': 2}
    call luaeval('vim.notify(_A[1], _A[2])', [l:msg, get(l:lvl, l:level, 2)])
  endif
  execute 'echohl ' . l:group
  echom '[claude] ' . l:msg
  echohl None
  return {'success': v:true, 'shown': l:msg}
endfunction

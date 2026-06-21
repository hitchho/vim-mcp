" vim_mcp/lsp.vim - bridge to the Lua LSP helpers (Neovim only)

function! vim_mcp#lsp#Action(params) abort
  if !has('nvim')
    return {'success': v:false, 'error': 'LSP tools require Neovim'}
  endif
  try
    return luaeval('require("vim_mcp_lsp").action(_A)', a:params)
  catch
    return {'success': v:false, 'error': 'lsp bridge error: ' . v:exception}
  endtry
endfunction

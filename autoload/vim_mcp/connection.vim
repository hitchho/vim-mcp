" vim_mcp/connection.vim - Server connection management (Vim + Neovim)

" Connection state
let s:channel = v:null
let s:connected = 0
let s:connection_timer = v:null
let s:instance_id = ''
let s:message_handler = v:null
let s:mcp_socket_path = get(g:, 'vim_mcp_socket_path', '/tmp/vim-mcp-server.sock')
let s:reconnect_interval = get(g:, 'vim_mcp_reconnect_interval', 5000)
let s:is_nvim = has('nvim')
let s:nvim_open = 0
let s:nvim_partial = ''

" --- public state accessors ---------------------------------------------------
function! vim_mcp#connection#IsConnected()
  return s:connected
endfunction

function! vim_mcp#connection#GetChannel()
  return s:channel
endfunction

function! vim_mcp#connection#GetInstanceID()
  return s:instance_id
endfunction

function! vim_mcp#connection#SetMessageHandler(handler)
  let s:message_handler = a:handler
endfunction

" --- channel abstraction (Vim ch_* vs Neovim sockconnect/chansend) -----------
function! s:ChannelIsOpen() abort
  if s:channel is v:null
    return 0
  endif
  return s:is_nvim ? s:nvim_open : (ch_status(s:channel) ==# 'open')
endfunction

function! s:ChannelSendRaw(text) abort
  if s:is_nvim
    call chansend(s:channel, a:text)
  else
    call ch_sendraw(s:channel, a:text)
  endif
endfunction

function! s:ChannelClose() abort
  if s:channel is v:null
    return
  endif
  try
    if s:is_nvim
      call chanclose(s:channel)
    else
      call ch_close(s:channel)
    endif
  catch
    " ignore close errors
  endtry
endfunction

" Try to open the channel. Returns 1 on success, 0/throw on failure.
function! s:ChannelTryOpen() abort
  if s:is_nvim
    let s:nvim_partial = ''
    let l:chan = sockconnect('pipe', s:mcp_socket_path, {'on_data': function('s:NvimOnData')})
    if l:chan > 0
      let s:channel = l:chan
      let s:nvim_open = 1
      return 1
    endif
    return 0
  endif
  let s:channel = ch_open('unix:' . s:mcp_socket_path, {
        \ 'mode': 'raw',
        \ 'callback': function('s:HandleMessage'),
        \ 'close_cb': function('s:HandleClose')
        \ })
  return ch_status(s:channel) ==# 'open'
endfunction

" Neovim raw stream: reassemble newline-delimited frames (first/last items
" of each chunk may be partial lines; a lone [''] signals EOF).
function! s:NvimOnData(chan, data, name) abort
  if a:data ==# ['']
    call s:HandleClose(a:chan)
    return
  endif
  let l:data = copy(a:data)
  let l:data[0] = s:nvim_partial . l:data[0]
  let s:nvim_partial = remove(l:data, len(l:data) - 1)
  for l:line in l:data
    if l:line !=# ''
      call s:HandleMessage(a:chan, l:line)
    endif
  endfor
endfunction

" --- message plumbing --------------------------------------------------------
function! s:HandleMessage(channel, msg)
  if s:message_handler != v:null
    call s:message_handler(a:channel, a:msg)
  endif
endfunction

function! vim_mcp#connection#SendMessage(msg)
  if s:ChannelIsOpen()
    try
      call s:ChannelSendRaw(json_encode(a:msg) . "\n")
    catch
      echohl ErrorMsg | echo 'vim-mcp: Error sending message: ' . v:exception | echohl None
    endtry
  endif
endfunction

function! s:HandleClose(channel)
  call vim_mcp#utils#DebugLog('Disconnected from server')
  let s:connected = 0
  let s:nvim_open = 0
  let s:channel = v:null
  call s:StartConnectionTimer()
endfunction

" --- retry timer -------------------------------------------------------------
function! s:StartConnectionTimer()
  if s:connection_timer != v:null
    " Timer already running
    return
  endif
  if has('timers')
    let s:connection_timer = timer_start(s:reconnect_interval, function('s:AttemptReconnect'), {'repeat': -1})
  endif
endfunction

function! s:StopConnectionTimer()
  if s:connection_timer != v:null && has('timers')
    call timer_stop(s:connection_timer)
    let s:connection_timer = v:null
  endif
endfunction

function! s:AttemptReconnect(timer)
  if s:connected
    call s:StopConnectionTimer()
    return
  endif
  call s:DoConnect(1)
endfunction

" --- connect / disconnect ----------------------------------------------------
function! s:Register() abort
  let l:msg = {
        \ 'type': 'register',
        \ 'instance_id': s:instance_id,
        \ 'info': {
        \   'pid': getpid(),
        \   'cwd': getcwd(),
        \   'main_file': expand('%:p'),
        \   'buffers': vim_mcp#utils#GetBufferList(),
        \   'version': v:version
        \ }
        \ }
  call vim_mcp#connection#SendMessage(l:msg)
endfunction

function! s:DoConnect(silent) abort
  if s:ChannelIsOpen()
    return
  endif
  if empty(s:instance_id)
    let s:instance_id = vim_mcp#utils#GenerateInstanceID()
  endif
  try
    if s:ChannelTryOpen()
      call s:StopConnectionTimer()
      call s:Register()
      call vim_mcp#utils#DebugLog('Connected to server at ' . s:mcp_socket_path)
    else
      throw 'channel not open'
    endif
  catch
    let s:channel = v:null
    let s:nvim_open = 0
    let s:connected = 0
    if !a:silent && s:connection_timer is v:null
      call vim_mcp#utils#DebugLog('MCP server not available, retrying every ' . (s:reconnect_interval / 1000) . 's')
    endif
    call s:StartConnectionTimer()
  endtry
endfunction

function! vim_mcp#connection#Connect()
  call s:DoConnect(0)
endfunction

function! vim_mcp#connection#Disconnect()
  call s:StopConnectionTimer()
  call s:ChannelClose()
  let s:channel = v:null
  let s:nvim_open = 0
  let s:connected = 0
endfunction

" Called by the main module when the server confirms registration.
function! vim_mcp#connection#MarkConnected(instance_id)
  let s:connected = 1
  if !empty(a:instance_id)
    let s:instance_id = a:instance_id
  endif
endfunction

" Launch MPV using a Unix socket for IPC.
"
" We'll defer the creation of a Vim channel, so that we don't have to wait for
" MPV to set up the socket. Deferring comes with added resilience in case MPV
" or its socket close. See s:Guard.
function! srtedit#Start(video_path)
	if &filetype != 'srt'
		throw 'Must be run on an SRT file'
	endif

	silent let s:socket = trim(system('mktemp /tmp/vim-mpv-socket-XX'))
	if v:shell_error != 0
		throw 'Could not create socket'
	endif

	autocmd VimLeavePre * call s:DeleteSocket(0, 0)

	call job_start(['mpv',
				\ '--input-ipc-server=' . fnameescape(s:socket),
				\ '--sub-file=' . fnameescape(expand('%')),
				\ '--osd-level=2',
				\ fnameescape(a:video_path)
				\ ],
				\ { 'out_io': 'null', 'err_io': 'out', 'exit_cb': 's:DeleteSocket' })
endfunction

" Called when either Vim quits or when the channel closes, e.g. if MPV quits.
function! s:DeleteSocket(ch, status)
	if exists('s:socket')
		call delete(s:socket)
	endif
endfunction

" Ensure we have a working channel to talk to MPV. Used by s:Send and s:Get.
function! s:Guard()
	if !exists('s:channel') || empty(s:channel)
		try
			let s:channel = ch_open('unix:' . fnameescape(s:socket), {'mode':'raw'})
		catch /Connection refused/
			throw 'MPV socket not available. Try SrtStart'
		endtry
	endif
	if ch_status(s:channel) != 'open'
		throw 'Channel not open'
	endif
endfunction

" Send a command to MPV
function! s:Send(cmd)
	call s:Guard()
	let msg = json_encode({'command': a:cmd})
	echo ch_sendraw(s:channel, msg . "\n")
endfunction

" Query MPV for a property
function! s:Get(property)
	call s:Guard()
	let msg = json_encode({'command': ['get_property', a:property]})
	let resp = ch_evalraw(s:channel, msg . "\n")
	let resp = json_decode(resp)
	if resp['error'] == 'success'
		return resp['data']
	endif
endfunction

" Convert a duration in milliseconds to a timecode string
function! s:ToTimestamp(time)
	let time = float2nr(a:time)
	let ms = time % 1000
	let s = time / 1000
	let m = s / 60
	let s = s % 60
	let h = m / 60
	let m = m % 60
	return printf('%02d:%02d:%02d,%03d', h, m, s, ms)
endfunction

" Convert a timecode string to a duration in milliseconds
function! s:ToMilliseconds(timestamp)
  let match = matchlist(a:timestamp, '\v^(\d{2}):(\d{2}):(\d{2}),(\d{3})$')
  if empty(match)
    throw 'Invalid timestamp format'
  endif

  let hours = str2nr(match[1])
  let minutes = str2nr(match[2])
  let seconds = str2nr(match[3])
  let ms = str2nr(match[4])

  return hours * 3600000 + minutes * 60000 + seconds * 1000 + ms
endfunction

" Pause or resume MPV playback
function! srtedit#Pause()
	call s:Send(["cycle", "pause"])
endfunction

" Rewind MPV playback by 2 seconds
function! srtedit#Rewind()
	call s:Send(["seek", -2])
endfunction

" Fast-forward MPV playback by 2 seconds
function! srtedit#Forward()
	call s:Send(["seek", 2])
endfunction

" Make MPV jump to the time position corresponding to the current record.
function! srtedit#Jump()
	" Reload subs
	execute 'silent update'
	call s:Send(["sub-clear"])
	call s:Send(["sub-add", bufname()])

	" Jump to record's timestamp
	let pos = getpos('.')
	call search('\v^$', 'b')
	call search('\v\d{2}:')

	" Bail if not the right place
	let line = getline(".")
	if line !~ '\v^(\d{2}):(\d{2}):(\d{2}),(\d{3})'
		return
	endif

	" Grab time, seek to it
	let start_time = matchstr(line, '\v^(\d{2}):(\d{2}):(\d{2})')
	call s:Send(["cycle", "play"]) " FIXME: why is this ignored?
	call s:Send(["seek", start_time, "absolute"])

	" Restore position
	call setpos('.', pos)
endfunction

" Increment or decrement the current timestamp by 'count' milliseconds.
function! srtedit#Increment(count=100)
	let ms = s:ToMilliseconds(expand("<cWORD>"))
	let ts = s:ToTimestamp((ms + a:count))
	execute 'normal ciW' . ts
endfunction

" Reindex all records in the buffer, starting at 1.
function! srtedit#Index()
	let pat_index = '\v^\d+$'
	let pat_timecodes = '\v^\d{2}:\d{2}:\d{2},\d{3} --\> \d{2}:\d{2}:\d{2},\d{3}$'
	let i = 1
	for match in matchbufline('%', pat_index, 1, '$')
		let prev = getline(match['lnum'] - 1)
		let next = getline(match['lnum'] + 1)
		if prev == '' && next =~ pat_timecodes
			call setline(match['lnum'], i)
			let i = i + 1
		endif
	endfor
endfunction

" Add a new subtitle record using MPV's current time position.
"
" The first invocation, which should happen on an empty line, creates a
" partial record consisting of a dummy ID (0) and the start timecode (from
" MPV). The second invocation, which should happen where the first invocation
" left off, will append the end timecode (also from MPV) to the record.
"
" What this doesn't do: sort the record chronologically, nor reindex the
" record. The user should move along the buffer to where the new record ought
" to be inserted; the role of this function is to quickly and accurately
" capture MPV's timecodes.
function! srtedit#Add()
	let line = getline('.')
	let time = s:ToTimestamp(s:Get('time-pos') * 1000)

	" Insert new record in place
	if line =~ '^$'
		call append('.', ['0', printf('%s --> ', time), '', ''])
		+2

	" Finish record timestamp
	elseif line =~ '\v(\d{2}):(\d{2}):(\d{2}),(\d{3}) --\> $'
		call setline(line('.'), line . time)
		+1

	" Append new record after current record
	else
		call search('\v^$')
		call append('.', ['0', printf('%s --> ', time), '', ''])
		+2

	endif
endfunction

srt-edit
========

Turn Vim into a lightweight subtitle ([SubRip](https://en.wikipedia.org/wiki/SubRip)) editor:

* Uses [MPV](https://mpv.io/) to preview video and subtitles
* Provides commands and bindings to:
    * jump in the video feed to the selected subtitle
    * synchronise new subtitles with the video feed
    * quickly pause, rewind or fast-forward without leaving Vim
    * re-index all subtitles from 1 onwards

_This is a very early version. More documentation or features to come._

Installation
------------

1. Install [MPV](https://mpv.io/)
2. Using Vim's built-in package support:

```
mkdir -p ~/.vim/pack/mcsf/start
cd ~/.vim/pack/mcsf/start
git clone https://github.com/mcsf/srtedit.vim.git
```

Usage
-----

* Open a `*.srt` subtitle file
* Run `:SrtEditStart some-video.mp4`
* Navigate through the subtitles as through any text file
* Place the cursor over a subtitle and press `<leader><cr>` to jump in the video feed to that subtitle, for example
    * If you haven't configured your `<leader>` key, set it in `~.vimrc` with `let mapleader = " "`
* See all bindings in `ftplugin/srt.vim`

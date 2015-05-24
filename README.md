SimpylFold
==========

Because of its reliance on significant whitespace rather than explicit block delimiters, properly folding Python code can be tricky. The Python syntax definition that comes bundled with Vim doesn't contain any fold directives at all, and the simplest workaround is to `:set foldmethod=indent`, which usually ends up folding a lot more than you really want it to.

There's no shortage of Vim plugins for improved Python folding, but most seem to suffer from cobbled-together algorithms with bizarre, intractable bugs in the corner cases. SimpylFold aims to be exactly what its name suggests: simple, correct folding for Python. It's nothing more than it needs to be: it properly folds class and function/method definitions, and leaves your loops and conditional blocks untouched. There's no BS involved: no screwing around with unrelated options (which several of the other plugins do), no choice of algorithms to scratch your head over (because there's only one that's correct); it just works, simply.

Installation
------------

### Pathogen

If you're using [Pathogen](https://github.com/tpope/vim-pathogen) and Git to manage your Vim plugins (highly recommended), you can just

    cd ~/.vim
    git submodule add https://github.com/tmhedberg/SimpylFold.git bundle/SimpylFold
    git submodule init

and you're good to go. 

### Vundle

If you use [Vundle](https://github.com/gmarik/Vundle.vim) then put in your `.vimrc`:

    Plugin 'tmhedberg/SimpylFold'

and then launch `vim` and run `:PluginInstall`.
    
### NeoBundle

If you use [NeoBundle](https://github.com/Shougo/neobundle.vim) then put in your `.vimrc`:

    NeoBundle 'tmhedberg/SimpylFold'

and then launch `vim` and run `:NeoBundleInstall`.

### Manually

If you insist on doing this manually, then just clone this repo somewhere or just grab the tarball, and drop the plugin file into your `~/.vim/ftplugin/python`.

Configuration
-------------

No configuration is necessary. However, if you want to enable previewing of your folded classes' and functions' docstrings in the fold text, add the following to your .vimrc:

    let g:SimpylFold_docstring_preview = 1

And if you don't want to see your docstrings folded, add this:

    let g:SimpylFold_fold_docstring = 0

In order for SimpylFold to be properly loaded in certain cases, you'll have to add lines like the following to your `.vimrc` (see issue #27):

```vim
autocmd BufWinEnter *.py setlocal foldexpr=SimpylFold(v:lnum) foldmethod=expr
autocmd BufWinLeave *.py setlocal foldexpr< foldmethod<
```

If you have the above options set to different values anywhere (e.g. setting `foldmethod=syntax` in `.vimrc`, SimpylFold won't work properly.

Bugs
----

If you find any bugs, please report them and/or submit pull requests on Github! Simple is nice, but simple and correct is much better.

Happy hacking!

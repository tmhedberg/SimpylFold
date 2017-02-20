SimpylFold
==========

Because of its reliance on significant whitespace rather than explicit block
delimiters, properly folding Python code can be tricky. The Python syntax
definition that comes bundled with Vim doesn't contain any fold directives at
all, and the simplest workaround is to `set foldmethod=indent`, which usually
ends up folding a lot more than you really want it to.

There's no shortage of Vim plugins for improved Python folding, but most seem
to suffer from cobbled-together algorithms with bizarre, intractable bugs
in the corner cases.  SimpylFold aims to be exactly what its name suggests:
simple, correct folding for Python.

It's nothing more than it needs to be: it properly folds class and
function/method definitions, and leaves your loops and conditional blocks
untouched. There's no BS involved: no screwing around with unrelated options
(which several of the other plugins do), no choice of algorithms to scratch
your head over (there's only one that's correct); it just works, simply.

Installation
------------

Use one of the following plugin managers:

* [dein](https://github.com/Shougo/dein.vim)
* [vim-plug](https://github.com/junegunn/vim-plug)
* [vundle](https://github.com/VundleVim/Vundle.vim)
* [pathogen](https://github.com/tpope/vim-pathogen)

Also strongly recommend using [FastFold](https://github.com/Konfekt/FastFold)
due to Vim's folding being extremely slow by default.

Configuration
-------------

No configuration is necessary. However, there are a few configurable options.

### Option variables

Set variable to `1` to enable or `0` to disable.

For example to enable docstring preview in fold text you can add the
following command to your `~/.config/nvim/init.vim` or `~/.vimrc`:
```vim
let g:SimpylFold_docstring_preview = 1
```
| Variable                         | Description                    | Default |
| -------------------------------- | ------------------------------ | ------- |
| `g:SimpylFold_docstring_preview` | Preview docstring in fold text | `0`     |
| `g:SimpylFold_fold_docstring`    | Fold docstrings                | `1`     |
| `b:SimpylFold_fold_docstring`    | Fold docstrings (buffer local) | `1`     |
| `g:SimpylFold_fold_import`       | Fold imports                   | `1`     |
| `b:SimpylFold_fold_import`       | Fold imports (buffer local)    | `1`     |

### Commands

There are also a few buffer local commands for fast toggling:

| Command                 | Description               |
| ----------------------- | ------------------------- |
| `SimpylFoldDocstrings`  | Enable docstring folding  |
| `SimpylFoldDocstrings!` | Disable docstring folding |
| `SimpylFoldImports`     | Enable import folding     |
| `SimpylFoldImports!`    | Disable import folding    |

Usage
-----

Use Vim's built-in folding commands to expand and collapse folds.
The most basic commands are `zc` to close a fold and `zo` to open one.
See `:help fold-commands` for full documentation.

Bugs
----

If you find any bugs, please report them and submit pull requests on GitHub!
Simple is nice, but simple and correct is much better.

Happy hacking!

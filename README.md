# npm_scripts.nvim

Run [npm scripts](https://docs.npmjs.com/cli/v8/using-npm/scripts) from the comfort of your favorite editor.

Features:

- Workspace support
- Run a script from the current buffer's project(monorepo)
- Uses `vim.ui.select()` for a picker which makes it easy to seamlessly integrate with your setup(telescope/fzf or anything else), see [`opts.select`](#opts.select)

## Install

```vim
" using vim-plug
Plug 'antonk52/npm_scripts.nvim'
```

```lua
-- using packer.nvim
use {'antonk52/npm_scripts.nvim'}
```

## Setup

```lua
-- optional
-- call this if you want to override global plugin options
require'npm_scripts'.setup(opts)
```

## API

- `require'npm_scripts'.run_script()` to run a script from a root `package.json`
- `require'npm_scripts'.run_workspace_script()` to pick a workspace and script to run
- `require'npm_scripts'.run_buffer_workspace_script()` infers a workspace from a current buffer and runs a script

### opts.select

Function. By default set to `vim.ui.select`. You can provide a custom function with the same signature(see `:help vim.ui.select`) or use a 3rd party solution like [`stevearc/dressing.nvim`](https://github.com/stevearc/dressing.nvim) for [`telescope`](https://github.com/nvim-telescope/telescope.nvim), [`fzf`](https://github.com/junegunn/fzf), [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) support, or [`telescope-ui-select.nvim`](https://github.com/nvim-telescope/telescope-ui-select.nvim) to override global `vim.ui.select` and have your favorite picker everywhere.

### opts.package_manager

String. Pick a package manager to use to run scripts. `npm` by default.

### opts.run_script

Function. Takes a table `run_opts` with fields `script_name`, `path`, and `package_manager`. It is called after a user selects a script to run. By default opens a terminal in a split and runs the selected script there.

### opts.select_script_prompt

String. Default `"Select a script to run:"`

### opts.select_script_format_item

Function. Default `tostring`

### opts.select_workspace_prompt

String. Default `"Select a workspace to run a script:"`

### opts.select_workspace_format_item

Function. Default `tostring`

## TODO

- [x] run any npm scripts
- [x] overridable optsions for vim.ui.select
- [x] workspace picker support
- [x] buffer workspace picker support
- [x] global options setup
- [x] local options
- [x] fzf integration readme example
- [ ] vim docs
- [ ] tmux run_script example
- [ ] `quiet` option ie run script in background

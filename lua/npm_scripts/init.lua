---@class NpmScripts.PackageJson
---@field json table<string, string|table<string,string>>
---@field filepath string

---@alias NpmScripts.PackageManager 'npm' | 'yarn' | 'pnpm' | 'bun'

---@class NpmScripts.RunScriptOpts
---@field name string script name from package json
---@field path string cwd for command to execute
---@field package_manager NpmScripts.PackageManager the binary to run the script


local GLOBAL_OPTIONS = {}
local M = {}

local uv = vim.uv or vim.loop

---Override default plugin options
---@param opts NpmScripts.PluginOptions
---@return nil
function M.setup(opts)
    for k, v in pairs(opts) do
        GLOBAL_OPTIONS[k] = v
    end
end

local utils = {}
---Infer options
---@param local_options NpmScripts.PluginOptions
---@return NpmScripts.PluginOptions
function utils.get_opts(local_options)
    ---@class NpmScripts.PluginOptions
    local DEFAULT_OPTIONS = {
        select = vim.ui.select,

        select_script_prompt = 'Select a script to run:',
        select_script_format_item = tostring,

        select_workspace_prompt = 'Select a workspace to run a script:',
        select_workspace_format_item = tostring,

        ---@type NpmScripts.PackageManager
        package_manager = local_options.package_manager or utils.infer_package_manager(),

        -- whether to pick a workspace script via a single search
        -- or two searches, over workspaces and picked workspace scripts
        workspace_script_solo_picker = true,
        ---@type fun(opts: NpmScripts.RunScriptOpts): nil
        run_script = function(opts)
            local cmd = string.format('cd %s && %s run %s', opts.path, opts.package_manager, opts.name)
            if vim.g.vscode ~= nil then
                local code = require('vscode')
                code.call('workbench.action.terminal.new')
                code.call('workbench.action.terminal.sendSequence', {
                    args = { text = cmd .. '\n' }
                })
                return
            else
                vim.cmd('tabnew | term ' .. cmd)
                -- rename buffer, ensuring uniqueness
                local base_name = opts.package_manager .. ':' .. opts.name
                local final_name = base_name
                local i = 2
                while vim.fn.bufexists(final_name) == 1 do
                    final_name = base_name .. '_' .. i
                    i = i + 1
                end
                vim.cmd.file(final_name)
            end
        end,
    }
    local result = {}
    for _, opts in ipairs({ DEFAULT_OPTIONS, GLOBAL_OPTIONS, local_options }) do
        for k, v in pairs(opts) do
            result[k] = v
        end
    end

    return result
end

---Get current buffer's closest directory
---@return string
function utils.buffer_cwd()
    local buf_path = vim.api.nvim_buf_get_name(0)
    if vim.fn.isdirectory(buf_path) == 1 then
        return buf_path
    end
    return vim.fs.dirname(buf_path)
end
---@return NpmScripts.PackageJson?
function utils.get_root_package_json()
    local filepath = vim.fn.getcwd() .. '/package.json'

    if vim.fn.filereadable(filepath) == 0 then
        return nil
    end

    local lines = vim.fn.readfile(filepath)
    local content = table.concat(lines, '')
    return {
        filepath = filepath,
        json = vim.json.decode(content),
    }
end
---@return NpmScripts.PackageJson?
function utils.get_closest_package_json()
    local file = vim.fs.find(
        { 'package.json'},
        { upward = true, type = 'file', stop = vim.fs.dirname(vim.env.HOME), limit = 1, path = utils.buffer_cwd() }
    )[1]
    if file then
        local lines = vim.fn.readfile(file)
        return {
            filepath = file,
            json = vim.json.decode(table.concat(lines, '')),
        }
    end
end

---@return 'npm' | 'yarn' | 'pnpm' | 'bun'
function utils.infer_package_manager()
    local lock_file_to_manager = {
        ['package-lock.json'] = 'npm',
        ['yarn.lock'] = 'yarn',
        ['pnpm-lock.yaml'] = 'pnpm',
        ['bun.lock'] = 'bun',
    }
    local lock_file = vim.fs.find(
        vim.tbl_keys(lock_file_to_manager),
        {
            upward = true,
            type = 'file',
            stop = vim.fs.dirname(vim.env.HOME),
            limit = 1,
            path = utils.buffer_cwd(),
        }
    )[1]
    if lock_file then
        return lock_file_to_manager[vim.fs.basename(lock_file)]
    end

    return 'npm'
end

---Run a script from project's package.json
---@param opts NpmScripts.PluginOptions|nil
---@return nil
function M.run_script(opts)
    opts = utils.get_opts(opts or {})

    local config = utils.get_root_package_json()
    if config == nil then
        return vim.notify('Could not locate package.json', vim.log.levels.WARN)
    end
    if config.json.scripts == nil then
        return vim.notify('No "scripts" in package.json', vim.log.levels.WARN)
    end

    local script_names = vim.fn.keys(config.json.scripts)

    if #script_names == 0 then
        return vim.notify('Empty "scripts" in package.json', vim.log.levels.WARN)
    end

    opts.select(script_names, {
        prompt = opts.select_script_prompt,
        kind = 'string',
        format_item = opts.select_script_format_item,
    }, function(name)
        opts.run_script({
            name = name,
            path = vim.fn.getcwd(),
            package_manager = opts.package_manager,
        })
    end)
end

---Run a script from a specific workspace
---@param opts NpmScripts.PluginOptions?
---@return nil
function M.run_workspace_script(opts)
    opts = utils.get_opts(opts or {})

    local root_config = utils.get_root_package_json()
    if root_config == nil then
        return vim.notify('Could not locate package.json', vim.log.levels.WARN)
    end

    if root_config.json.workspaces == nil then
        return vim.notify('No "workspaces" in package.json', vim.log.levels.WARN)
    end

    -- { [name] = {filepath, json} }
    ---@type table<string, NpmScripts.PackageJson>
    local workspaces = {}

    local raw_root_workspaces = root_config.json.workspaces
    if type(raw_root_workspaces) == 'table' then
        for _, glob in pairs(raw_root_workspaces) do
            local items = vim.split(vim.fn.glob(glob), '\n')

            for _, item in ipairs(items) do
                local package_json_filepath = item .. '/package.json'

                if item ~= '' and vim.fn.filereadable(package_json_filepath) == 1 then
                    local workspace_json_lines = vim.fn.readfile(package_json_filepath)
                    local workspace_json = vim.json.decode(table.concat(workspace_json_lines, ''))

                    workspaces[workspace_json.name] = {
                        filepath = item,
                        json = workspace_json,
                    }
                end
            end
        end
    end

    if opts.workspace_script_solo_picker then
        local items = {}
        for workspace_name, w in pairs(workspaces) do
            local scripts = w.json.scripts or {}
            if type(scripts) == 'table' then
                for script_name, _ in pairs(scripts) do
                    table.insert(items, workspace_name .. '  ' .. script_name)
                end
            end
        end

        opts.select(items, {
            prompt = opts.select_script_prompt,
        }, function(picked)
            local parsed_picked = vim.split(picked, '  ')
            local workspace_name = parsed_picked[1]
            local script_name = parsed_picked[2]
            opts.run_script({
                name = script_name,
                path = workspaces[workspace_name].filepath,
                package_manager = opts.package_manager,
            })
        end)
    else
        opts.select(vim.fn.keys(workspaces), {
            prompt = opts.select_workspace_prompt,
            kind = 'string',
            format_item = opts.select_workspace_format_item,
        }, function(workspace_name)
            local workspace_scripts = workspaces[workspace_name].json.scripts

            if workspace_scripts == nil or vim.tbl_isempty(workspace_scripts) then
                return vim.notify('No "scripts" in workspace package.json', vim.log.levels.WARN)
            end

            opts.select(vim.fn.keys(workspace_scripts), {
                prompt = opts.select_script_prompt,
                kind = 'string',
                format_item = opts.select_script_format_item,
            }, function(name)
                opts.run_script({
                    name = name,
                    path = workspaces[workspace_name].filepath,
                    package_manager = opts.package_manager,
                })
            end)
        end)
    end
end

---Run a script from current buffer's package
---@param opts NpmScripts.PluginOptions|nil
---@return nil
function M.run_buffer_script(opts)
    opts = utils.get_opts(opts or {})

    local config = utils.get_closest_package_json()

    if not config then
        return vim.notify('Could not locate package.json', vim.log.levels.WARN)
    end

    if not config.json.scripts then
        return vim.notify('package.json does not have "scripts"', vim.log.levels.WARN)
    end

    opts.select(vim.fn.keys(config.json.scripts), {
        prompt = opts.select_script_prompt,
        kind = 'string',
        format_item = function(script)
            return script .. '\t"' .. config.json.scripts[script] .. '"'
        end,
    }, function(name)
        opts.run_script({
            name = name,
            path = vim.fs.dirname(config.filepath),
            package_manager = opts.package_manager,
        })
    end)
end

-- Traverses fs from cwd to find package.json files excluding node_modules
---@return string[]
local function find_package_jsons_with_uv()
    local package_jsons = {}
    local cwd = uv.cwd() or vim.fn.getcwd()
    local function search_recursively(path)
        ---@diagnostic disable-next-line: param-type-mismatch
        local dir = uv.fs_opendir(path, nil, 10000)
        if not dir then
            return
        end
        local items = uv.fs_readdir(dir)
        uv.fs_closedir(dir)
        if not items then
            return
        end
        for _, item in ipairs(items) do
            if item.name ~= 'node_modules' then
                local abs_path = path .. '/' .. item.name
                local stat = uv.fs_stat(abs_path)
                if stat then
                    if stat.type == 'directory' then
                        search_recursively(abs_path)
                    elseif stat.type == 'file' and item.name == 'package.json' then
                        table.insert(package_jsons, abs_path)
                    end
                end
            end
        end
    end
    search_recursively(cwd)
    return package_jsons
end

---@return string[]
local function find_package_jsons_with_fd()
    local cwd = uv.cwd() or vim.fn.getcwd()
    local command = {'fd', '--glob', 'package.json', '--type', 'f', '--exclude', 'node_modules', '--color', 'never'}
    local obj = vim.system(command, {text = true, cwd = cwd}):wait()

    assert(obj.code == 0, 'fd failed with code ' .. obj.code)

    local out = vim.trim(obj.stdout)
    return out == '' and {} or vim.split(out, '\n')
end

local function read_file_lines(filepath, cb)
    uv.fs_open(filepath, 'r', 438, function(fd_err, fd)
        if fd_err or not fd then
            return cb(nil, filepath)
        end
        uv.fs_fstat(fd, function(stat_err, stat)
            if stat_err or not stat then
                return cb(nil, filepath)
            end
            uv.fs_read(fd, stat.size, 0, function(read_err, content)
                if read_err or not content then
                    return cb(nil, filepath)
                end

                cb(content, filepath)

                uv.fs_close(fd)
            end)
        end)
    end)
end

---Find all package.json files from cwd and select a script across all of them
---@param opts NpmScripts.PluginOptions|nil
---@return nil
function M.run_from_all(opts)
    opts = utils.get_opts(opts or {})

    local filepaths = {}
    if vim.fn.executable('fd') == 1 then
        filepaths = find_package_jsons_with_fd()
    else
        filepaths = find_package_jsons_with_uv()
    end

    if #filepaths == 0 then
        return vim.notify('No package.json files found', vim.log.levels.WARN)
    end

    ---@type string[]
    local failed_to_parse = {}
    ---@type {filepath: string, name: string, scripts: table}[]
    local package_jsons = {}

    local function select_script()
        if #failed_to_parse > 0 then
            vim.notify(
                'Failed to parse package.json files: ' .. table.concat(failed_to_parse, '; '),
                vim.log.levels.WARN
            )
        end

        local flatten_scripts = {}
        for _, package_json in ipairs(package_jsons) do
            local scripts = (package_json or {}).scripts or {}
            for script_name, script in pairs(scripts) do
                local label = package_json.name .. ': ' .. script_name
                local script_obj = {
                    label = label,
                    script_name = script_name,
                    script_value = script,
                    path = vim.fs.dirname(package_json.filepath),
                }
                table.insert(flatten_scripts, script_obj)
            end
        end

        opts.select(flatten_scripts, {
            prompt = opts.select_script_prompt,
            kind = 'string',
            format_item = function(script)
                return script.label
            end,
        }, function(script)
            if script == nil then
                return vim.notify('No script selected', vim.log.levels.INFO)
            end
            opts.run_script({
                name = script.script_name,
                path = script.path,
                package_manager = opts.package_manager,
            })
        end)
    end

    local function file_read_callback(content, filepath)
        if not content then
            table.insert(failed_to_parse, filepath)
        else
            local success, result = pcall(vim.json.decode, content)
            if success then
                table.insert(package_jsons, {
                    filepath = filepath,
                    name = result.name or 'unknown',
                    scripts = result.scripts or {},
                })
            else
                table.insert(failed_to_parse, filepath)
            end
        end

        if (#package_jsons + #failed_to_parse) == #filepaths then
            vim.schedule(select_script)
        end
    end

    for _, filepath in ipairs(filepaths) do
        read_file_lines(filepath, file_read_callback)
    end
end

return M

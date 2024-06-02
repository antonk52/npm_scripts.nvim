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
            vim.cmd('vs | term cd ' .. opts.path .. ' && ' .. opts.package_manager .. ' run ' .. opts.name)
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

    if vim.fn.file_readable(filepath) == 0 then
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
    local files = vim.fs.find(
        { 'package.json'},
        { upward = true, type = 'file', stop = vim.fs.dirname(vim.env.HOME), limit = 1, path = utils.buffer_cwd() }
    )
    if #files > 0 then
        local lines = vim.fn.readfile(files[1])
        return {
            filepath = files[1],
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
    local lock_files = vim.fs.find(
        vim.tbl_keys(lock_file_to_manager),
        {
            upward = true,
            type = 'file',
            stop = vim.fs.dirname(vim.env.HOME),
            limit = 1,
            path = utils.buffer_cwd(),
        }
    )
    if #lock_files > 0 then
        return lock_file_to_manager[vim.fs.basename(lock_files[1])]
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

                if item ~= '' and vim.fn.file_readable(package_json_filepath) == 1 then
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

---Find all package.json files from cwd and select a script across all of them
---@param opts NpmScripts.PluginOptions|nil
---@return nil
function M.run_from_all(opts)
    opts = utils.get_opts(opts or {})

    local out = vim.fn.system({ 'fd', '-E', 'node_modules', '-t', 'f', 'package.json', '.' })
    out = vim.trim(out)
    local lines = vim.split(out, '\n')
    lines = vim.tbl_filter(function(line)
        return line ~= ''
    end, lines)

    if #lines == 0 then
        return vim.notify('No package.json files found', vim.log.levels.WARN)
    end

    local failed_to_parse = {}
    local package_jsons = vim.tbl_map(function(filepath)
        local content = vim.fn.readfile(filepath)
        local success, result = pcall(vim.json.decode, table.concat(content, ''))
        if success then
            return {
                filepath = filepath,
                name = result.name or 'unknown',
                scripts = result.scripts or {},
            }
        else
            table.insert(failed_to_parse, filepath)
            return nil
        end
    end, lines)

    if #failed_to_parse > 0 then
        vim.notify('Failed to parse package.json files: ' .. table.concat(failed_to_parse, '; '), vim.log.levels.WARN)
    end

    local flatten_scripts = {}
    for _, package_json in ipairs(package_jsons) do
        if package_json == nil then
            goto continue
        end
        for script_name, script in pairs(package_json.scripts) do
            local label = package_json.name .. ': ' .. script_name
            local script_obj = {
                label = label,
                script_name = script_name,
                script_value = script,
                path = vim.fs.dirname(package_json.filepath),
            }
            table.insert(flatten_scripts, script_obj)
        end
        ::continue::
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

return M

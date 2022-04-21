---@class PackageJson
---@field json table<string, string|table<string,string>>
---@field filepath string

---@class PluginOptions
local DEFAULT_OPTIONS = {
    select = vim.ui.select,

    select_script_prompt = "Select a script to run:",
    select_script_format_item = tostring,

    select_workspace_prompt = "Select a workspace to run a script:",
    select_workspace_format_item = tostring,

    package_manager = "npm",

    -- whether to pick a workspace script via a single search
    -- or two searches, over workspaces and picked workspace scripts
    workspace_script_solo_picker = true,
    -- opts.script_name string
    -- opts.path string where command should be executed
    -- opts.package_manager string the binary to run the script ie 'npm' | 'yarn'
    run_script = function(opts)
        vim.cmd("vs | term cd " .. opts.path .. " && " .. opts.package_manager .. " run " .. opts.name)
    end,
}
local GLOBAL_OPTIONS = {}
local M = {}

---Override default plugin options
---@param opts PluginOptions
---@return nil
function M.setup(opts)
    for k, v in pairs(opts) do
        GLOBAL_OPTIONS[k] = v
    end
end

local utils = {}
---Infer options
---@param local_options PluginOptions
---@return PluginOptions
function utils.get_opts(local_options)
    local result = {}
    for _, opts in ipairs({ DEFAULT_OPTIONS, GLOBAL_OPTIONS, local_options }) do
        for k, v in pairs(opts) do
            result[k] = v
        end
    end

    return result
end
---closest directory to the argument
---@param path string
---@return string
function utils.dirname(path)
    if vim.fn.isdirectory(path) == 1 then
        return path
    end
    local parts = vim.split(path, "/")
    return table.concat(parts, "/", 1, #parts == 1 and 1 or #parts - 1)
end

---Get current buffer's closest directory
---@return string
function utils.buffer_cwd()
    local buf_path = vim.fn.expand("%")
    return utils.dirname(buf_path)
end
---@return PackageJson|nil
function utils.get_root_package_json()
    -- process cwd
    local cwd = vim.fn.getcwd()
    local filepath = cwd .. "/package.json"

    if vim.fn.file_readable(filepath) == 0 then
        return nil
    end

    local lines = vim.fn.readfile(filepath)
    local content = table.concat(lines, "")
    return {
        filepath = filepath,
        json = vim.json.decode(content),
    }
end
---@return PackageJson|nil
function utils.get_closest_package_json()
    local cwd = utils.buffer_cwd()
    local paths = vim.split(cwd, "/")

    for i, _ in ipairs(paths) do
        local filepath = table.concat(paths, "/", 1, #paths == 1 and 1 or #paths - i) .. "/package.json"
        if vim.fn.file_readable(filepath) == 1 then
            local lines = vim.fn.readfile(filepath)
            return {
                filepath = filepath,
                json = vim.json.decode(table.concat(lines, "")),
            }
        end
    end

    return nil
end

---Run a script from project's package.json
---@param opts PluginOptions|nil
---@return nil
function M.run_script(opts)
    opts = utils.get_opts(opts or {})

    local config = utils.get_root_package_json()
    if config == nil then
        print("package.json not found")
        return nil
    end
    if config.json.scripts == nil then
        print('No "scripts" in package.json')
        return nil
    end

    local script_names = vim.fn.keys(config.json.scripts)

    if #script_names == 0 then
        print('Empty "scripts" in package.json')
        return nil
    end

    opts.select(script_names, {
        prompt = opts.select_script_prompt,
        kind = "string",
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
---@param opts PluginOptions|nil
---@return nil
function M.run_workspace_script(opts)
    opts = utils.get_opts(opts or {})

    local root_config = utils.get_root_package_json()
    if root_config == nil then
        print("no root package.json")
        return nil
    end

    if root_config.json.workspaces == nil then
        print('no "workspaces" in package.json')
        return nil
    end

    -- { [name] = {filepath, json} }
    ---@type table<string, PackageJson>
    local workspaces = {}

    for _, glob in pairs(root_config.json.workspaces) do
        local items = vim.split(vim.fn.glob(glob), "\n")

        for _, item in ipairs(items) do
            local package_json_filepath = item .. "/package.json"

            if item ~= "" and vim.fn.file_readable(package_json_filepath) == 1 then
                local workspace_json_lines = vim.fn.readfile(package_json_filepath)
                local workspace_json = vim.json.decode(table.concat(workspace_json_lines, ""))

                workspaces[workspace_json.name] = {
                    filepath = item,
                    json = workspace_json,
                }
            end
        end
    end

    if opts.workspace_script_solo_picker then
        local items = {}
        for workspace_name, w in pairs(workspaces) do
            for script_name, _ in pairs(w.json.scripts or {}) do
                table.insert(items, workspace_name..'  '..script_name)
            end
        end

        opts.select(items, {
            prompt = opts.select_script_prompt
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
            kind = "string",
            format_item = opts.select_workspace_format_item,
        }, function(workspace_name)
            local workspace_scripts = workspaces[workspace_name].json.scripts

            if workspace_scripts == nil or #vim.fn.keys(workspace_scripts) == 0 then
                print('No "scripts" in workspace package.json')
                return nil
            end

            opts.select(vim.fn.keys(workspace_scripts), {
                prompt = opts.select_script_prompt,
                kind = "string",
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
---@param opts PluginOptions|nil
---@return nil
function M.run_buffer_script(opts)
    opts = utils.get_opts(opts or {})

    local config = utils.get_closest_package_json()

    if not config then
        print("Could not locate package.json")
        return nil
    end

    if not config.json.scripts then
        print('package.json does not have "scripts"')
        return nil
    end

    opts.select(vim.fn.keys(config.json.scripts), {
        prompt = opts.select_script_prompt,
        kind = "string",
        format_item = function(script)
            return script .. '\t"' .. config.json.scripts[script] .. '"'
        end,
    }, function(name)
        opts.run_script({
            name = name,
            path = utils.dirname(config.filepath),
            package_manager = opts.package_manager,
        })
    end)
end

return M

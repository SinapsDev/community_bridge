---@diagnostic disable: duplicate-set-field
-- Late module loading.
--
-- Framework and boss-menu modules used to bail out at load time unless their
-- resource was already 'started'. When community_bridge started before the
-- framework (server.cfg order, a [category] ensure, or the framework still
-- 'starting'), the module was skipped for good: Bridge.Framework only had the
-- _default functions, so e.g. Framework.GetIsFrameworkAdmin was nil until
-- community_bridge was restarted by hand.
--
-- A module now calls BridgeLateLoad.Gate(...) instead. If its resource is
-- started it loads as before. If the resource exists but is not started yet,
-- the module file is re-run once that resource fires onResourceStart and the
-- Bridge module is registered again.
--
-- Resources that fetched the bridge before that moment hold a copy of the old
-- table, so while a module is pending its exported functions are forwarders
-- that look up the current implementation at call time.

local RESOURCE = GetCurrentResourceName()
local IS_SERVER = IsDuplicityVersion()
local SIDE = IS_SERVER and 'server' or 'client'

BridgeLateLoad = BridgeLateLoad or {}

-- Resources that compete for the same Bridge module.
BridgeLateLoad.Frameworks = { 'es_extended', 'qb-core', 'qbx_core' }
BridgeLateLoad.BossMenus = { 'esx_society', 'qb-management', 'qbx_management' }

local pending = {}        -- resourceName -> list of { moduleName, path }
local pendingByModule = {} -- moduleName -> list of { resourceName, path }
local resolved = {}       -- moduleName -> resourceName that was loaded late
local loadingPath = nil   -- module path currently being re-run
local earlyConsumers = {} -- resources that fetched the bridge while a module was pending
local earlyOrder = {}

---Remember which resources took a copy of the bridge while a module was still
---pending. Functions reach them through forwarders, but data fields such as
---Framework.Shared were copied empty and stay that way until they restart.
---@param resourceName string|nil
function BridgeLateLoad.NoteConsumer(resourceName)
    if not resourceName or resourceName == RESOURCE or next(pending) == nil then return end
    if earlyConsumers[resourceName] then return end
    earlyConsumers[resourceName] = true
    earlyOrder[#earlyOrder + 1] = resourceName
end

local function anyStarted(group)
    if not group then return false end
    for i = 1, #group do
        if GetResourceState(group[i]) == 'started' then return true end
    end
    return false
end

---Decide whether a module file should load now.
---@param moduleName string Bridge module the file fills (e.g. 'Framework')
---@param resourceName string resource the file wraps (e.g. 'es_extended')
---@param modulePath string path of the file inside this resource
---@param group string[]|nil resources competing for the same module; if one of them is already started, nothing is deferred
---@return boolean loadNow
function BridgeLateLoad.Gate(moduleName, resourceName, modulePath, group)
    if loadingPath == modulePath then return true end

    local state = GetResourceState(resourceName)
    if state == 'started' then return true end
    if state == 'missing' then return false end
    if anyStarted(group) then return false end

    local entry = { moduleName = moduleName, resourceName = resourceName, path = modulePath }
    pending[resourceName] = pending[resourceName] or {}
    table.insert(pending[resourceName], entry)
    pendingByModule[moduleName] = pendingByModule[moduleName] or {}
    table.insert(pendingByModule[moduleName], entry)

    if moduleName == 'Framework' and IS_SERVER then
        print(('^3[%s] %s is not started yet (state: %s). The %s module will load when it starts. Put "ensure %s" after "ensure %s" in server.cfg.^0')
            :format(RESOURCE, resourceName, state, moduleName, RESOURCE, resourceName))
    elseif BridgeSharedConfig and BridgeSharedConfig.DebugLevel ~= 0 then
        print(('^3[%s] %s module for %s deferred (%s state: %s)^0'):format(RESOURCE, moduleName, resourceName, SIDE, state))
    end
    return false
end

local function collectFunctionNames(path)
    local names, nested = {}, {}
    local src = LoadResourceFile(RESOURCE, path)
    if not src then return names, nested end
    for line in src:gmatch('[^\n]+') do
        local sub, fn = line:match('^%s*[%w_]+%.([%w_]+)%.([%w_]+)%s*=%s*function')
        if sub then
            nested[sub] = nested[sub] or {}
            nested[sub][fn] = true
        else
            fn = line:match('^%s*[%w_]+%.([%w_]+)%s*=%s*function')
                or line:match('^%s*function%s+[%w_]+%.([%w_]+)%s*%(')
            if fn then names[fn] = true end
        end
    end
    return names, nested
end

local function forwarder(moduleName, fnName, subName)
    return function(...)
        local mod = _G[moduleName]
        local fn = mod and mod[subName or fnName]
        if subName then fn = type(fn) == 'table' and fn[fnName] or nil end
        if type(fn) ~= 'function' then
            local waiting = {}
            for _, e in ipairs(pendingByModule[moduleName] or {}) do waiting[#waiting + 1] = e.resourceName end
            error(('[%s] %s.%s%s is not available: %s has not started yet'):format(
                RESOURCE, moduleName, subName and (subName .. '.') or '', fnName, table.concat(waiting, '/')), 2)
        end
        return fn(...)
    end
end

---Replace the exported functions of every pending module with forwarders so
---resources that grab the bridge before the late module loads still reach the
---real implementation afterwards. Called once from init.lua.
function BridgeLateLoad.InstallForwarders()
    for moduleName, entries in pairs(pendingByModule) do
        local wrapped = Bridge and Bridge[moduleName]
        if type(wrapped) == 'table' then
            local names, nested = {}, {}
            for _, e in ipairs(entries) do
                local n, s = collectFunctionNames(e.path)
                for k in pairs(n) do names[k] = true end
                for sub, fns in pairs(s) do
                    nested[sub] = nested[sub] or {}
                    for k in pairs(fns) do nested[sub][k] = true end
                end
            end
            for k, v in pairs(wrapped) do
                if type(v) == 'function' then names[k] = true end
            end
            for k in pairs(names) do
                wrapped[k] = forwarder(moduleName, k)
            end
            for sub, fns in pairs(nested) do
                if wrapped[sub] == nil then
                    local t = {}
                    for k in pairs(fns) do t[k] = forwarder(moduleName, k, sub) end
                    wrapped[sub] = t
                end
            end
        end
    end
end

local function runModule(entry)
    local src = LoadResourceFile(RESOURCE, entry.path)
    if not src then return false, 'file not found' end
    local chunk, err = load(src, ('@%s/%s'):format(RESOURCE, entry.path))
    if not chunk then return false, err end
    loadingPath = entry.path
    local ok, result = pcall(chunk)
    loadingPath = nil
    if not ok then return false, result end
    return true, result
end

AddEventHandler('onResourceStart', function(resourceName)
    local entries = pending[resourceName]
    if not entries then return end
    pending[resourceName] = nil

    for _, entry in ipairs(entries) do
        if not resolved[entry.moduleName] then
            local ok, result = runModule(entry)
            if not ok then
                print(('^1[%s] Failed to load the %s module for %s after it started: %s^0'):format(RESOURCE, entry.moduleName, resourceName, tostring(result)))
            elseif result ~= nil then
                resolved[entry.moduleName] = resourceName
                if Bridge and Bridge.RegisterModule then
                    Bridge.RegisterModule(entry.moduleName, _G[entry.moduleName])
                end
                print(('^2[%s] %s started after %s: %s module loaded late (%s)^0'):format(RESOURCE, resourceName, RESOURCE, entry.moduleName, SIDE))
                if #earlyOrder > 0 then
                    print(('^3[%s] Resources that fetched the bridge before %s started: %s. Their %s functions now work, but data fields copied at that time (e.g. Framework.Shared) stay empty until they restart. Ensure %s after %s to avoid this.^0')
                        :format(RESOURCE, resourceName, table.concat(earlyOrder, ', '), entry.moduleName, RESOURCE, resourceName))
                end
            end
        end
    end
end)

return BridgeLateLoad

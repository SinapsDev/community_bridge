---@diagnostic disable: duplicate-set-field
local resourceName = "DHS-PrisonSim"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

local validLevels = { min = true, med = true, max = true }

local function securityLevel()
    local configured = BridgeServerConfig and BridgeServerConfig.DHSPrisonSecurity or "min"
    local level = string.lower(GetConvar("community_bridge:dhs_security", configured))
    if validLevels[level] then return level end
    print(("^3[community_bridge] DHS-PrisonSim: invalid security level '%s' (use min, med or max), using 'min'^0"):format(level))
    return "min"
end

local function call(name, ...)
    local args = { ... }
    local ok, result = pcall(function()
        return exports[resourceName][name](exports[resourceName], table.unpack(args))
    end)
    if not ok then
        print(("^1[community_bridge] DHS-PrisonSim: export %s failed: %s^0"):format(name, tostring(result)))
        return nil
    end
    return result
end

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    return call("SendPlayerToPrison", src, securityLevel(), math.floor(tonumber(time) or 0))
end

Prison.UnjailPlayer = function(src)
    return call("ReleaseFromPrison", src)
end

return Prison

---@diagnostic disable: duplicate-set-field
local resourceName = "rcore_prison"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    exports['rcore_prison']:Jail(src, time)
end

Prison.UnjailPlayer = function(src)
    exports["rcore_prison"]:Unjail(src)
end

return Prison
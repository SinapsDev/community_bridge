---@diagnostic disable: duplicate-set-field
local resourceName = "tk_jail"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    exports["tk_jail"]:jail(src, time)
end

Prison.UnjailPlayer = function(src)
    exports["tk_jail"]:unjail(src)
end

return Prison
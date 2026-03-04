---@diagnostic disable: duplicate-set-field
local resourceName = "pickle_prisons"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    exports["pickle_prisons"]:JailPlayer(src, time)
end

Prison.UnjailPlayer = function(src)
    exports["pickle_prisons"]:UnjailPlayer(src)
end

return Prison
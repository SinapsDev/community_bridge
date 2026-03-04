---@diagnostic disable: duplicate-set-field
local resourceName = "xt-prison"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    lib.callback.await('xt-prison:client:enterJail', src, time)
end

Prison.UnjailPlayer = function(src)
    lib.callback.await('xt-prison:client:exitJail', src, true)
end

return Prison
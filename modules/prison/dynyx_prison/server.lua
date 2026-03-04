---@diagnostic disable: duplicate-set-field
local resourceName = "dynyx_prison"
if GetResourceState(resourceName) == 'missing' then return end
Prison = Prison or {}

Prison.GetResourceName = function()
    return resourceName
end

Prison.JailPlayer = function(src, time)
    exports["dynyx_prison"]:AddPrisonerExternally(src, time, {}, false, "prison")
end

Prison.UnjailPlayer = function(src)
    local citizenid = Framework.GetPlayerIdentifier(src)
    if not citizenid then return end
    exports["dynyx_prison"]:ReleasePrisonerExternally(citizenid, "prison")
end

return Prison
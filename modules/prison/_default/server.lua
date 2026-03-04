---@diagnostic disable: duplicate-set-field
Prison = Prison or {}

Prison.GetResourceName = function()
    return "default"
end

Prison.JailPlayer = function(src, time)
    print("^6 There is no prison bridged in community_bridge. ^0")
end

Prison.UnjailPlayer = function(src)
    print("^6 There is no prison bridged in community_bridge. ^0")
end

return Prison
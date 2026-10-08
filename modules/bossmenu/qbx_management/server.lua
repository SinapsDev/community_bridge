---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('BossMenu', 'qbx_management', 'modules/bossmenu/qbx_management/server.lua', BridgeLateLoad.BossMenus) then return end

BossMenu = BossMenu or {}

---This will get the name of the module being used.
---@return string
BossMenu.GetResourceName = function()
    return "qbx_management"
end

BossMenu.OpenBossMenu = function(src, jobName, jobType)
    TriggerClientEvent("community_bridge:client:OpenBossMenu", src, jobName, jobType)
end

return BossMenu
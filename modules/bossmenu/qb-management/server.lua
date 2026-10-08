---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('BossMenu', 'qb-management', 'modules/bossmenu/qb-management/server.lua', BridgeLateLoad.BossMenus) then return end
if GetResourceState('qbx_management') == 'started' then return end

BossMenu = BossMenu or {}

---This will get the name of the module being used.
---@return string
BossMenu.GetResourceName = function()
    return "qb-management"
end

BossMenu.OpenBossMenu = function(src, jobName, jobType)
    TriggerClientEvent("qb-bossmenu:client:OpenMenu", src)
end

return BossMenu
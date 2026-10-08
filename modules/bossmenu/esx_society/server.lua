---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('BossMenu', 'esx_society', 'modules/bossmenu/esx_society/server.lua', BridgeLateLoad.BossMenus) then return end

BossMenu = BossMenu or {}

---This will get the name of the module being used.
---@return string
BossMenu.GetResourceName = function()
    return "esx_society"
end

local registeredSocieties = {}
BossMenu.OpenBossMenu = function(src, jobName, jobType)
    if not registeredSocieties[jobName] then
        exports["esx_society"]:registerSociety(jobName, jobName, 'society_' .. jobName, 'society_' .. jobName, 'society_' .. jobName, {type = 'private'})
        registeredSocieties[jobName] = true
    end
    TriggerClientEvent("community_bridge:client:OpenBossMenu", src, jobName, jobType)
end

return BossMenu
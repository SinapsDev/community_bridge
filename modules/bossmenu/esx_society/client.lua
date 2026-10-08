---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('BossMenu', 'esx_society', 'modules/bossmenu/esx_society/client.lua', BridgeLateLoad.BossMenus) then return end

BossMenu = BossMenu or {}

---This will get the name of the module being used.
---@return string
BossMenu.GetResourceName = function()
    return "esx_society"
end

return BossMenu
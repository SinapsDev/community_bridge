---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('Framework', 'qbx_core', 'modules/framework/qbx_core/client.lua', BridgeLateLoad.Frameworks) then return end

QBox = exports.qbx_core

Framework = Framework or {}

---@description This will get the name of the framework being used (if a supported framework).
---@return string
Framework.GetFrameworkName = function()
    print("This is depricated, please use Framework.GetResourceName() instead.")
    return Framework.GetResourceName()
end

---@description This will get the name of the in use resource.
---@return string
Framework.GetResourceName = function()
    return 'qbx_core'
end

---@description This will return true if the player is loaded, false otherwise.
---@return boolean
Framework.GetIsPlayerLoaded = function()
    return LocalPlayer.state.isLoggedIn or false
end

---@description This is an internal function, do not use this outside of bridge as there is no standard format between the frameworks.
---@return table
Framework.GetPlayerData = function()
    return QBox.GetPlayerData()
end

---@description This will return a table of all the jobs in the framework.
---@return table
Framework.GetFrameworkJobs = function()
    return QBox.GetJobs()
end

---@description This will get the players birth date
---@return string
Framework.GetPlayerDob = function()
    local playerData = Framework.GetPlayerData()
    return playerData.charinfo.birthdate
end

---@description Will Display the help text message on the screen
---@param message string
---@param position string
---@return nil
Framework.ShowHelpText = function(message, position)
    return exports.ox_lib:showTextUI(message, { position = position or 'top-center' })
end

---@description This will hide the help text message on the screen
---@return nil
Framework.HideHelpText = function()
    return exports.ox_lib:hideTextUI()
end

---@description This will return the players metadata for the specified metadata key.
---@param metadata table | string
---@return table | string | number | boolean
Framework.GetPlayerMetaData = function(metadata)
    return Framework.GetPlayerData().metadata[metadata]
end

---@description This will send a notification to the player.
---@param message string
---@param type string
---@param time number
---@return nil
Framework.Notify = function(message, type, time)
    return QBox:Notify("Notification", type, time, message)
end

---@description This will get the hunger of a player
---@return number
Framework.GetHunger = function()
    local hunger = Framework.GetPlayerMetaData("hunger") or 0
    return math.floor((hunger) + 0.5) or 0
end

---@description This will get the thirst of a player
---@return number
Framework.GetThirst = function()
    local thirst = Framework.GetPlayerMetaData("thirst") or 0
    return math.floor((thirst) + 0.5) or 0
end

---@description This will get the players identifier (citizenid) etc.
---@return string
Framework.GetPlayerIdentifier = function()
    return Framework.GetPlayerData().citizenid
end

---@description This will get the players name (first and last).
---@return string
---@return string
Framework.GetPlayerName = function()
    local playerData = Framework.GetPlayerData()
    return playerData.charinfo.firstname, playerData.charinfo.lastname
end

---@description Depricated : This will return the players job name, job label, job grade label and job grade level
---@return string
---@return string
---@return string
---@return string
Framework.GetPlayerJob = function()
    --print("This is depricated, please use Framework.GetPlayerJobData() instead.")
    local jobData = Framework.GetPlayerJobData()
    return jobData.jobName, jobData.jobLabel, jobData.gradeName, jobData.gradeRank
end

---@description This will return the players job name, job label, job grade label job grade level, boss status, and duty status in a table
---@return table
Framework.GetPlayerJobData = function()
    local playerData = Framework.GetPlayerData()
    local jobData = playerData.job
    return {
        jobName = jobData.name,
        jobLabel = jobData.label,
        gradeName = jobData.grade.name,
        gradeLabel = jobData.grade.name,
        gradeRank = jobData.grade.level,
        boss = jobData.isboss,
        onDuty = jobData.onduty,
    }
end

---@description This is an internal function used as a fallback, please use the Inventory.GetPlayerInventory instead.
---@return table {name, label, count, slot, metadata, stack, close, weight}
Framework.GetPlayerInventory = function()
    return Framework.GetPlayerData().items
end

---@description This will return the players money by type, I recommend not useing this as its the client and not secure or to be trusted.
---Use case is for a ui or a menu I guess.
---@param _type string
---@return number
Framework.GetAccountBalance = function(_type)
    local player = Framework.GetPlayerData()
    if not player then return 0 end
    local account = player.money
    if _type == 'money' then _type = 'cash' end
    local balance = account[_type] or 0
    if balance <= 0 then return 0 end
    return balance
end

---@description This is an internal function used as a fallback, please use the Inventory.GetItemCount instead.
--- @param item string
--- @return number
Framework.GetItemCount = function(item)
    return 0, print("Qbox has not implemented GetItemCount for this framework. Please ensure the inventory you are using is supported and start order is correct.")
end

---@description This will return the item data for the specified item.
--- @param item string
--- @return table {name, label, stack, weight, description, image}
Framework.GetItemInfo = function(item)
    return {}, print("Qbox has not implemented GetItemInfo for this framework. Please ensure the inventory you are using is supported and start order is correct.")
end

---@description Will return boolean if the player has the item.
---@param item string
---@param requiredCount number (optional)
---@return boolean
Framework.HasItem = function(item, requiredCount)
	return false, print("Qbox has not implemented HasItem for this framework, Please ensure the inventory you are using is supported and start order is correct.")
end

---@description This will get a players dead status.
---@return boolean
Framework.GetIsPlayerDead = function()
    local playerData = Framework.GetPlayerData()
    return playerData.metadata["isdead"] or playerData.metadata["inlaststand"]
end

---@description Event handler for when player is loaded in QBX Core framework
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1500)
    TriggerEvent('community_bridge:Client:OnPlayerLoaded')
end)

---@description Event handler for when player is unloaded in QBX Core framework
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    TriggerEvent('community_bridge:Client:OnPlayerUnload')
end)

---@description Event handler for when player job is updated in QBX Core framework
---@param data table Job data containing name, label, and grade information
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(data)
    TriggerEvent('community_bridge:Client:OnPlayerJobUpdate', data.name, data.label, data.grade.name, data.grade.level)
end)

return Framework
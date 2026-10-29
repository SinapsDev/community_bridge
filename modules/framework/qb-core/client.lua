---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('Framework', 'qb-core', 'modules/framework/qb-core/client.lua', BridgeLateLoad.Frameworks) then return end
if GetResourceState('qbx_core') == 'started' then return end

Framework = Framework or {}

QBCore = exports['qb-core']:GetCoreObject()

Framework.Shared = QBCore.Shared

---@description This will get the name of the framework being used (if a supported framework).
---@return string
Framework.GetFrameworkName = function()
    print("This is depricated, please use Framework.GetResourceName() instead.")
    return Framework.GetResourceName()
end

---@description This will get the name of the in use resource.
---@return string
Framework.GetResourceName = function()
    return 'qb-core'
end

---@description This will return true if the player is loaded, false otherwise.
---This could be useful in scripts that rely on player loaded events and offer a debug mode to hit this function.
---@return boolean
Framework.GetIsPlayerLoaded = function()
    return LocalPlayer.state.isLoggedIn or false
end

---@description This will return a table of the player data, this will be in the framework format. 
---This is mainly for internal bridge use and should be avoided.
---@return table
Framework.GetPlayerData = function()
    return QBCore.Functions.GetPlayerData()
end

---@description This will return a table of all the jobs in the framework.
---@return table
Framework.GetFrameworkJobs = function()
    local jobs = {}
    for k, v in pairs(QBCore.Shared.Jobs) do
        table.insert(jobs, {
            name = k,
            label = v.label,
            grade = v.grades
        })
    end
    return jobs
end

---@description This will get the players birth date
---@return string
Framework.GetPlayerDob = function()
    local playerData = Framework.GetPlayerData()
    local charinfo = playerData and playerData.charinfo
    return charinfo and charinfo.birthdate
end

---@description This will return the players metadata for the specified metadata key.
---@param metadata table | string
---@return table | string | number | boolean
Framework.GetPlayerMetaData = function(metadata)
    local playerData = Framework.GetPlayerData()
    local playerMeta = playerData and playerData.metadata
    return playerMeta and playerMeta[metadata]
end

---@description This will send a notification to the player.
---@param message string
---@param type string
---@param time number
---@return nil
Framework.Notify = function(message, type, time)
    TriggerEvent('QBCore:Notify', message, 'primary', time)
end

---@description This will display the help text message on the screen
---@param message string
---@param _position unknown
---@return nil
Framework.ShowHelpText = function(message, _position)
    return exports['qb-core']:DrawText(message, _position)
end

---@description This will hide the help text message on the screen
---@return nil
Framework.HideHelpText = function()
    return exports['qb-core']:HideText()
end

---@description This will return the players money by type, I recommend not using this
---as its the client and not secure or to be trusted. Use case is for a ui or a menu I guess.
---@param _type string
---@return number
Framework.GetAccountBalance = function(_type)
    local player = Framework.GetPlayerData()
    local account = player and player.money
    if not account then return 0 end
    if _type == 'money' then _type = 'cash' end
    return account[_type] or 0
end

---@description This will return the item data for the specified item.
---@param item string
---@return table
Framework.GetItemInfo = function(item)
    local itemData = QBCore.Shared.Items[item]
    if not itemData then return {} end
    local repackedTable = {
        name = itemData.name,
        label = itemData.label,
        stack = itemData.unique,
        weight = itemData.weight,
        description = itemData.description,
        image = itemData.image
    }
    return repackedTable
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
    local charinfo = playerData and playerData.charinfo
    if not charinfo then return nil, nil end
    return charinfo.firstname, charinfo.lastname
end

---@deprecated Deprecated: This will return the players job name, job label, job grade label and job grade level
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
    -- No job yet while the character is still loading (or none selected).
    local jobData = playerData and playerData.job
    if not jobData then return {} end
    local grade = jobData.grade or {}
    return {
        jobName = jobData.name,
        jobLabel = jobData.label,
        gradeName = grade.name,
        gradeLabel = grade.name,
        gradeRank = grade.level,
        boss = jobData.isboss,
        onDuty = jobData.onduty,
    }
end

---@description Will return boolean if the player has the item.
---@param item string
---@param requiredCount number (optional)
---@return boolean
Framework.HasItem = function(item, requiredCount)
	return QBCore.Functions.HasItem(item, requiredCount or 1)
end

---@description This will return the item count for the specified item in the players inventory
---@param item string
---@return number
Framework.GetItemCount = function(item)
    local playerData = Framework.GetPlayerData()
    local frameworkInv = playerData and playerData.items or {}
    local count = 0
    for _, v in pairs(frameworkInv) do
        if v.name == item then
            count = count + (v.amount or v.count)
        end
    end
    return count
end

---@description This will return the players inventory as a table in the ox_inventory style format
---@return table
Framework.GetPlayerInventory = function()
    local items = {}
    local playerData = Framework.GetPlayerData()
    local frameworkInv = playerData and playerData.items or {}
    for _, v in pairs(frameworkInv) do
        table.insert(items, {
            name = v.name,
            label = v.label,
            count = v.amount or v.count,
            slot = v.slot,
            metadata = v.info or v.metadata or {},
            stack = v.unique,
            close = v.useable,
            weight = v.weight
        })
    end
    return items
end

---@description This will return the vehicle properties for the specified vehicle
---@param vehicle number
---@return table
Framework.GetVehicleProperties = function(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return {} end
    local vehicleProps = QBCore.Functions.GetVehicleProperties(vehicle)
    return vehicleProps or {}
end

---@description This will set the vehicle properties for the specified vehicle
---@param vehicle number
---@param properties table
---@return boolean
Framework.SetVehicleProperties = function(vehicle, properties)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    if not properties then return false end
    if NetworkGetEntityIsNetworked(vehicle) then
        local vehNetID = NetworkGetNetworkIdFromEntity(vehicle)
        local entOwner = GetPlayerServerId(NetworkGetEntityOwner(vehNetID))
        if entOwner ~= GetPlayerServerId(PlayerId()) then
            NetworkRequestControlOfEntity(vehicle)
            local count = 0
            while not NetworkHasControlOfEntity(vehicle) and count < 3000 do
                Wait(1)
                count = count + 1
            end
        end
    end
    return true, QBCore.Functions.SetVehicleProperties(vehicle, properties)
end

---@description This will get a players dead status
---@return boolean
Framework.GetIsPlayerDead = function()
    local playerData = Framework.GetPlayerData()
    local playerMeta = playerData and playerData.metadata
    if not playerMeta then return false end
    return playerMeta["isdead"] or playerMeta["inlaststand"]
end

---@description Event handler for when player is loaded in QB-Core framework
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1500)
    TriggerEvent('community_bridge:Client:OnPlayerLoaded')
end)

---@description Event handler for when player is unloaded in QB-Core framework
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    TriggerEvent('community_bridge:Client:OnPlayerUnload')
end)

---@description Event handler for when player job is updated in QB-Core framework
---@param data table Job data containing name, label, grade_label, and grade
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(data)
    TriggerEvent('community_bridge:Client:OnPlayerJobUpdate', data.name, data.label, data.grade_label, data.grade)
end)

return Framework
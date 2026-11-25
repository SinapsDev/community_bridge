---@diagnostic disable: duplicate-set-field
if not BridgeLateLoad.Gate('Framework', 'qbx_core', 'modules/framework/qbx_core/server.lua', BridgeLateLoad.Frameworks) then return end

Framework = Framework or {}

local QBox = exports.qbx_core

-- Identity and job reads (GetPlayerIdentifier, GetPlayerName, GetPlayerJobData,
-- GetPlayerDuty, ...) each fetched the whole Player through
-- exports.qbx_core:GetPlayer(src): PlayerData with the full inventory plus every
-- Player.Functions entry as a function reference, copied across resources on
-- every call. Resources that walk their officers or units call these many times
-- per tick, so they now share a short-lived per-source copy of only the fields
-- they read (citizenid, name, birthdate, phone, job, gang). Framework.GetPlayer,
-- money, items and metadata are still read live.
--
-- The copy is dropped on every job, duty, gang, load, unload and drop event and
-- around the bridge's own setters. Events only drop it, the data always comes
-- from qbx_core (some of these events are net events a client can fire).
-- PLAYER_INFO_TTL_MS bounds it when qbx_core changes a field without an event
-- (SetCharInfo, SetPlayerData('job', ...)).
local PLAYER_INFO_TTL_MS = 2000
-- After an unload or drop the character is still in qbx_core for a moment
-- (Logout waits 200 ms); reads in this window go to qbx_core uncached.
local PLAYER_INFO_UNLOAD_BYPASS_MS = 1000

local playerInfoCache = {}  -- src -> snapshot
local playerInfoBypass = {} -- src -> GetGameTimer() until which reads skip the cache

local function snapshotPlayerData(playerData)
    local charinfo = type(playerData.charinfo) == 'table' and playerData.charinfo or nil
    local job = type(playerData.job) == 'table' and playerData.job or nil
    local jobGrade = job and type(job.grade) == 'table' and job.grade or nil
    local gang = type(playerData.gang) == 'table' and playerData.gang or nil
    return {
        citizenid = playerData.citizenid,
        charinfo = charinfo and {
            firstname = charinfo.firstname,
            lastname = charinfo.lastname,
            birthdate = charinfo.birthdate,
            phone = charinfo.phone,
        } or nil,
        job = job and {
            name = job.name,
            label = job.label,
            isboss = job.isboss,
            onduty = job.onduty,
            grade = jobGrade and { name = jobGrade.name, level = jobGrade.level } or nil,
        } or nil,
        gang = gang and { name = gang.name } or nil,
    }
end

---Cache key of a source: a whole positive number, or nil when the source is not
---cached (a license or other non-numeric string, NaN, inf, 0, a negative or a
---fraction); reads for such a source go to qbx_core uncached, as in 0.13.18.
---Some invalidation events are net events, so src can be anything a client sends,
---and NaN must never reach a table index ("table index is NaN").
---@param src any
---@return number|nil
local function cacheKey(src)
    local key = tonumber(src)
    if not key or key ~= key or key <= 0 or key == math.huge or key % 1 ~= 0 then return nil end
    return key
end

---Read-only identity/job snapshot of a player. Never hand it out: the getters
---below return single values or new tables built from it.
---@param src number
---@return table|false|nil snapshot, false when the player has no PlayerData, nil when there is no player
local function getPlayerInfo(src)
    local key = cacheKey(src)
    local now = GetGameTimer()
    if key then
        local entry = playerInfoCache[key]
        if entry and entry.expires > now then return entry end
        playerInfoCache[key] = nil
    end
    local player = Framework.GetPlayer(src)
    if not player then return nil end
    local playerData = player.PlayerData
    if type(playerData) ~= 'table' then return false end
    local entry = snapshotPlayerData(playerData)
    if key then
        local bypassUntil = playerInfoBypass[key]
        if bypassUntil and bypassUntil <= now then
            playerInfoBypass[key] = nil
            bypassUntil = nil
        end
        if not bypassUntil then
            entry.expires = now + PLAYER_INFO_TTL_MS
            playerInfoCache[key] = entry
        end
    end
    return entry
end

---Drops the cached identity/job of a player (job, duty or gang changed, or a character loaded).
---@param src any
local function forgetPlayerInfo(src)
    local key = cacheKey(src)
    if key then playerInfoCache[key] = nil end
end

---Drops the cached identity/job of a player whose character is unloading or who left,
---and reads it uncached for PLAYER_INFO_UNLOAD_BYPASS_MS.
---@param src any
local function releasePlayerInfo(src)
    local key = cacheKey(src)
    if not key then return end
    playerInfoCache[key] = nil
    local now = GetGameTimer()
    for other, untilMs in pairs(playerInfoBypass) do
        if untilMs <= now then playerInfoBypass[other] = nil end
    end
    playerInfoBypass[key] = now + PLAYER_INFO_UNLOAD_BYPASS_MS
end

---Player a QBCore:Server:* handler acts on, or nil to ignore the event.
---OnPlayerLoaded, OnPlayerUnload and OnJobUpdate are registered as net events
---here, so a client can fire them with any argument: another player's id, 0,
---NaN, inf, a fraction. When the event came from the network (source is a
---player id) the sender is the player and the argument is ignored. When a
---server script fired it with TriggerEvent (source is ''), the argument is the
---player, as the cores pass it. Either way only a whole positive id of a
---connected player, or of one qbx_core still has, is accepted. Call it before
---anything that can yield: source changes on the next event.
---@param arg any the src argument of the event
---@return number|nil
local function eventPlayer(arg)
    local netSrc = tonumber(source)
    local candidate = arg
    if netSrc and netSrc > 0 then candidate = netSrc end
    local key = cacheKey(candidate)
    if not key then return nil end
    if GetPlayerName(key) == nil and not Framework.GetPlayer(key) then return nil end
    return key
end

---@description Returns the name of the framework being used (if a supported framework).
---@return string
Framework.GetFrameworkName = function()
    return 'qbx_core'
end

---@description This will get the name of the in use resource.
---@return string
Framework.GetResourceName = function()
    return 'qbx_core'
end

---@description This will return if the player is an admin in the framework.
---@param src number
---@return boolean
Framework.GetIsFrameworkAdmin = function(src)
    if not src then return false end
    return IsPlayerAceAllowed(src, 'admin')
end

---@description Returns the player date of birth.
---@param src number
---@return string|nil
Framework.GetPlayerDob = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    return info.charinfo.birthdate
end

---@description Returns the player data of the specified source.
---@param src any
---@return table | nil
Framework.GetPlayer = function(src)
    local player = QBox:GetPlayer(src)
    if not player then return end
    return player
end


---@description Returns the player data of the specified identifier in the framework defualt format.
---@param citizenid string
---@return table | nil
Framework.GetPlayerByIdentifier = function(citizenid)
    local player = QBox:GetPlayerByCitizenId(citizenid)
    if not player then return end
    return player
end

---@description This will return the player source of the specified citizen ID.
---@param citizenid string
---@return number | nil
Framework.GetPlayerSource = function(citizenid)
    local player = Framework.GetPlayerByIdentifier(citizenid)
    if not player then return end
    return player.PlayerData.source
end

---@description Returns a table of the jobs in the framework.
---@return table
Framework.GetFrameworkJobs = function()
    return QBox.GetJobs()
end

---@description Returns the citizen ID of the player.
---@param src number
---@return string | boolean | nil
Framework.GetPlayerIdentifier = function(src)
    local info = getPlayerInfo(src)
    if info == nil then return end
    if not info then return false end
    return info.citizenid
end

---@description This will return a table of all logged in players
---@return table
Framework.GetPlayers = function()
    local players = QBox:GetQBPlayers()
    local playerList = {}
    for src, _ in pairs(players) do
        table.insert(playerList, src)
    end
    return playerList
end

---@description Returns the first and last name of the player.
---@param src number
---@return string | nil
---@return string | nil
Framework.GetPlayerName = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    return info.charinfo.firstname, info.charinfo.lastname
end

---@description Adds the specified item to the player's inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@param item string
---@param amount number
---@param slot number
---@param metadata table
---@return boolean | nil
Framework.AddItem = function(src, item, amount, slot, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return false end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, { action = "add", item = item, count = amount, slot = slot, metadata = metadata })
    return player.Functions.AddItem(item, amount, slot, metadata)
end

---@description Removes the specified item from the player's inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@param item string
---@param amount number
---@param slot number
---@param metadata table
---@return boolean | nil
Framework.RemoveItem = function(src, item, amount, slot, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return false end
    TriggerClientEvent("community_bridge:client:inventory:updateInventory", src, { action = "remove", item = item, count = amount, slot = slot, metadata = metadata })
    return player.Functions.RemoveItem(item, amount, slot)
end

---@description Sets the metadata for the specified item in the player's inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@param item string
---@param slot number
---@param metadata table
---@return boolean | nil
Framework.SetMetadata = function(src, item, slot, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return false end
    player.Functions.RemoveItem(item, 1, slot)
    return player.Functions.AddItem(item, 1, slot, metadata)
end

---@description Returns a table of items matching the specified name and if passed metadata from the player's inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---returns {name = v.name, count = v.amount, metadata = v.info, slot = v.slot}
---@param src number
---@param item string
---@param metadata table
---@return table|nil {name = v.name, count = v.amount, metadata = v.info, slot = v.slot}
Framework.GetItem = function(src, item, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return { } end
    local repackedTable = {}
    for _, v in pairs(player.PlayerData.items) do
        if v.name == item and (not metadata or v.info == metadata) then
            repackedTable[#repackedTable + 1] = {
                name = v.name,
                count = v.amount or v.count,
                metadata = v.info or v.metadata,
                slot = v.slot,
            }
        end
    end
    return repackedTable
end

---@description Returns the count of items matching the specified name and if passed metadata from the player's inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@param item string
---@param metadata table
---@return number | nil
Framework.GetItemCount = function(src, item, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return 0 end
    local playerInventory = player.PlayerData.items
    local count = 0
    for _, v in pairs(playerInventory) do
        if v.name == item and (not metadata or v.info == metadata) then
            count = count + (v.amount or v.count)
        end
    end
    return count
end

---@description Returns boolean if the player has the specified item in their inventory.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@param item string
---@return boolean
Framework.HasItem = function(src, item)
    local getCount = Framework.GetItemCount(src, item)
    return getCount > 0
end

---@description Returns the entire inventory of the player as a table.
---This is an internal function and should not be used outside of bridge, use the Inventory module instead when dealing with items.
---@param src number
---@return table | nil
Framework.GetPlayerInventory = function(src)
    local player = Framework.GetPlayer(src)
    if not player then return { } end
    local playerItems = player.PlayerData.items
    local repackedTable = {}
    for _, v in pairs(playerItems) do
        table.insert(repackedTable, {
            name = v.name,
            count = v.amount,
            metadata = v.metadata,
            slot = v.slot,
        })
    end
    return repackedTable
end

---@description Adds the specified metadata key and number value to the player's data.
---@param src number
---@param metadata string
---@param value string
---@return boolean | nil
Framework.SetPlayerMetadata = function(src, metadata, value)
    local player = Framework.GetPlayer(src)
    if not player then return end
    player.Functions.SetMetaData(metadata, value)
    return true
end

---@description Gets the specified metadata key to the player's data.
---@param src number
---@param metadata string
---@return string | boolean | nil
Framework.GetPlayerMetadata = function(src, metadata)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    return playerData.metadata[metadata] or false
end

---@description Adds the specified value to the player's stress level and updates the client HUD.
---@param src number
---@param value number
---@return number | nil
Framework.AddStress = function(src, value)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    local newStress = playerData.metadata.stress + value
    player.Functions.SetMetaData('stress', Math.Clamp(newStress, 0, 100))
    TriggerClientEvent('hud:client:UpdateStress', src, newStress)
    return newStress
end

---@description Removes the specified value from the player's stress level and updates the client HUD.
---@param src number
---@param value number
---@return number | nil
Framework.RemoveStress = function(src, value)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    local newStress = (playerData.metadata.stress or 0) - value
    player.Functions.SetMetaData('stress', Math.Clamp(newStress, 0, 100))
    TriggerClientEvent('hud:client:UpdateStress', src, newStress)
    return newStress
end

---@description Adds the specified value from the player's hunger level.
---@param src number
---@param value number
---@return number | nil
Framework.AddHunger = function(src, value)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    local newHunger = (playerData.metadata.hunger or 0) + value
    player.Functions.SetMetaData('hunger', Math.Clamp(newHunger, 0, 100))
    --TriggerClientEvent('hud:client:UpdateStress', src, newStress)
    return newHunger
end

---@description Adds the specified value from the player's thirst level.
---@param src number
---@param value number
---@return number | nil
Framework.AddThirst = function(src, value)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    local newThirst = (playerData.metadata.thirst or 0) + value
    player.Functions.SetMetaData('thirst', Math.Clamp(newThirst, 0, 100))
    --TriggerClientEvent('hud:client:UpdateStress', src, newStress)
    return newThirst
end

---@description This will return the players hunger level.
---@param src number
---@return number | nil
Framework.GetHunger = function(src)
    local player = Framework.GetPlayer(src)
    if not player then return 0 end
    local playerData = player.PlayerData
    local newHunger = (playerData.metadata.hunger or 0)
    return math.floor((newHunger) + 0.5) or 0
end

---@description This will return a boolean if the player is dead or in last stand.
---@param src number
---@return boolean|nil
Framework.GetIsPlayerDead = function(src)
    local player = Framework.GetPlayer(src)
    if not player then return false end
    local playerData = player.PlayerData
    return playerData.metadata.isdead or false
end

---@description This will revive a player, if the player is dead or in last stand.
---@param src number
---@return boolean
Framework.RevivePlayer = function(src)
    src = tonumber(src)
    if not src then return false end
    TriggerClientEvent('hospital:client:Revive', src)
    return true
end

---@description This will return the players thirst level.
---@param src number
---@return number| nil
Framework.GetThirst = function(src)
    local player = Framework.GetPlayer(src)
    if not player then return 0 end
    local playerData = player.PlayerData
    local newThirst = (playerData.metadata.thirst or 0)
    return math.floor((newThirst) + 0.5) or 0
end

---@description Returns the phone number of the player.
---@param src number
---@return string | nil
Framework.GetPlayerPhone = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    return info.charinfo.phone
end

---@description Returns the gang name of the player.
---@param src number
---@return string | nil
Framework.GetPlayerGang = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    return info.gang.name
end

---@description This will get a table of player sources that have the specified job name.
---@param job string
---@return table
Framework.GetPlayersByJob = function(job)
    return Framework.GetPlayerSourcesByJob(job) or {}
end

---@description Depricated: Returns the job name, label, grade name, and grade level of the player.
---Please use GetPlayerJobData instead.
---@param src number
---@return string | string | string | number | nil
---@return string | string | string | number | nil
---@return string | string | string | number | nil
---@return string | string | string | number | nil
Framework.GetPlayerJob = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    --print("This function is depricated, please use GetPlayerJobData instead.")
    return info.job.name, info.job.label, info.job.grade.name, info.job.grade.level
end

---@description This will return the players job name, job label, job grade label job grade level, boss status, and duty status in a table
---@param src number
---@return table | nil
Framework.GetPlayerJobData = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    local jobData = info.job
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

---@description Sets the player's job to the specified name and grade.
---@param src number
---@param name string
---@param grade string
---@return boolean | nil
Framework.SetPlayerJob = function(src, name, grade)
    local player = Framework.GetPlayer(src)
    if not player then return end
    forgetPlayerInfo(src)
    local result = table.pack(player.Functions.SetJob(name, grade))
    forgetPlayerInfo(src)
    return table.unpack(result, 1, result.n)
end

---@description This will toggle the duty status of the player.
---qbx_core's SetJobDuty fires QBCore:Server:SetDuty with the new status itself.
---@param src number
---@param status boolean
Framework.SetPlayerDuty = function(src, status)
    local citizenid = Framework.GetPlayerIdentifier(src)
    if not citizenid then return end
    forgetPlayerInfo(src)
    QBox:SetJobDuty(citizenid, status)
    forgetPlayerInfo(src)
end

---@description Returns the players duty status.
---@param src number
---@return boolean | nil
Framework.GetPlayerDuty = function(src)
    local info = getPlayerInfo(src)
    if not info then return end
    if not info.job.onduty then return false end
    return true
end

---@description Adds the specified amount to the player's account balance of the specified type.
---@param src number
---@param _type string
---@param amount number
---@return boolean | nil
Framework.AddAccountBalance = function(src, _type, amount)
    local player = Framework.GetPlayer(src)
    if not player then return end
    if _type == 'money' then _type = 'cash' end
    if amount <= 0 then return false end
    return player.Functions.AddMoney(_type, amount)
end

---@description Removes the specified amount from the player's account balance of the specified type.
---@param src number
---@param _type string
---@param amount number
---@return boolean | nil
Framework.RemoveAccountBalance = function(src, _type, amount)
    local player = Framework.GetPlayer(src)
    if not player then return end
    if _type == 'money' then _type = 'cash' end
    if amount <= 0 then return false end
    return player.Functions.RemoveMoney(_type, amount)
end

---@description Returns the player's account balance of the specified type.
---@param src number
---@param _type string
---@return number | nil
Framework.GetAccountBalance = function(src, _type)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local playerData = player.PlayerData
    if _type == 'money' then _type = 'cash' end
    local balance = playerData.money[_type] or 0
    if balance <= 0 then return 0 end
    return balance
end

---@description Returns a table of owned vehicles for the player. format is {vehicle = vehicle, plate = plate}
---@param src number
---@return table
Framework.GetOwnedVehicles = function(src)
    local citizenId = Framework.GetPlayerIdentifier(src)
    local result = MySQL.Sync.fetchAll("SELECT vehicle, plate FROM player_vehicles WHERE citizenid = '" .. citizenId .. "'")
    local vehicles = {}
    for i = 1, #result do
        local vehicle = result[i].vehicle
        local plate = result[i].plate
        table.insert(vehicles, { vehicle = vehicle, plate = plate })
    end
    return vehicles
end

---@description Returns a table of owned vehicles for the player. format is {vehicle = model, plate = plate}
---@param src number
---@param plate string
---@return table
Framework.IsVehicleOwnedByPlayer = function(src, plate)
    local citizenId = Framework.GetPlayerIdentifier(src)
    local result = MySQL.Sync.fetchAll("SELECT vehicle, plate FROM player_vehicles WHERE citizenid = '" .. citizenId .. "' AND plate = '" .. plate .. "'")
    if not result[1] then return false end

    local id = result[1].id
    local vehicle = result[1].vehicle
    return { vehicle = vehicle, plate = plate }
end

---@description Returns the citizen identifier of the player who owns the vehicle with the given plate, or nil.
---@param plate string
---@return string|nil
Framework.GetVehicleOwner = function(plate)
    if not plate then return nil end
    local result = MySQL.query.await("SELECT citizenid FROM player_vehicles WHERE plate = ?", { plate })
    if result and result[1] then return result[1].citizenid end
    return nil
end

---@description Registers a usable item with a callback function.
---@param itemName string
---@param cb function
---@return function
Framework.RegisterUsableItem = function(itemName, cb)
    local func = function(src, item, itemData)
        itemData = itemData or item
        itemData.metadata = itemData.metadata or itemData.info or {}
        itemData.slot = itemData.id or itemData.slot
        cb(src, itemData)
    end
    return QBox:CreateUseableItem(itemName, func)
end

---@description Event handler for when a player is loaded in QBX Core framework
---qbx_core (client/character.lua), qbx_spawn and multicharacter resources fire it
---from the client with no argument (TriggerServerEvent): the sender is the player.
---@param src number
RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function(src)
    src = eventPlayer(src)
    if not src then return end
    forgetPlayerInfo(src)
    TriggerEvent("community_bridge:Server:OnPlayerLoaded", src)
    local jobData = Framework.GetPlayerJobData(src)
    if not jobData then return end
    Framework.AddJobCount(src, jobData.jobName)
end)

---@description Event handler for when a player is unloaded in QBX Core framework
---qbx_core fires it on the server with the player's source (Logout, server/player.lua),
---so it takes the argument path in eventPlayer; a client fire only ever acts on its sender.
---@param src number
RegisterNetEvent("QBCore:Server:OnPlayerUnload", function(src)
    src = eventPlayer(src)
    if not src then return end
    releasePlayerInfo(src)
    TriggerEvent("community_bridge:Server:OnPlayerUnload", src)
end)

---@description Event handler for when a player's job is updated in QBX Core framework
---qbx_core SetPlayerPrimaryJob and Player.Functions.SetJob (server/player.lua:211,
---979) fire it with TriggerEvent(..., source, job).
---@param src number
---@param job table
RegisterNetEvent("QBCore:Server:OnJobUpdate", function(src, job)
    src = eventPlayer(src)
    if not src then return end
    forgetPlayerInfo(src)
    if not job then return end
    TriggerEvent("community_bridge:Server:OnPlayerJobChange", src, job.name)
end)

-- Cached identity/job invalidation only (see PLAYER_INFO_TTL_MS). Server-side
-- events: AddEventHandler, so a client cannot fire them here.
AddEventHandler("QBCore:Server:SetDuty", function(src)
    forgetPlayerInfo(src)
end)

AddEventHandler("QBCore:Server:OnGangUpdate", function(src)
    forgetPlayerInfo(src)
end)

-- RemovePlayerFromJob/Gang can move a player off their primary job or gang
-- without QBCore:Server:OnJobUpdate/OnGangUpdate.
AddEventHandler("qbx_core:server:onGroupUpdate", function(src)
    forgetPlayerInfo(src)
end)

AddEventHandler("qbx_core:server:playerLoggedOut", function(src)
    releasePlayerInfo(src)
end)

---@description Event handler for when a player disconnects from the server
AddEventHandler("playerDropped", function()
    local src = source
    releasePlayerInfo(src)
    TriggerEvent("community_bridge:Server:OnPlayerUnload", src)
end)

return Framework
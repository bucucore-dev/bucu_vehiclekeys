-- ============================================================================
-- BUCU Vehicle Keys System — Server Main Handler
-- ============================================================================

local PlayerKeys = {} -- [citizenid] = { [plate] = true }
local VehicleLocks = {} -- [plate] = 1 (unlocked) or 2 (locked)
local isOxLoaded = (MySQL ~= nil)

local function getPlayerData(src)
    if Bucu and Bucu.Player and Bucu.Player.Get then
        local p = Bucu.Player:Get(src)
        if p then
            local char = p:GetChar() or {}
            local name = (char.first_name and char.last_name) and (char.first_name .. " " .. char.last_name) or ("Citizen #" .. tostring(src))
            return p:GetCitizenId(), name
        end
    end
    return "citizen_" .. tostring(src), "Resident " .. tostring(src)
end

local function hasKey(src, plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    if plate == "" then return false end

    local cid = getPlayerData(src)
    if PlayerKeys[cid] and PlayerKeys[cid][plate] then
        return true
    end

    -- Check database ownership if oxmysql available
    if isOxLoaded and MySQL and MySQL.query then
        local rows = MySQL.query.await("SELECT id FROM bucu_vehicles WHERE plate = ? AND citizenid = ? LIMIT 1", { plate, cid })
        if rows and #rows > 0 then
            PlayerKeys[cid] = PlayerKeys[cid] or {}
            PlayerKeys[cid][plate] = true
            return true
        end
    end

    return false
end

local function giveKey(src, plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    if plate == "" then return false end

    local cid = getPlayerData(src)
    PlayerKeys[cid] = PlayerKeys[cid] or {}
    PlayerKeys[cid][plate] = true

    TriggerClientEvent('bucu:vehiclekeys:keyAdded', src, plate)
    return true
end

local function removeKey(src, plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    local cid = getPlayerData(src)
    if PlayerKeys[cid] then
        PlayerKeys[cid][plate] = nil
    end
    return true
end

-- ============================================================================
-- Network Events
-- ============================================================================

-- Toggle Vehicle Door Lock
RegisterNetEvent('bucu:vehiclekeys:toggleLock', function(netId, plate)
    local src = source
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")

    if not hasKey(src, plate) then
        TriggerClientEvent('bucu:vehiclekeys:notify', src, false, "no_keys")
        return
    end

    local currentLock = VehicleLocks[plate] or 1
    local newLock = (currentLock == 1) and 2 or 1
    VehicleLocks[plate] = newLock

    -- Sync door lock state to all clients
    TriggerClientEvent('bucu:vehiclekeys:syncLock', -1, netId, newLock, plate)

    local notifyKey = (newLock == 2) and "locked" or "unlocked"
    TriggerClientEvent('bucu:vehiclekeys:notify', src, true, notifyKey)
end)

-- Share Vehicle Key with target player (/givekeys)
RegisterNetEvent('bucu:vehiclekeys:shareKey', function(targetSrc, plate)
    local src = source
    targetSrc = tonumber(targetSrc) or 0
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")

    if not hasKey(src, plate) then
        TriggerClientEvent('bucu:vehiclekeys:notify', src, false, "no_keys")
        return
    end

    if targetSrc <= 0 or targetSrc == src then
        TriggerClientEvent('bucu:vehiclekeys:notify', src, false, "no_player_nearby")
        return
    end

    giveKey(targetSrc, plate)
    local _, targetName = getPlayerData(targetSrc)

    TriggerClientEvent('bucu:vehiclekeys:notify', src, true, "keys_shared", plate, targetName)
    TriggerClientEvent('bucu:vehiclekeys:notify', targetSrc, true, "keys_received", plate)
end)

-- Lockpick completion handler
RegisterNetEvent('bucu:vehiclekeys:lockpickCompleted', function(success, plate)
    local src = source
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")

    if success then
        giveKey(src, plate)
        TriggerClientEvent('bucu:vehiclekeys:notify', src, true, "lockpick_success")
    else
        TriggerClientEvent('bucu:vehiclekeys:notify', src, false, "lockpick_failed")

        -- Chance to break lockpick item
        local roll = math.random(1, 100)
        if roll <= VehicleKeysConfig.BreakLockpickChance then
            if exports and exports.bucu_inventory and exports.bucu_inventory.RemoveItem then
                exports.bucu_inventory:RemoveItem(src, 'lockpick', 1)
                TriggerClientEvent('bucu:vehiclekeys:notify', src, false, "lockpick_broken")
            end
        end
    end
end)

-- Register lockpick as usable item
CreateThread(function()
    Wait(1500)
    if exports and exports.bucu_inventory and exports.bucu_inventory.CreateUsableItem then
        exports.bucu_inventory:CreateUsableItem('lockpick', function(src, item)
            TriggerClientEvent('bucu:vehiclekeys:useLockpick', src)
        end)
    end
end)

-- Handler for acquiring keys from NPC carjacking, running engine, or hotwire
RegisterNetEvent('bucu:vehiclekeys:server:acquireNpcKeys', function(plate)
    local src = source
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    if plate == "" then return end

    giveKey(src, plate)
end)

-- ============================================================================
-- Public Exports
-- ============================================================================

exports('HasKey', hasKey)
exports('GiveKey', giveKey)
exports('RemoveKey', removeKey)

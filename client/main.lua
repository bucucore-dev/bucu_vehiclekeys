-- ============================================================================
-- BUCU Vehicle Keys System — Client Main Logic
-- ============================================================================

local localKeys = {} -- [plate] = true

local function getLocale(key, ...)
    local lang = VehicleKeysConfig.Language or 'en'
    local dict = VehicleKeysLocales[lang] or VehicleKeysLocales['en']
    local str = dict[key] or key
    if ... then
        return string.format(str, ...)
    end
    return str
end

local function notify(isSuccess, key, ...)
    local msg = getLocale(key, ...)
    local nType = isSuccess and "success" or "error"
    if exports and exports.bucu_notify and exports.bucu_notify.Notify then
        exports.bucu_notify:Notify(msg, nType, 3000)
    else
        BeginTextCommandThefeedPost("STRING")
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

RegisterNetEvent('bucu:vehiclekeys:notify', notify)

RegisterNetEvent('bucu:vehiclekeys:keyAdded', function(plate)
    localKeys[plate] = true
end)

-- Find closest vehicle within max distance
local function getClosestVehicle(maxDist)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then return veh end

    local handle, entity = FindFirstVehicle()
    local success = true
    local closestVeh = nil
    local closestDist = maxDist or VehicleKeysConfig.LockDistance or 15.0

    while success do
        if DoesEntityExist(entity) then
            local vCoords = GetEntityCoords(entity)
            local dist = #(pCoords - vCoords)
            if dist < closestDist then
                closestDist = dist
                closestVeh = entity
            end
        end
        success, entity = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)
    return closestVeh
end

-- Play key fob remote animation
local function playFobAnimation()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        local dict = "anim@mp_player_intmenu@key_fob@"
        RequestAnimDict(dict)
        local timeout = 800
        while not HasAnimDictLoaded(dict) and timeout > 0 do
            Wait(50)
            timeout = timeout - 50
        end
        if HasAnimDictLoaded(dict) then
            TaskPlayAnim(ped, dict, "fob_click", 8.0, -8.0, 900, 48, 0, false, false, false)
        end
    end
end

-- Blink headlights twice
local function blinkVehicleLights(veh)
    SetVehicleLights(veh, 2)
    Wait(150)
    SetVehicleLights(veh, 0)
    Wait(150)
    SetVehicleLights(veh, 2)
    Wait(150)
    SetVehicleLights(veh, 0)
end

-- Synchronize vehicle lock status across clients
RegisterNetEvent('bucu:vehiclekeys:syncLock', function(netId, lockStatus, plate)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, lockStatus)
        CreateThread(function()
            blinkVehicleLights(veh)
        end)
    end
end)

-- Toggle Lock Action
local function toggleLock()
    local veh = getClosestVehicle(VehicleKeysConfig.LockDistance)
    if not veh or not DoesEntityExist(veh) then return end

    local plate = GetVehicleNumberPlateText(veh)
    playFobAnimation()
    TriggerServerEvent('bucu:vehiclekeys:toggleLock', VehToNet(veh), plate)
end

RegisterCommand('togglelock', toggleLock, false)
RegisterKeyMapping('togglelock', 'Toggle Vehicle Door Lock', 'keyboard', VehicleKeysConfig.DefaultKeybind or 'L')

-- ============================================================================
-- Lockpick Usable Item Action
-- ============================================================================

RegisterNetEvent('bucu:vehiclekeys:useLockpick', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local veh = getClosestVehicle(3.0)
    if not veh or not DoesEntityExist(veh) then
        notify(false, "no_player_nearby")
        return
    end

    local plate = GetVehicleNumberPlateText(veh)
    local duration = VehicleKeysConfig.LockpickDuration or 7000

    if exports and exports.bucu_notify and exports.bucu_notify.ProgressBar then
        exports.bucu_notify:ProgressBar(getLocale('lockpick_started'), duration, {
            cancelOnMove = true,
            anim = { dict = "veh@break_in@0h@p_m_one@", anim = "low_force_entry_ds" }
        }, function()
            local roll = math.random(1, 100)
            local success = (roll <= (VehicleKeysConfig.LockpickChance or 75))
            TriggerServerEvent('bucu:vehiclekeys:lockpickCompleted', success, plate)
        end, function()
            notify(false, "lockpick_failed")
        end)
    else
        TriggerServerEvent('bucu:vehiclekeys:lockpickCompleted', true, plate)
    end
end)

-- ============================================================================
-- NPC Carjacking & Ignition Key Detection
-- ============================================================================

local lastCarjackedPlate = nil
local lastCarjackedVeh = nil
local lastCarjackedTime = 0
local currentVeh = nil
local isHotwiring = false
local hotwiringVeh = nil
local hotwiringPlate = nil

-- Track carjacking in real-time when player drags an NPC out of a vehicle
CreateThread(function()
    while true do
        Wait(100)
        local ped = PlayerPedId()
        if IsPedJacking(ped) then
            local targetPed = GetJackingPed(ped)
            if targetPed and DoesEntityExist(targetPed) and not IsPedAPlayer(targetPed) then
                local veh = GetVehiclePedIsUsing(targetPed)
                if not veh or veh == 0 then
                    veh = GetVehiclePedIsTryingToEnter(ped)
                end
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                    local plate = GetVehicleNumberPlateText(veh)
                    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
                    if plate ~= "" then
                        lastCarjackedPlate = plate
                        lastCarjackedVeh = veh
                        lastCarjackedTime = GetGameTimer()
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- Hotwire Action Handler, Dynamic Camera & Interactive Minigame Bridge
-- ============================================================================

local hotwireCam = nil

-- Dynamic in-vehicle cinematic camera: placed at passenger side eye-level (samping kanan pemain)
-- looking diagonally across at the steering column, dashboard & hands (zero clipping)
local function getHotwireCamCoords(veh, ped)
    local pCoords = GetEntityCoords(ped)
    local vOffset = GetOffsetFromEntityGivenWorldCoords(veh, pCoords.x, pCoords.y, pCoords.z)
    local isDriverLeft = (vOffset.x <= 0.05)
    local vClass = GetVehicleClass(veh)

    -- Motorcycles, Quads, Bicycles, Boats
    if vClass == 8 or vClass == 13 or vClass == 3 or vClass == 14 then
        local camPos = GetOffsetFromEntityInWorldCoords(veh, 1.10, 0.60, 0.75)
        local tgtPos = GetOffsetFromEntityInWorldCoords(veh, 0.00, 0.10, 0.45)
        return camPos, tgtPos, 64.0
    end

    -- Standard cars, trucks, SUVs:
    -- If driver is on the LEFT:
    -- Camera is placed on passenger seat at eye level (+X = kanan pemain, -Y = bahu penumpang, +Z = ketinggian mata)
    -- Target is pointing at the ignition switch / lower dashboard under the steering wheel
    if isDriverLeft then
        local camPos = GetOffsetFromEntityInWorldCoords(veh, 0.52, -0.18, 0.52)
        local tgtPos = GetOffsetFromEntityInWorldCoords(veh, -0.32, 0.32, 0.28)
        return camPos, tgtPos, 62.0
    else
        -- Right-hand drive vehicle: camera on left passenger side
        local camPos = GetOffsetFromEntityInWorldCoords(veh, -0.52, -0.18, 0.52)
        local tgtPos = GetOffsetFromEntityInWorldCoords(veh, 0.32, 0.32, 0.28)
        return camPos, tgtPos, 62.0
    end
end

local function createHotwireCamera(veh, ped)
    if hotwireCam and DoesCamExist(hotwireCam) then
        DestroyCam(hotwireCam, false)
        hotwireCam = nil
    end

    local camPos, tgtPos, fov = getHotwireCamCoords(veh, ped)

    hotwireCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(hotwireCam, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(hotwireCam, tgtPos.x, tgtPos.y, tgtPos.z)
    SetCamFov(hotwireCam, fov or 62.0)
    SetCamActive(hotwireCam, true)
    RenderScriptCams(true, true, 500, true, true)

    -- Tracking loop locked to vehicle orientation and motion
    CreateThread(function()
        while isHotwiring and hotwireCam and DoesCamExist(hotwireCam) do
            Wait(0)
            if DoesEntityExist(veh) then
                local cPos, tPos = getHotwireCamCoords(veh, ped)
                SetCamCoord(hotwireCam, cPos.x, cPos.y, cPos.z)
                PointCamAtCoord(hotwireCam, tPos.x, tPos.y, tPos.z)
            end
        end
    end)
end

local function destroyHotwireCamera()
    if hotwireCam and DoesCamExist(hotwireCam) then
        RenderScriptCams(false, true, 500, true, true)
        local camToDestroy = hotwireCam
        hotwireCam = nil
        CreateThread(function()
            Wait(500)
            if DoesCamExist(camToDestroy) then
                DestroyCam(camToDestroy, false)
            end
        end)
    end
end

-- Cancel / Exit Hotwire cleanly at any time
local function cancelHotwire()
    if not isHotwiring then return end
    isHotwiring = false

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'CANCEL_HOTWIRE' })
    destroyHotwireCamera()
    ClearPedTasks(PlayerPedId())

    hotwiringVeh = nil
    hotwiringPlate = nil
end

local function startHotwire(veh, plate)
    if isHotwiring then return end
    isHotwiring = true
    hotwiringVeh = veh
    hotwiringPlate = plate

    local ped = PlayerPedId()

    -- 1. Play in-vehicle wiring animation (lean under steering column)
    local dict = "anim@veh@break_in@0h@p_m_one@"
    local anim = "low_force_entry_ds"
    RequestAnimDict(dict)
    local timeout = 800
    while not HasAnimDictLoaded(dict) and timeout > 0 do
        Wait(50)
        timeout = timeout - 50
    end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
    end

    -- 2. Trigger NUI Minigame HUD (Right-aligned BUCU Card)
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'START_HOTWIRE',
        stages = 3,
        lang = VehicleKeysConfig.Language or 'id',
        plate = plate
    })

    -- 3. Create dynamic cinematic in-vehicle camera from passenger side (samping kanan pemain)
    createHotwireCamera(veh, ped)

    -- 4. Watchdog & Emergency Cancel Loop
    CreateThread(function()
        while isHotwiring do
            Wait(50)
            local p = PlayerPedId()

            -- Cancel if player exited, died, or car disappeared
            if not IsPedInAnyVehicle(p, false) or IsPedDeadOrDying(p) or not DoesEntityExist(veh) then
                cancelHotwire()
                break
            end

            -- Maintain animation loop
            if not IsEntityPlayingAnim(p, dict, anim, 3) then
                TaskPlayAnim(p, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end
    end)
end

-- Minigame NUI Result Callback
RegisterNUICallback('hotwireResult', function(data, cb)
    cb('ok')
    SetNuiFocus(false, false)

    local ped = PlayerPedId()
    ClearPedTasks(ped)
    destroyHotwireCamera()

    if not isHotwiring then return end
    isHotwiring = false

    local veh = hotwiringVeh
    local plate = hotwiringPlate or (data and data.plate)

    if not veh or not DoesEntityExist(veh) then
        veh = GetVehiclePedIsIn(ped, false)
    end

    if data and data.cancelled then
        hotwiringVeh = nil
        hotwiringPlate = nil
        return
    end

    if data and data.success then
        if plate and plate ~= "" then
            localKeys[plate] = true
            TriggerServerEvent('bucu:vehiclekeys:server:acquireNpcKeys', plate)
        end
        if veh and DoesEntityExist(veh) then
            SetVehicleEngineOn(veh, true, true, false)
            SetVehicleUndriveable(veh, false)
        end
        notify(true, "hotwire_success")
    else
        -- Failed hotwire: trigger alarm sound and warning notification
        if veh and DoesEntityExist(veh) then
            SetVehicleAlarm(veh, true)
            StartVehicleAlarm(veh)
            SetVehicleAlarmTimeLeft(veh, 4000)
        end
        notify(false, "hotwire_failed")
    end

    hotwiringVeh = nil
    hotwiringPlate = nil
end)

-- Safe cleanup if resource stops during hotwire
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if isHotwiring then
            SetNuiFocus(false, false)
            destroyHotwireCamera()
            ClearPedTasks(PlayerPedId())
        end
    end
end)

RegisterCommand('hotwire', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if GetPedInVehicleSeat(veh, -1) == ped and GetVehicleClass(veh) ~= 13 then
            local plate = GetVehicleNumberPlateText(veh)
            plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
            if not localKeys[plate] then
                startHotwire(veh, plate)
            end
        end
    end
end, false)

RegisterCommand('cancelhotwire', function()
    if isHotwiring then
        cancelHotwire()
    end
end, false)

-- Hotwire UI Prompt (Press H when in driver seat without key)
CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped and GetVehicleClass(veh) ~= 13 then
                local plate = GetVehicleNumberPlateText(veh)
                plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
                local hasKey = localKeys[plate] or false

                if not hasKey and not isHotwiring and (VehicleKeysConfig.EnableHotwire ~= false) then
                    sleep = 0
                    BeginTextCommandDisplayHelp("STRING")
                    AddTextComponentSubstringPlayerName(getLocale("hotwire_prompt"))
                    EndTextCommandDisplayHelp(0, false, true, 1)

                    if IsControlJustPressed(0, 74) then -- 74 = 'H' key in GTA V
                        startHotwire(veh, plate)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ============================================================================
-- Engine State & Inhibitor Thread
-- ============================================================================

CreateThread(function()
    while true do
        Wait(200)
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if GetPedInVehicleSeat(veh, -1) == ped then
                local isBicycle = (GetVehicleClass(veh) == 13)
                if isBicycle then
                    SetVehicleUndriveable(veh, false)
                else
                    local plate = GetVehicleNumberPlateText(veh)
                    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")

                    -- When newly entering this vehicle as driver
                    if veh ~= currentVeh then
                        currentVeh = veh
                        local wasRunning = GetIsVehicleEngineRunning(veh)

                        if plate ~= "" and not localKeys[plate] then
                            local wasCarjacked = (lastCarjackedVeh == veh or (lastCarjackedPlate == plate and (GetGameTimer() - lastCarjackedTime) < 15000))

                            if wasCarjacked and (VehicleKeysConfig.AutoKeyOnCarjack ~= false) then
                                -- Stolen directly from NPC: snatch keys
                                localKeys[plate] = true
                                lastCarjackedVeh = nil
                                lastCarjackedPlate = nil
                                TriggerServerEvent('bucu:vehiclekeys:server:acquireNpcKeys', plate)
                                SetVehicleEngineOn(veh, true, true, false)
                                SetVehicleUndriveable(veh, false)
                                notify(true, "npc_keys_acquired")
                            elseif wasRunning and (VehicleKeysConfig.KeyInIgnitionIfRunning ~= false) then
                                -- Engine was already running (keys left in ignition)
                                localKeys[plate] = true
                                TriggerServerEvent('bucu:vehiclekeys:server:acquireNpcKeys', plate)
                                SetVehicleEngineOn(veh, true, true, false)
                                SetVehicleUndriveable(veh, false)
                                notify(true, "keys_in_ignition")
                            end
                        end
                    end

                    -- Inhibitor check
                    local hasKey = localKeys[plate] or false
                    if not hasKey then
                        if GetIsVehicleEngineRunning(veh) then
                            SetVehicleEngineOn(veh, false, true, true)
                        end
                        SetVehicleUndriveable(veh, true)
                    else
                        SetVehicleUndriveable(veh, false)
                    end
                end
            else
                currentVeh = nil
            end
        else
            currentVeh = nil
        end
    end
end)

-- Share Keys Command: /givekeys
RegisterCommand('givekeys', function()
    local ped = PlayerPedId()
    local veh = getClosestVehicle(4.0)
    if not veh or not DoesEntityExist(veh) then return end

    local plate = GetVehicleNumberPlateText(veh)
    local pCoords = GetEntityCoords(ped)
    local closestPlayer, closestDist = -1, 3.0

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            local tCoords = GetEntityCoords(targetPed)
            local dist = #(pCoords - tCoords)
            if dist < closestDist then
                closestDist = dist
                closestPlayer = player
            end
        end
    end

    if closestPlayer ~= -1 then
        local targetServerId = GetPlayerServerId(closestPlayer)
        TriggerServerEvent('bucu:vehiclekeys:shareKey', targetServerId, plate)
    else
        notify(false, "no_player_nearby")
    end
end, false)

-- ============================================================================
-- Public Client Exports
-- ============================================================================

exports('GiveKey', function(plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    if plate == "" then return false end
    localKeys[plate] = true
    TriggerServerEvent('bucu:vehiclekeys:server:acquireNpcKeys', plate)
    return true
end)

exports('HasKey', function(plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    return localKeys[plate] or false
end)

exports('RemoveKey', function(plate)
    plate = tostring(plate or ""):gsub("^%s*(.-)%s*$", "%1")
    localKeys[plate] = nil
    return true
end)


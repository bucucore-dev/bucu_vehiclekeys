-- ============================================================================
-- BUCU Vehicle Keys System — Cross-Framework Compatibility Bridge
-- Shims for qb-vehiclekeys and wasabi_carlock
-- ============================================================================

-- QBCore Emulation: qb-vehiclekeys:server:AcquireVehicleKeys
RegisterNetEvent('qb-vehiclekeys:server:AcquireVehicleKeys', function(plate)
    local src = source
    if exports.bucu_vehiclekeys and exports.bucu_vehiclekeys.GiveKey then
        exports.bucu_vehiclekeys:GiveKey(src, plate)
    end
end)

-- Standard exports emulation
exports('HasKeys', function(plate)
    local src = source
    if exports.bucu_vehiclekeys and exports.bucu_vehiclekeys.HasKey then
        return exports.bucu_vehiclekeys:HasKey(src, plate)
    end
    return false
end)

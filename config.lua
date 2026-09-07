-- ============================================================================
-- BUCU Vehicle Keys System — Configuration
-- ============================================================================

VehicleKeysConfig = {}

VehicleKeysConfig.Language = 'en'
VehicleKeysConfig.LockDistance = 15.0       -- Remote key fob interaction radius
VehicleKeysConfig.DefaultKeybind = 'L'      -- Keyboard toggle lock keybind
VehicleKeysConfig.LockpickDuration = 7000   -- Duration in ms to lockpick a vehicle
VehicleKeysConfig.LockpickChance = 75       -- 75% success chance
VehicleKeysConfig.BreakLockpickChance = 30  -- 30% chance to break lockpick item on fail

-- NPC & Vehicle Stealing Mechanics
VehicleKeysConfig.AutoKeyOnCarjack = true       -- Automatically snatch keys when carjacking an NPC driver
VehicleKeysConfig.KeyInIgnitionIfRunning = true  -- If NPC vehicle engine was running when entered, keep engine on and grant keys
VehicleKeysConfig.EnableHotwire = true         -- Enable hotwiring empty/parked NPC vehicles without keys
VehicleKeysConfig.HotwireDuration = 4000       -- Duration in ms to hotwire vehicle ignition
VehicleKeysConfig.HotwireChance = 85           -- 85% success chance to hotwire


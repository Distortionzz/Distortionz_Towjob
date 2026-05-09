-- =====================================================================
--  Distortionz Tow Job · client.lua
-- =====================================================================

local yardPed         = nil
local yardBlip        = nil
local flatbed         = nil
local onDuty          = false
local activeCall      = nil   -- { spawn, model, plate, label, vehicle, blip, timeoutEpoch }
local pickedUp        = false
local pickupCoords    = nil   -- vec3 of where the player attached the car (for distance bonus)

-- ─── Notify wrapper ─────────────────────────────────────────────────

local function Notify(message, notifyType, duration, title)
    if not message then return end

    notifyType = notifyType or 'primary'
    duration   = tonumber(duration) or Config.Notify.defaultLength
    title      = title or Config.Notify.title

    if notifyType == 'inform' then notifyType = 'info' end

    if GetResourceState(Config.Notify.resource) == 'started' then
        exports[Config.Notify.resource]:Notify(message, notifyType, duration, title)
        return
    end

    lib.notify({
        title       = title,
        description = message,
        type        = notifyType,
        duration    = duration,
    })
end

-- ─── HUD bridge ─────────────────────────────────────────────────────

local function HudShow(payload)
    SendNUIMessage({ action = 'show', data = payload })
end

local function HudUpdate(payload)
    SendNUIMessage({ action = 'update', data = payload })
end

local function HudHide()
    SendNUIMessage({ action = 'hide' })
end

local function HudSnapshot()
    local secs = 0
    if activeCall and activeCall.timeoutEpoch then
        secs = math.max(0, math.floor((activeCall.timeoutEpoch - GetGameTimer()) / 1000))
    end

    return {
        onDuty    = onDuty,
        hasCall   = activeCall ~= nil,
        pickedUp  = pickedUp,
        callLabel  = activeCall and activeCall.label  or '',
        callModel  = activeCall and activeCall.model  or '',
        callPlate  = activeCall and activeCall.plate  or '',
        callReason = activeCall and activeCall.reason or '',
        timeLeft   = secs,
        version    = Config.CurrentVersion,
        repo       = Config.Repo,
    }
end

-- ─── HUD live tick ──────────────────────────────────────────────────

CreateThread(function()
    while true do
        if onDuty then
            HudUpdate(HudSnapshot())
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

-- ─── Towed-vehicle hazard lights tick ──────────────────────────────
-- Indicators reset every frame in GTA, so they have to be re-applied
-- per-frame. Adaptive wait keeps this thread idle when no tow is active.

CreateThread(function()
    while true do
        if activeCall and pickedUp and activeCall.vehicle and DoesEntityExist(activeCall.vehicle) then
            SetVehicleIndicatorLights(activeCall.vehicle, 0, true)  -- left
            SetVehicleIndicatorLights(activeCall.vehicle, 1, true)  -- right (both on = hazards)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ─── Yard blip ──────────────────────────────────────────────────────

local function CreateYardBlip()
    if not Config.Yard.blip.enabled then return end
    if yardBlip then return end

    local c = Config.Yard.ped.coords
    yardBlip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(yardBlip, Config.Yard.blip.sprite)
    SetBlipColour(yardBlip, Config.Yard.blip.color)
    SetBlipScale(yardBlip, Config.Yard.blip.scale)
    SetBlipAsShortRange(yardBlip, Config.Yard.blip.shortRange)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Yard.blip.label)
    EndTextCommandSetBlipName(yardBlip)
end

-- ─── Yard ped ───────────────────────────────────────────────────────

local function SpawnYardPed()
    if not Config.Yard.ped.enabled then return end
    if yardPed and DoesEntityExist(yardPed) then return end

    local pedConfig = Config.Yard.ped
    local hash = joaat(pedConfig.model)
    lib.requestModel(hash, 10000)

    local c = pedConfig.coords
    yardPed = CreatePed(0, hash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(yardPed, true)
    SetBlockingOfNonTemporaryEvents(yardPed, true)
    FreezeEntityPosition(yardPed, true)
    SetPedDiesWhenInjured(yardPed, false)

    -- Distortionz protected ped flags
    Entity(yardPed).state:set('distortionz_protected_ped', true, true)
    Entity(yardPed).state:set('distortionz_contact_ped',   true, true)
    Entity(yardPed).state:set('distortionz_towjob_ped',    true, true)

    if pedConfig.scenario and pedConfig.scenario ~= '' then
        TaskStartScenarioInPlace(yardPed, pedConfig.scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(hash)

    exports.ox_target:addLocalEntity(yardPed, {
        {
            name     = 'distortionz_towjob_clockon',
            label    = 'Clock on',
            icon     = Config.Yard.target.icon,
            distance = Config.Yard.target.distance,
            canInteract = function() return not onDuty end,
            onSelect = function() TriggerEvent('distortionz_towjob:client:clockOn') end,
        },
        {
            name     = 'distortionz_towjob_requestflatbed',
            label    = 'Request flatbed',
            icon     = 'fa-solid fa-truck-pickup',
            distance = Config.Yard.target.distance,
            canInteract = function() return onDuty and not (flatbed and DoesEntityExist(flatbed)) end,
            onSelect = function() TriggerEvent('distortionz_towjob:client:requestFlatbed') end,
        },
        {
            name     = 'distortionz_towjob_clockoff',
            label    = 'Clock off',
            icon     = 'fa-solid fa-power-off',
            distance = Config.Yard.target.distance,
            canInteract = function() return onDuty end,
            onSelect = function() TriggerEvent('distortionz_towjob:client:clockOff') end,
        },
    })
end

-- ─── Flatbed handling ───────────────────────────────────────────────

local function SpawnFlatbed(model, color, plate)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        Notify('Invalid flatbed model.', 'error', 5000)
        return nil
    end

    lib.requestModel(hash, 10000)

    local s = Config.Yard.flatbedSpawn
    local veh = CreateVehicle(hash, s.x, s.y, s.z, s.w, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(veh) then return nil end

    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, plate or 'TOW')
    if color and color[1] then
        SetVehicleColours(veh, color[1], color[2] or color[1])
    end
    -- prevent qbx_vehiclekeys auto-lock
    Entity(veh).state:set('doorslockstate', 1, true)
    SetEntityAsMissionEntity(veh, true, true)

    -- Cosmetic / mechanical reset — every flatbed leaves the yard pristine
    SetVehicleDirtLevel(veh, 0.0)
    WashDecalsFromVehicle(veh, 1.0)
    SetVehicleFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleDeformationFixed(veh)
    SetVehicleUndriveable(veh, false)
    SetVehicleCanBeVisiblyDamaged(veh, true)

    -- Disable radio (job vehicle, no music)
    SetVehicleRadioEnabled(veh, false)
    SetVehRadioStation(veh, 'OFF')

    -- Grant the player flatbed keys (qbx_vehiclekeys integration) so the engine works
    local netId = NetworkGetNetworkIdFromEntity(veh)
    if netId and netId ~= 0 then
        TriggerServerEvent('distortionz_towjob:server:grantFlatbedKeys', netId)
    end

    -- Add a "Return flatbed" target action
    exports.ox_target:addLocalEntity(veh, {
        {
            name     = 'distortionz_towjob_returnflatbed',
            label    = 'Return flatbed',
            icon     = 'fa-solid fa-rotate-left',
            distance = 2.5,
            canInteract = function() return onDuty end,
            onSelect = function() TriggerEvent('distortionz_towjob:client:returnFlatbed') end,
        },
    })

    return veh
end

local function DespawnFlatbed()
    if flatbed and DoesEntityExist(flatbed) then
        SetEntityAsMissionEntity(flatbed, true, true)
        DeleteVehicle(flatbed)
    end
    flatbed = nil
end

-- ─── Spawn the abandoned target vehicle (call) ──────────────────────

local function SpawnCallVehicle(call)
    local hash = joaat(call.model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        Notify('Dispatch model invalid. Resetting call.', 'error', 5000)
        TriggerServerEvent('distortionz_towjob:server:cancelCall')
        return nil
    end

    lib.requestModel(hash, 10000)

    local c = call.spawn.coords
    local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(veh) then return nil end

    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, call.plate)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleDoorsLocked(veh, 2)  -- abandoned + locked, but we're towing not driving
    Entity(veh).state:set('doorslockstate', 2, true)
    SetEntityAsMissionEntity(veh, true, true)

    -- Random scuffed paint
    SetVehicleDirtLevel(veh, 12.0 + math.random() * 3.0)

    return veh
end

-- ─── Attach / detach (flatbed lift) ─────────────────────────────────

local function AttachToFlatbed(targetVeh)
    if not flatbed or not DoesEntityExist(flatbed) then
        Notify('You need a flatbed nearby to hook the vehicle.', 'warning', 5000)
        return false
    end

    local fb = GetEntityCoords(flatbed)
    local tv = GetEntityCoords(targetVeh)
    if #(fb - tv) > (Config.Attach and Config.Attach.maxDistance or 10.0) then
        Notify('Pull the flatbed closer to the target vehicle.', 'warning', 5000)
        return false
    end

    -- Attach behind the flatbed
    local off = (Config.Attach and Config.Attach.offset) or { x = 0.0, y = -2.6, z = 1.0 }
    AttachEntityToEntity(targetVeh, flatbed,
        0,
        off.x, off.y, off.z,
        0.0, 0.0, 0.0,
        false, false, false, false,
        20, true)

    -- Engine ON so the electrical system powers the indicators / hazard lights.
    -- The vehicle is attached to the flatbed so it can't drive itself anywhere.
    -- Hazard tick (separate thread) hammers SetVehicleIndicatorLights every
    -- frame so they keep blinking the whole transport.
    SetVehicleEngineOn(targetVeh, true, true, false)
    -- Force lights on (mode 2) — taillights visible at night so following
    -- traffic can see the load.
    SetVehicleLights(targetVeh, 2)
    return true
end

local function DetachFromFlatbed(targetVeh)
    if targetVeh and DoesEntityExist(targetVeh) then
        DetachEntity(targetVeh, true, true)
    end
end

-- ─── Active-call vehicle target hooks ───────────────────────────────

local function SwitchToDropoffBlip()
    if not activeCall then return end

    -- Drop the call-spot blip (it has the GPS route on the abandoned car)
    if activeCall.blip and DoesBlipExist(activeCall.blip) then
        RemoveBlip(activeCall.blip)
        activeCall.blip = nil
    end

    -- Create a new GPS route to the yard dropoff
    local d = Config.Yard.dropoff.coords
    local blip = AddBlipForCoord(d.x, d.y, d.z)
    SetBlipSprite(blip, 68)         -- tow truck icon
    SetBlipColour(blip, Config.Dispatch.blipColor or 5)
    SetBlipScale(blip, 0.95)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, Config.Dispatch.blipColor or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Tow Yard — Drop Off')
    EndTextCommandSetBlipName(blip)

    activeCall.dropoffBlip = blip
end

local function AttachCallTargets(veh)
    exports.ox_target:addLocalEntity(veh, {
        {
            name     = 'distortionz_towjob_hook',
            label    = 'Hook to flatbed',
            icon     = 'fa-solid fa-link',
            distance = 3.5,
            canInteract = function() return onDuty and activeCall and not pickedUp end,
            onSelect = function()
                if not activeCall or pickedUp then return end
                local ok = AttachToFlatbed(veh)
                if ok then
                    pickedUp     = true
                    pickupCoords = GetEntityCoords(veh)
                    TriggerServerEvent('distortionz_towjob:server:confirmPickup')
                    SwitchToDropoffBlip()
                end
            end,
        },
    })
end

-- ─── Drop-off zone watcher ──────────────────────────────────────────

CreateThread(function()
    while true do
        local sleep = 1500

        if onDuty and activeCall and pickedUp and DoesEntityExist(activeCall.vehicle) then
            local pCoords = GetEntityCoords(PlayerPedId())
            local d = #(pCoords - Config.Yard.dropoff.coords)

            if d <= Config.Yard.dropoff.radius then
                sleep = 0
                lib.showTextUI('[E] Drop off vehicle', { position = 'right-center' })

                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()

                    local engineHp = GetVehicleEngineHealth(activeCall.vehicle) or 1000.0
                    local bodyHp   = GetVehicleBodyHealth(activeCall.vehicle)   or 1000.0
                    local distKm   = 0.0
                    if pickupCoords then
                        distKm = #(pCoords - pickupCoords) / 1000.0
                    end

                    local result = lib.callback.await('distortionz_towjob:server:deliver', false, {
                        engineHealth    = engineHp,
                        bodyHealth      = bodyHp,
                        driveDistanceKm = distKm,
                    })

                    if result and result.success then
                        DetachFromFlatbed(activeCall.vehicle)
                        Wait(400)
                        if DoesEntityExist(activeCall.vehicle) then
                            SetEntityAsMissionEntity(activeCall.vehicle, true, true)
                            DeleteVehicle(activeCall.vehicle)
                        end
                        if activeCall.blip and DoesBlipExist(activeCall.blip) then
                            RemoveBlip(activeCall.blip)
                        end
                        if activeCall.dropoffBlip and DoesBlipExist(activeCall.dropoffBlip) then
                            RemoveBlip(activeCall.dropoffBlip)
                        end

                        Notify(
                            ('Delivered. Base $%s · Distance bonus $%s · Damage -$%s · Total $%s'):format(
                                result.base, result.distanceBonus, result.penalty, result.payout
                            ),
                            'success', 8000
                        )

                        activeCall   = nil
                        pickedUp     = false
                        pickupCoords = nil
                        HudUpdate(HudSnapshot())
                    elseif result and result.reason then
                        Notify(result.reason, 'error', 5000)
                    end
                end
            else
                lib.hideTextUI()
            end
        else
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- ─── Clock on / off events ──────────────────────────────────────────

RegisterNetEvent('distortionz_towjob:client:clockOn', function()
    if onDuty then return end

    local result = lib.callback.await('distortionz_towjob:server:clockOn', false)
    if not result or not result.success then
        Notify(result and result.reason or 'Failed to clock in.', 'error', 6000)
        return
    end

    onDuty = true
    flatbed = SpawnFlatbed(result.flatbedModel, result.flatbedColor, result.flatbedPlate)

    if flatbed then
        TaskWarpPedIntoVehicle(PlayerPedId(), flatbed, -1)
    end

    HudShow(HudSnapshot())
    Notify('Clocked in. Stand by for dispatch.', 'success', 6000)
end)

RegisterNetEvent('distortionz_towjob:client:clockOff', function()
    if not onDuty then return end

    local result = lib.callback.await('distortionz_towjob:server:clockOff', false)
    if not result or not result.success then
        Notify(result and result.reason or 'Failed to clock out.', 'error', 6000)
        return
    end

    onDuty = false

    DespawnFlatbed()

    if activeCall then
        if activeCall.vehicle and DoesEntityExist(activeCall.vehicle) then
            SetEntityAsMissionEntity(activeCall.vehicle, true, true)
            DeleteVehicle(activeCall.vehicle)
        end
        if activeCall.blip and DoesBlipExist(activeCall.blip) then
            RemoveBlip(activeCall.blip)
        end
        if activeCall.dropoffBlip and DoesBlipExist(activeCall.dropoffBlip) then
            RemoveBlip(activeCall.dropoffBlip)
        end
        activeCall = nil
    end

    pickedUp     = false
    pickupCoords = nil

    CleanupAllPlacedObjects()

    HudHide()
    Notify('Clocked out. Drive safe.', 'info', 5000)
end)

local function HasActiveFlatbed()
    return flatbed ~= nil and DoesEntityExist(flatbed)
end

RegisterNetEvent('distortionz_towjob:client:returnFlatbed', function()
    if not onDuty or not HasActiveFlatbed() then return end

    local fbCoords = GetEntityCoords(flatbed)
    local pCoords  = GetEntityCoords(PlayerPedId())
    if #(pCoords - fbCoords) > 4.0 then
        Notify('Walk up to the flatbed to return it.', 'warning', 5000)
        return
    end

    DespawnFlatbed()
    Notify('Flatbed returned. Speak to dispatch for another.', 'info', 5000)
end)

RegisterNetEvent('distortionz_towjob:client:requestFlatbed', function()
    if not onDuty then return end
    if HasActiveFlatbed() then
        Notify('You already have a flatbed assigned.', 'warning', 5000)
        return
    end

    local plate = ('TOW%d'):format(math.random(100, 999))
    flatbed = SpawnFlatbed(Config.Flatbed.model, Config.Flatbed.color, plate)

    if flatbed then
        TaskWarpPedIntoVehicle(PlayerPedId(), flatbed, -1)
        Notify('Flatbed assigned. Stand by for dispatch.', 'success', 5000)
    else
        Notify('Could not assign a flatbed. Try again.', 'error', 5000)
    end
end)

-- ─── Incoming dispatch call ─────────────────────────────────────────

RegisterNetEvent('distortionz_towjob:client:incomingCall', function(payload)
    if not onDuty then return end
    if activeCall then return end  -- already handling one

    local veh = SpawnCallVehicle({
        spawn = payload.spawn,
        model = payload.model,
        plate = payload.plate,
    })

    if not veh then return end

    local sCoords = payload.spawn.coords
    local blip = AddBlipForCoord(sCoords.x, sCoords.y, sCoords.z)
    SetBlipSprite(blip, Config.Dispatch.blipSprite)
    SetBlipColour(blip, Config.Dispatch.blipColor)
    SetBlipScale(blip, Config.Dispatch.blipScale)
    SetBlipAsShortRange(blip, false)
    SetBlipFlashes(blip, true)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, Config.Dispatch.blipColor)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Tow Call — %s'):format(payload.label or 'Unknown'))
    EndTextCommandSetBlipName(blip)

    SetTimeout(8000, function()
        if blip and DoesBlipExist(blip) then SetBlipFlashes(blip, false) end
    end)

    activeCall = {
        spawn         = payload.spawn,
        model         = payload.model,
        plate         = payload.plate,
        reason        = payload.reason,
        label         = payload.label,
        vehicle       = veh,
        blip          = blip,
        timeoutEpoch  = GetGameTimer() + ((payload.timeout or Config.Dispatch.callTimeoutSeconds) * 1000),
    }

    AttachCallTargets(veh)

    Notify(
        ('10-86 — %s. %s · Plate %s. Reason: %s'):format(
            payload.label or '?', payload.model, payload.plate, payload.reason or 'Unknown'
        ),
        'police', 9000, 'Dispatch'
    )

    -- Dispatch audio (chirp + TTS voiceover)
    if Config.Audio and Config.Audio.enabled then
        SendNUIMessage({
            action = 'dispatchAudio',
            data = {
                chirps      = Config.Audio.chirps,
                chirpOpen   = Config.Audio.chirpOpen,
                chirpClose  = Config.Audio.chirpClose,
                chirpVolume = Config.Audio.chirpVolume,
                voice       = Config.Audio.voice,
                voiceRate   = Config.Audio.voiceRate,
                voicePitch  = Config.Audio.voicePitch,
                voiceVolume = Config.Audio.voiceVolume,
                voicePrefer = Config.Audio.voicePrefer,
                template    = Config.Audio.voiceTemplate,
                location    = payload.label  or 'unknown location',
                model       = payload.model  or 'unknown',
                plate       = payload.plate  or '',
                reason      = payload.reason or 'Unspecified',
            },
        })
    end

    HudUpdate(HudSnapshot())
end)

RegisterNetEvent('distortionz_towjob:client:callCancelled', function(payload)
    if activeCall then
        if activeCall.vehicle and DoesEntityExist(activeCall.vehicle) then
            SetEntityAsMissionEntity(activeCall.vehicle, true, true)
            DeleteVehicle(activeCall.vehicle)
        end
        if activeCall.blip and DoesBlipExist(activeCall.blip) then
            RemoveBlip(activeCall.blip)
        end
        if activeCall.dropoffBlip and DoesBlipExist(activeCall.dropoffBlip) then
            RemoveBlip(activeCall.dropoffBlip)
        end
    end

    activeCall   = nil
    pickedUp     = false
    pickupCoords = nil

    if payload and payload.reason then
        Notify(payload.reason, 'warning', 6000)
    end

    HudUpdate(HudSnapshot())
end)

-- ─── Equipment spawner (/towjob) ────────────────────────────────────

local placedObjects = {}        -- list of placed object handles
local spawnerOpen   = false     -- NUI catalog visible
local placing       = false     -- raycast preview active

local function FindSpawnerItem(id)
    if not id then return nil end
    for _, item in ipairs(Config.Spawner.items or {}) do
        if item.id == id then return item end
    end
    return nil
end

local function SetSpawnerNuiOpen(open)
    spawnerOpen = open
    SetNuiFocus(open, open)
    if open then
        SendNUIMessage({
            action = 'openSpawner',
            data   = { items = Config.Spawner.items },
        })
    else
        SendNUIMessage({ action = 'closeSpawner' })
    end
end

local function AddPickupTarget(obj)
    if not obj or obj == 0 then return end
    exports.ox_target:addLocalEntity(obj, {
        {
            name     = 'distortionz_towjob_pickup_' .. obj,
            label    = 'Pack up',
            icon     = 'fa-solid fa-hand',
            distance = 2.0,
            onSelect = function()
                exports.ox_target:removeLocalEntity(obj, 'distortionz_towjob_pickup_' .. obj)
                if DoesEntityExist(obj) then
                    SetEntityAsMissionEntity(obj, true, true)
                    DeleteEntity(obj)
                end
                for i, h in ipairs(placedObjects) do
                    if h == obj then
                        table.remove(placedObjects, i)
                        break
                    end
                end
                Notify('Equipment packed up.', 'info', 3000)
            end,
        },
    })
end

local function RaycastFromCamera(distance)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosX = math.abs(math.cos(rotX))
    local forward = vec3(
        -math.sin(rotZ) * cosX,
         math.cos(rotZ) * cosX,
         math.sin(rotX)
    )
    local dest = cam + (forward * distance)

    local ped = PlayerPedId()
    local handle = StartShapeTestRay(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, -1, ped, 0)
    local _, hit, endCoords = GetShapeTestResult(handle)
    if hit == 1 then return endCoords end
    return dest
end

local function PlacementLoop(item)
    placing = true

    local hash = joaat(item.model)
    lib.requestModel(hash, 10000)

    local previewCoords = RaycastFromCamera(Config.Spawner.rayDistance)
    local preview = CreateObjectNoOffset(hash, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
    SetEntityCollision(preview, false, false)
    SetEntityAlpha(preview, 160, false)
    SetEntityInvincible(preview, true)
    FreezeEntityPosition(preview, true)

    local heading = GetEntityHeading(PlayerPedId())
    local rotateStep = Config.Spawner.rotateStep or 15.0

    while placing do
        DisableControlAction(0, 24,  true)  -- LMB attack
        DisableControlAction(0, 25,  true)  -- RMB aim
        DisableControlAction(0, 257, true)  -- attack 2
        DisableControlAction(0, 263, true)  -- melee 1
        DisableControlAction(0, 264, true)  -- melee 2
        DisableControlAction(0, 14,  true)  -- scroll prev (free for rotate)
        DisableControlAction(0, 15,  true)  -- scroll next

        local target = RaycastFromCamera(Config.Spawner.rayDistance)
        SetEntityCoordsNoOffset(preview, target.x, target.y, target.z + (item.z or 0.0), true, false, false)
        SetEntityHeading(preview, heading)
        -- Ground-snap the preview so it visually matches the final spawn
        PlaceObjectOnGroundProperly(preview)

        if IsDisabledControlPressed(0, 14) or IsControlPressed(0, 39) then
            heading = (heading - rotateStep) % 360.0
        elseif IsDisabledControlPressed(0, 15) or IsControlPressed(0, 38) then
            heading = (heading + rotateStep) % 360.0
        end

        if IsDisabledControlJustPressed(0, 24) then
            -- Confirm placement
            placing = false

            -- Spawn the real (networked) object
            local real = CreateObject(hash, target.x, target.y, target.z + (item.z or 0.0), true, true, false)
            if DoesEntityExist(real) then
                SetEntityHeading(real, heading)
                -- Always ground-snap before optional freeze, otherwise frozen
                -- props float at the raw raycast Z (sign half-buried / floating).
                PlaceObjectOnGroundProperly(real)
                if item.freeze then FreezeEntityPosition(real, true) end
                placedObjects[#placedObjects + 1] = real
                AddPickupTarget(real)
            end

            -- Cleanup preview, reopen catalog
            if DoesEntityExist(preview) then DeleteEntity(preview) end
            SetModelAsNoLongerNeeded(hash)
            SetSpawnerNuiOpen(true)
            return
        end

        if IsDisabledControlJustPressed(0, 25) then
            -- Abort
            placing = false
            if DoesEntityExist(preview) then DeleteEntity(preview) end
            SetModelAsNoLongerNeeded(hash)
            SetSpawnerNuiOpen(true)
            return
        end

        Wait(0)
    end

    -- Safety cleanup if loop exited any other way
    if DoesEntityExist(preview) then DeleteEntity(preview) end
    SetModelAsNoLongerNeeded(hash)
end

local function StartPlacement(itemId)
    if placing then return end
    if (#placedObjects) >= (Config.Spawner.maxPerPlayer or 12) then
        Notify(('You already have %d items placed. Pack some up first.'):format(#placedObjects), 'warning', 5000)
        SetSpawnerNuiOpen(true)
        return
    end

    local item = FindSpawnerItem(itemId)
    if not item then
        Notify('Unknown equipment item.', 'error', 4000)
        SetSpawnerNuiOpen(true)
        return
    end

    local hash = joaat(item.model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        Notify(('Invalid prop model "%s" — check Config.Spawner.items.'):format(item.model), 'error', 6000)
        SetSpawnerNuiOpen(true)
        return
    end

    SetSpawnerNuiOpen(false)
    Wait(50)
    CreateThread(function() PlacementLoop(item) end)
end

local function CleanupAllPlacedObjects()
    for _, obj in ipairs(placedObjects) do
        if obj and DoesEntityExist(obj) then
            pcall(function()
                exports.ox_target:removeLocalEntity(obj, 'distortionz_towjob_pickup_' .. obj)
            end)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
    placedObjects = {}
end

RegisterNUICallback('selectSpawnItem', function(data, cb)
    cb({ ok = true })
    StartPlacement(data and data.id)
end)

RegisterNUICallback('closeSpawner', function(_, cb)
    cb({ ok = true })
    SetSpawnerNuiOpen(false)
end)

RegisterCommand(Config.Spawner.command or 'towjob', function()
    if not onDuty then
        Notify('Clock on at the dispatcher first.', 'warning', 5000)
        return
    end
    if placing or spawnerOpen then return end
    SetSpawnerNuiOpen(true)
end, false)

TriggerEvent('chat:addSuggestion', '/' .. (Config.Spawner.command or 'towjob'),
    Config.Spawner.chatSuggest or 'Open the tow equipment placer')

-- ─── Boot / cleanup ─────────────────────────────────────────────────

CreateThread(function()
    Wait(1500)
    CreateYardBlip()
    SpawnYardPed()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if yardPed and DoesEntityExist(yardPed) then
        exports.ox_target:removeLocalEntity(yardPed, {
            'distortionz_towjob_clockon',
            'distortionz_towjob_requestflatbed',
            'distortionz_towjob_clockoff',
        })
        DeleteEntity(yardPed)
    end

    if yardBlip and DoesBlipExist(yardBlip) then RemoveBlip(yardBlip) end

    DespawnFlatbed()

    if activeCall and activeCall.vehicle and DoesEntityExist(activeCall.vehicle) then
        DeleteVehicle(activeCall.vehicle)
    end
    if activeCall and activeCall.blip and DoesBlipExist(activeCall.blip) then
        RemoveBlip(activeCall.blip)
    end
    if activeCall and activeCall.dropoffBlip and DoesBlipExist(activeCall.dropoffBlip) then
        RemoveBlip(activeCall.dropoffBlip)
    end

    CleanupAllPlacedObjects()

    if spawnerOpen then SetSpawnerNuiOpen(false) end
    placing = false

    HudHide()
    if lib and lib.hideTextUI then lib.hideTextUI() end
end)

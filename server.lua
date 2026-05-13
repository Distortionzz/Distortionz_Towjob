-- =====================================================================
--  Distortionz Tow Job · server.lua
-- =====================================================================

local QBX = exports.qbx_core

-- [src] = {
--   onDuty       = boolean,
--   call         = { spawnIdx, model, coords, plate, startedAt } | nil,
--   nextCallAt   = epoch when next dispatch call may fire (server time),
--   pickedUp     = bool — has the player attached the target vehicle yet?
-- }
local jobs = {}

-- ─── Helpers ────────────────────────────────────────────────────────

local function Debug(...)
    if Config.Debug then
        print(('^5[distortionz_towjob]^7 %s'):format(table.concat({...}, ' ')))
    end
end

local function Notify(src, message, notifyType, duration, title)
    if not src or not message then return end

    notifyType = notifyType or 'primary'
    duration   = tonumber(duration) or Config.Notify.defaultLength
    title      = title or Config.Notify.title

    if notifyType == 'inform' then notifyType = 'info' end

    if GetResourceState(Config.Notify.resource) == 'started' then
        TriggerClientEvent('distortionz_notify:client:notify', src, {
            title    = title,
            message  = message,
            type     = notifyType,
            duration = duration,
        })
        return
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = title,
        description = message,
        type        = notifyType,
        duration    = duration,
    })
end

local function GenerateTowPlate()
    local n = math.random(100, 999)
    return ('TOW%d'):format(n)
end

-- ─── Job set/clear ──────────────────────────────────────────────────

local function SetPlayerJob(src, jobName, grade)
    local Player = QBX:GetPlayer(src)
    if not Player then return false end

    grade = tonumber(grade) or 0

    if Player.Functions and Player.Functions.SetJob then
        return Player.Functions.SetJob(jobName, grade) ~= false
    end

    return QBX:SetJob(src, jobName, grade) ~= false
end

-- ─── Pay ────────────────────────────────────────────────────────────

local function PayPlayer(src, amount)
    if amount <= 0 then return true end

    local account = Config.Payout.account
    local Player  = QBX:GetPlayer(src)
    if not Player then return false end

    if account == 'dirty' then
        return exports.ox_inventory:AddItem(src, 'markedbills', amount) and true or false
    end

    if Player.Functions and Player.Functions.AddMoney then
        Player.Functions.AddMoney(account, amount, 'distortionz-towjob-payout')
        return true
    end

    return false
end

-- ─── Clock on / off ─────────────────────────────────────────────────

lib.callback.register('distortionz_towjob:server:clockOn', function(source)
    local src = source

    if jobs[src] and jobs[src].onDuty then
        return { success = false, reason = 'You are already clocked in.' }
    end

    if not SetPlayerJob(src, Config.Job.name, Config.Job.grade) then
        return { success = false, reason = 'Failed to set job. Try again.' }
    end

    jobs[src] = {
        onDuty     = true,
        call       = nil,
        nextCallAt = os.time() + Config.Dispatch.callCooldownSeconds,
        pickedUp   = false,
    }

    Debug(('Source %s clocked in'):format(src))

    return {
        success         = true,
        flatbedModel    = Config.Flatbed.model,
        flatbedSpawn    = Config.Yard.flatbedSpawn,
        flatbedPlate    = GenerateTowPlate(),
        flatbedColor    = Config.Flatbed.color,
        nextCallSeconds = Config.Dispatch.callCooldownSeconds,
    }
end)

lib.callback.register('distortionz_towjob:server:clockOff', function(source)
    local src = source
    local job = jobs[src]
    if not job or not job.onDuty then
        return { success = false, reason = 'You are not on duty.' }
    end

    SetPlayerJob(src, Config.Job.revertTo, 0)
    jobs[src] = nil

    Debug(('Source %s clocked off'):format(src))

    return { success = true }
end)

-- ─── Dispatch tick ──────────────────────────────────────────────────

local function PickCall()
    local spawnIdx = math.random(1, #Config.SpawnPool)
    local spawn    = Config.SpawnPool[spawnIdx]
    local model    = Config.TargetModels[math.random(1, #Config.TargetModels)]
    local letters  = ('%c%c'):format(math.random(65, 90), math.random(65, 90))
    local plate    = ('%s%05d'):format(letters, math.random(0, 99999))
    local reason   = Config.TowReasons[math.random(1, #Config.TowReasons)]

    return {
        spawnIdx  = spawnIdx,
        spawn     = spawn,
        model     = model,
        plate     = plate,
        reason    = reason,
        startedAt = os.time(),
    }
end

CreateThread(function()
    while true do
        Wait(2000)

        for src, job in pairs(jobs) do
            if job.onDuty and not job.call and os.time() >= job.nextCallAt then
                local call = PickCall()
                job.call     = call
                job.pickedUp = false

                TriggerClientEvent('distortionz_towjob:client:incomingCall', src, {
                    spawn    = call.spawn,
                    model    = call.model,
                    plate    = call.plate,
                    reason   = call.reason,
                    label    = call.spawn.label,
                    timeout  = Config.Dispatch.callTimeoutSeconds,
                })

                Debug(('Dispatch → src=%s spot=%s model=%s plate=%s reason=%s'):format(
                    src, call.spawn.label, call.model, call.plate, call.reason
                ))
            end

            -- Auto-expire stuck calls
            if job.call and (os.time() - job.call.startedAt) > Config.Dispatch.callTimeoutSeconds then
                Debug(('Call expired for src=%s'):format(src))
                job.call       = nil
                job.pickedUp   = false
                job.nextCallAt = os.time() + Config.Dispatch.callCooldownSeconds

                TriggerClientEvent('distortionz_towjob:client:callCancelled', src, {
                    reason          = 'Call expired. Dispatch is sending another shortly.',
                    nextCallSeconds = Config.Dispatch.callCooldownSeconds,
                })
            end
        end
    end
end)

-- ─── Flatbed key grant (client sends netId after CreateVehicle) ─────

RegisterNetEvent('distortionz_towjob:server:grantFlatbedKeys', function(netId)
    local src = source
    if not netId or netId == 0 then return end
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end

    -- Wait up to ~2s for the entity to replicate to the server. Without
    -- this, qbx_vehiclekeys.GiveKeys can fire on a 0-handle or an entity
    -- whose plate hasn't propagated yet, and the keys silently no-op.
    local entity = 0
    local plate
    for _ = 1, 20 do
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 then
            plate = GetVehicleNumberPlateText(entity)
            if plate and plate ~= '' then break end
        end
        Wait(100)
    end

    if entity == 0 then
        Debug(('grantFlatbedKeys: entity never replicated (netId=%s)'):format(netId))
        return
    end

    local ok, err = pcall(function()
        exports.qbx_vehiclekeys:GiveKeys(src, entity, true)
    end)
    if not ok then
        Debug(('GiveKeys failed: %s'):format(tostring(err)))
    else
        Debug(('Keys granted to src=%s plate=%s netId=%s'):format(src, plate or '?', netId))
    end
end)

-- ─── Pickup confirmation (client tells server "I attached the car") ─

RegisterNetEvent('distortionz_towjob:server:confirmPickup', function()
    local src = source
    local job = jobs[src]
    if not job or not job.onDuty or not job.call then return end

    job.pickedUp = true
    Notify(src, 'Vehicle hooked. Drop it at the tow yard.', 'success', 6000)
end)

-- ─── Cancel current call (player rejected / wants to skip) ──────────

RegisterNetEvent('distortionz_towjob:server:cancelCall', function(opts)
    local src = source
    local job = jobs[src]
    if not job or not job.onDuty then return end

    local noAccess = type(opts) == 'table' and opts.noAccess == true
    local cooldown = noAccess
        and (Config.Dispatch.noAccessCooldownSeconds or Config.Dispatch.callCooldownSeconds)
        or Config.Dispatch.callCooldownSeconds

    job.call       = nil
    job.pickedUp   = false
    job.nextCallAt = os.time() + cooldown

    TriggerClientEvent('distortionz_towjob:client:callCancelled', src, {
        reason          = noAccess
            and '10-99 — vehicle inaccessible. Returning to standby.'
            or  'Call dismissed. Dispatch will try again shortly.',
        nextCallSeconds = cooldown,
        noAccess        = noAccess,
    })
end)

-- ─── Deliver (drop at yard) ─────────────────────────────────────────

lib.callback.register('distortionz_towjob:server:deliver', function(source, payload)
    local src = source
    local job = jobs[src]

    if not job or not job.onDuty then
        return { success = false, reason = 'You are not on duty.' }
    end
    if not job.call then
        return { success = false, reason = 'You do not have an active call.' }
    end
    if not job.pickedUp then
        return { success = false, reason = 'You haven\'t hooked the vehicle yet.' }
    end
    if type(payload) ~= 'table' then
        return { success = false, reason = 'Invalid delivery payload.' }
    end

    local engineHealth = tonumber(payload.engineHealth) or 1000.0
    local bodyHealth   = tonumber(payload.bodyHealth)   or 1000.0
    local driveDistKm  = math.max(0, tonumber(payload.driveDistanceKm) or 0)

    if engineHealth < 0    then engineHealth = 0    end
    if engineHealth > 1000 then engineHealth = 1000 end
    if bodyHealth   < 0    then bodyHealth   = 0    end
    if bodyHealth   > 1000 then bodyHealth   = 1000 end

    -- Compute payout
    local base    = Config.Payout.base
    local distBonus = math.floor(driveDistKm * Config.Payout.perKilometer)
    local damageHp = (1000.0 - engineHealth) + (1000.0 - bodyHealth)
    local penalty  = math.floor(damageHp * Config.Payout.damagePenaltyPerHp)

    local pay = math.max(Config.Payout.minFloor, base + distBonus - penalty)

    if not PayPlayer(src, pay) then
        return { success = false, reason = 'Payout failed. Try again.' }
    end

    Debug(('Deliver: src=%s base=%s dist=%s penalty=-%s pay=%s'):format(
        src, base, distBonus, penalty, pay
    ))

    job.call       = nil
    job.pickedUp   = false
    job.nextCallAt = os.time() + Config.Dispatch.callCooldownSeconds

    return {
        success         = true,
        payout          = pay,
        base            = base,
        distanceBonus   = distBonus,
        penalty         = penalty,
        nextCallSeconds = Config.Dispatch.callCooldownSeconds,
    }
end)

-- ─── Status query (HUD pulls cooldown, on-duty flag, call info) ─────

lib.callback.register('distortionz_towjob:server:getStatus', function(source)
    local src = source
    local job = jobs[src]
    if not job or not job.onDuty then
        return { onDuty = false }
    end

    local secsLeft = math.max(0, (job.nextCallAt or 0) - os.time())

    return {
        onDuty            = true,
        hasCall           = job.call ~= nil,
        pickedUp          = job.pickedUp,
        nextCallSeconds   = secsLeft,
        callTimeoutLeft   = job.call and math.max(0,
            Config.Dispatch.callTimeoutSeconds - (os.time() - job.call.startedAt)) or 0,
        meta = {
            version = Config.CurrentVersion,
            repo    = Config.Repo,
        },
    }
end)

-- ─── Cleanup on disconnect ──────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    jobs[src] = nil
end)

-- ─── Resource start banner ──────────────────────────────────────────

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print(('^5[%s]^7 Started successfully. Version: ^2%s^7'):format(
        resourceName, Config.Script.version or '1.0.0'
    ))
end)

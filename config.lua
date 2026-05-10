Config = {}

Config.Debug = false

-- ─── Script meta ────────────────────────────────────────────────────
Config.Script = {
    name    = 'Distortionz Tow Job',
    version = '1.2.1',
}
Config.CurrentVersion = Config.Script.version

Config.Repo = 'https://github.com/Distortionzz/Distortionz_Towjob'

Config.VersionCheck = {
    enabled      = true,
    checkOnStart = true,
    url          = 'https://raw.githubusercontent.com/Distortionzz/Distortionz_Towjob/main/version.json',
}

-- ─── Notify wrapper ─────────────────────────────────────────────────
Config.Notify = {
    resource      = 'distortionz_notify',
    title         = 'Tow Dispatch',
    defaultLength = 5000,
}

-- ─── Dispatch audio ─────────────────────────────────────────────────
-- Two layers: a radio chirp (short audio file, optional) and a voice-over
-- generated at runtime via the browser SpeechSynthesis API (no asset).
Config.Audio = {
    enabled = true,

    -- Radio chirps. Drop two .ogg or .mp3 files in html/sounds/
    -- (free SFX libraries: zapsplat, freesound, pixabay).
    -- Set chirps = false to skip if you don't have files.
    chirps      = true,
    chirpVolume = 0.55,
    chirpOpen   = 'sounds/dispatch_open.mp3',   -- relative to html/
    chirpClose  = 'sounds/dispatch_close.mp3',

    -- Browser TTS voice (no asset required — works out of the box).
    voice       = true,
    voiceRate   = 0.85,   -- 0.1 to 10. <1 = slower, more deliberate
    voicePitch  = 0.65,   -- 0 to 2. <1 = deeper, more authoritative
    voiceVolume = 0.90,   -- 0 to 1
    -- Preferred voice name fragments (first match wins on the player's machine).
    -- Defaults aim at a male English-US voice when available.
    voicePrefer = { 'Mark', 'David', 'Aaron', 'Daniel', 'Google US English', 'en-US' },

    -- Phrase template. {location} {model} {plate} {reason} are substituted.
    voiceTemplate = 'Attention available tow unit. Ten eighty six at {location}. Vehicle is a {model}, plate {plate}. {reason}. Respond.',
}

-- ─── Tow yard ───────────────────────────────────────────────────────
-- Beeker's Garage @ La Mesa — canonical FiveM tow yard
Config.Yard = {
    -- Clock-on ped (sits inside the yard office)
    ped = {
        enabled  = true,
        model    = 's_m_y_dockwork_01',
        coords   = vec4(409.0, -1623.0, 29.29, 226.0),
        scenario = 'WORLD_HUMAN_CLIPBOARD',
    },

    -- ox_target option on the ped
    target = {
        icon     = 'fa-solid fa-truck-pickup',
        label    = 'Speak to dispatcher',
        distance = 2.5,
    },

    -- Blip on the map
    blip = {
        enabled    = true,
        sprite     = 68,         -- tow truck icon
        color      = 5,          -- yellow
        scale      = 0.85,
        label      = 'Tow Yard - Beeker\'s Garage Job Center',
        shortRange = true,
    },

    -- Flatbed handout spot
    flatbedSpawn = vec4(412.13, -1636.03, 28.29, 137.0),

    -- Where towed cars must be dropped off (rectangle around the yard)
    dropoff = {
        coords = vec3(396.46, -1644.13, 28.74),
        radius = 18.0,
    },
}

-- ─── Job vehicle ────────────────────────────────────────────────────
Config.Flatbed = {
    model = 'f550rollback',
    plate = 'TOW',
    -- Color (primary, secondary)
    color = { 88, 88 },
}

-- ─── Equipment spawner (/towjob command) ───────────────────────────
-- Place cones, barriers, flares around a tow scene. Gated to on-duty
-- only. Items are networked so other players see them; tracked for
-- cleanup on clock-off / resource stop.
Config.Spawner = {
    command       = 'towjob',
    chatSuggest   = 'Open the tow equipment placer',

    -- Max distance (metres) the placement preview can be from the player
    rayDistance   = 7.5,

    -- Rotation step (degrees) for Q / E
    rotateStep    = 15.0,

    -- Maximum number of objects a single player can place at once
    maxPerPlayer  = 12,

    -- The catalog. Each entry:
    --   id       — unique key sent over NUI
    --   label    — what the UI shows
    --   icon     — emoji or fontawesome (matched in app.js)
    --   model    — GTA prop hash name
    --   z        — extra height offset above the raycast hit (metres)
    --   freeze   — true = static (cars pass through); false = physics on
    items = {
        { id = 'cone_small',   label = 'Small Cone',          icon = '🚧', model = 'prop_roadcone02a',     z = 0.0, freeze = true },
        { id = 'cone_large',   label = 'Large Cone',          icon = '🛑', model = 'prop_roadcone01a',     z = 0.0, freeze = true },
        { id = 'cone_mp',      label = 'Highway Cone',        icon = '🚧', model = 'prop_mp_cone_02',      z = 0.0, freeze = true },
        { id = 'tri_warning',  label = 'Reflective Triangle', icon = '🔺', model = 'prop_warningtri_01',   z = 0.0, freeze = true  },
        { id = 'flare',        label = 'Road Flare',          icon = '🔥', model = 'prop_flare_01a',       z = 0.0, freeze = true  },
        { id = 'barrier_work', label = 'Work Barrier',        icon = '🚏', model = 'prop_barrier_work01a', z = 0.0, freeze = true  },
        { id = 'barrier_long', label = 'Long Barrier',        icon = '🚏', model = 'prop_barrier_work04a', z = 0.0, freeze = true  },
        { id = 'sign_men',     label = 'Construction Sign',   icon = '⚠️', model = 'prop_consign_01a',     z = 0.0, freeze = true  },
    },
}

-- ─── Attach behavior ────────────────────────────────────────────────
Config.Attach = {
    -- Max distance (centre-to-centre) the flatbed can be from the target
    -- vehicle when hooking. The flatbed alone is ~7m long, so 6m is too
    -- tight — bumpers can be touching with centres still ~7m apart.
    maxDistance = 10.0,

    -- Default attach offset relative to the flatbed centre (metres).
    -- y < 0 = towards the rear bed.
    -- Used when the towed vehicle is NOT in modelOverrides below.
    offset = { x = 0.0, y = -2.6, z = 1.0 },

    -- Per-model offsets — fixes vehicles that float / clip on the bed.
    -- Tall SUVs/trucks usually need higher z; small/sports cars lower.
    -- Tune in-game and add entries here. Lookup uses joaat(name) == model.
    --
    -- Workflow: spawn a call, hook the car, eyeball the alignment, then
    -- adjust z by ±0.05 increments until it sits flush. Save → restart.
    modelOverrides = {
        -- Tall SUVs / pickups (sit higher)
        ['cavalcade'] = { x = 0.0, y = -2.6, z = 1.20 },
        ['granger']   = { x = 0.0, y = -2.6, z = 1.25 },
        ['baller']    = { x = 0.0, y = -2.6, z = 1.15 },
        ['bobcatxl']  = { x = 0.0, y = -2.6, z = 1.20 },

        -- Small / low-slung cars (sit lower)
        ['blista']     = { x = 0.0, y = -2.6, z = 0.85 },
        ['panto']      = { x = 0.0, y = -2.6, z = 0.75 },
        ['dilettante'] = { x = 0.0, y = -2.6, z = 0.85 },

        -- Sports / coupes
        ['felon']    = { x = 0.0, y = -2.6, z = 0.90 },
        ['sentinel'] = { x = 0.0, y = -2.6, z = 0.90 },
        ['fugitive'] = { x = 0.0, y = -2.6, z = 0.95 },

        -- Wagons (slightly under default)
        ['ingot']    = { x = 0.0, y = -2.6, z = 0.95 },
        ['stratum']  = { x = 0.0, y = -2.6, z = 0.95 },
    },
}

-- ─── Dispatch / call timing ─────────────────────────────────────────
Config.Dispatch = {
    -- Seconds between dispatch calls (police-call cadence)
    callCooldownSeconds = 20,

    -- Map blip on the abandoned vehicle
    blipSprite = 67,
    blipColor  = 5,
    blipScale  = 0.9,

    -- How long the call stays open before auto-cancel (seconds)
    callTimeoutSeconds = 600,

    -- Distance under which an "approach" notification is fired
    approachNotifyDistance = 80.0,
}

-- ─── Abandoned vehicle spawn pool ───────────────────────────────────
-- Each entry: { coords = vec4(x, y, z, heading), label = 'Location name' }
Config.SpawnPool = {
    { coords = vec4(-1187.32, -1518.60, 4.35,  35.0),  label = 'Vespucci Beach' },
    { coords = vec4(1216.88, -1413.52, 35.22, 270.0),  label = 'El Burro Heights alley' },
    { coords = vec4(196.13, -1671.81, 29.34,   140.0), label = 'Davis residential' },
    { coords = vec4(-274.20, -2025.30, 30.12,  150.0), label = 'Cypress Flats lot' },
    { coords = vec4(-1178.74, -1510.83, 2.83,  123.3), label = 'Del Perro Pier' },
    { coords = vec4(-44.89,  -1460.59, 30.25,  94.1),  label = 'Strawberry alley' },
    { coords = vec4(-1087.96, -885.79, 2.21,   215.0), label = 'Morningwood' },
    { coords = vec4(118.43,  -1057.10, 29.20,  160.0), label = 'Strawberry warehouse' },
    { coords = vec4(728.35,  -1296.12, 26.30,  180.0), label = 'La Mesa industrial' },
    { coords = vec4(-577.88, -931.20, 23.80,   90.0),  label = 'Pillbox Hill curb' },
    { coords = vec4(-356.73, -134.32, 38.60,   30.0),  label = 'Rockford Hills' },
    { coords = vec4(305.74,  -994.37, 29.16,   175.0), label = 'Mission Row precinct' },
    { coords = vec4(133.39,  -1057.16, 28.19,  68.0),  label = 'Elgin Ave parking lot' },
    { coords = vec4(-555.42,  -931.41, 22.85,  310.9), label = 'Pillbox Hill curb' },
}

-- ─── Reasons for tow ────────────────────────────────────────────────
-- Picked at random per dispatch call. Mix of parking, mechanical,
-- accident, owner-related, and miscellaneous calls to keep dispatch
-- from feeling repetitive.
Config.TowReasons = {
    -- Parking violations
    'Illegally parked in a fire lane',
    'Blocking a private driveway',
    'Stopped in a no-stopping zone',
    'Expired registration tag',
    'Abandoned over 72 hours',
    'Handicap spot, no permit displayed',
    'Double-parked, obstructing traffic',
    'Parked across two metered spaces',
    'Blocking a fire hydrant',
    'On the sidewalk in a pedestrian zone',
    'Blocking sidewalk access for pedestrians',
    'Loading zone violation, business complaint',
    'Permit-only block, no permit shown',
    'Parked in a non-parking spot, blocking gate entrance/exit',

    -- Mechanical breakdowns
    'Engine seized — will not start',
    'Flat tire, no spare in trunk',
    'Out of fuel on the highway shoulder',
    'Smoke pouring from under the hood',
    'Transmission failure mid-traffic',
    'Broken axle after hitting a pothole',
    'Dead battery, jump start failed',
    'Overheated and stalled',
    'Stuck in gear, will not shift',
    'Brake line burst, vehicle inoperable',

    -- Accidents / stuck
    'Minor fender bender, driver fled the scene',
    'Single-vehicle collision, occupants gone',
    'Crashed into a planter, abandoned',
    'Stuck on the highway median',
    'Wedged on a high curb',
    'Hit a utility pole and abandoned',
    'Run off the road, in a ditch',
    'Beached on rocks near the coast',
    'Wedged in an alley, no clearance to reverse',

    -- Owner-related
    'Owner reported it stolen — recovered for return',
    'Repossession order from the bank',
    'Police impound — driver in custody',
    'Insurance lapsed, no proof on file',
    'Driver locked keys inside, gave up waiting',
    'Eviction sweep — owner relocating',
    'DUI arrest at the scene',
    'Owner stranded, called for a tow home',
    'Auction lot pickup, paperwork ready',

    -- Misc / unusual
    'Multiple unpaid parking tickets, boot pulled',
    'Driver flagged a taxi and walked off',
    'Dumped behind a closed business overnight',
    'Tagged for graffiti, needs evidence yard',
    'Stuck in storm-flood water, owner on foot',
    'Parked in a film-permit zone, production complaint',
}

-- ─── Vehicle models that can be the tow target ──────────────────────
-- Lore-friendly civilian cars the dispatcher might call about.
Config.TargetModels = {
    'asea', 'asterope', 'baller', 'blista', 'bobcatxl', 'buccaneer',
    'cavalcade', 'chino', 'dilettante', 'emperor', 'felon', 'fugitive',
    'granger', 'ingot', 'intruder', 'minivan', 'oracle', 'panto',
    'peyote', 'premier', 'primo', 'radi', 'rhapsody', 'sentinel',
    'stanier', 'stratum', 'sultan', 'tailgater', 'warrener', 'washington',
}

-- ─── Payout ─────────────────────────────────────────────────────────
Config.Payout = {
    -- Pay account: 'cash' | 'bank' | 'dirty'
    account = 'cash',

    -- Base payout per delivered vehicle
    base = 350,

    -- Distance bonus: $X per kilometer driven from pickup → dropoff
    perKilometer = 25,

    -- Damage penalty: $X per HP lost off the towed vehicle (engine + body)
    damagePenaltyPerHp = 0.10,

    -- Minimum guaranteed payout floor (after penalties)
    minFloor = 100,
}

-- ─── Job & permissions ──────────────────────────────────────────────
Config.Job = {
    -- qbx job name applied on clock-on (and reset on clock-off)
    name = 'tow',
    -- Grade level set on clock-on
    grade = 0,
    -- Job name to revert to on clock-off
    revertTo = 'unemployed',
}

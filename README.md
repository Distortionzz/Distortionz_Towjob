# Distortionz Tow Job

> Premium tow operator job for Qbox / FiveM. Police-call style dispatch, NUI HUD, voice-over radio chatter, equipment placer, dynamic damage-aware payouts.

![version](https://img.shields.io/badge/version-1.2.0-d4aa62)
![framework](https://img.shields.io/badge/framework-Qbox-181b20)
![license](https://img.shields.io/badge/license-MIT-3fb950)

---

## Overview

A complete, hand-built tow job script. Players clock on at a real-world yard ped, get handed a flatbed with keys, and wait for dispatch calls. Each call drops them on a randomized abandoned vehicle with a randomized violation reason — they hook it via `ox_target`, drive it back to the yard, and get paid based on speed and damage.

## Features

### Gameplay loop
- **Clock on / off ped** at Beeker's Garage (La Mesa) — context-aware `ox_target` options
- **Flatbed handout** — `f550rollback` by default, swappable in config; spawns 100% clean every time, hands the player keys via `qbx_vehiclekeys`
- **Dispatch calls** every 60s while on duty — police-radio style, with audio cues
- **46 randomized tow reasons** across 5 categories (parking violations, mechanical, accidents, owner-related, misc) so dispatches never feel repetitive
- **12 spawn locations** (configurable) for the abandoned vehicle
- **Hook via `ox_target`** on the target vehicle → vehicle attaches to the flatbed via native attach
- **Drop-off zone** at the yard with `[E] Drop off vehicle` text-UI
- **Damage-aware payout** — base + per-km distance bonus − damage penalty (engine + body HP loss)

### Polish
- **Premium NUI HUD** — Standing By / Active Call states, live phase tracker, dispatch reason, plate, vehicle, location
- **Hazard lights on towed vehicle** — auto-on the moment you confirm the hookup, taillights forced for night visibility
- **GPS route swapping** — call-spot blip becomes a fresh route to the yard once the vehicle is on the bed
- **Dispatch audio** — radio chirp + dynamic SpeechSynthesis voice-over (no asset required for voice; chirp `.mp3`/`.ogg`/`.wav` optional)

### `/towjob` equipment spawner
- Open the catalog with `/towjob` while on duty
- 8 placeable props: 3 cone variants, reflective triangle, road flare, work + long barriers, construction sign
- Raycast preview follows the camera; **Q / E** to rotate, **LMB** to confirm, **RMB** to abort
- Placed items are networked — other players see them
- **Pack up** option via `ox_target` on each placed item
- 12-item per-player cap, auto-cleanup on clock-off and resource stop

### Engineering
- Standard distortionz patterns: `distortionz_notify` wrapper with `ox_lib` fallback, `version_check.lua`, version-bumped fxmanifest + `Config.CurrentVersion` + `version.json`
- `qbx_core` integration for `SetJob` / pay accounts
- All client objects/blips/text-UI cleaned up on resource stop and player disconnect

## Dependencies

| Resource | Required | Purpose |
|---|---|---|
| `qbx_core` | yes | Player data, money, SetJob |
| `ox_lib` | yes | callbacks, notify fallback, requestModel |
| `ox_target` | yes | Ped clock-on options + vehicle hook + placed-item pickup |
| `qbx_vehiclekeys` | recommended | Flatbed key grant (else engine cuts on entry) |
| `distortionz_notify` | optional | Branded notifications (else falls back to `ox_lib` notify) |
| `f550rollback` | **bundled** | Default flatbed model — ships in this zip. Swap in `Config.Flatbed.model` if you prefer your own. |

## Installation

The zip ships with **two folders**: the script itself and the bundled flatbed addon. Drop both into your server.

```bash
# 1. Drop the folders into your resources directory
<server>/resources/[distortionz]/distortionz_towjob/
<server>/resources/[distortionz]/f550rollback/        # bundled flatbed addon

# 2. Add to server.cfg (after qbx_core, ox_lib, ox_target are ensured)
ensure f550rollback         # vehicle addon — must load BEFORE the script
ensure distortionz_towjob
```

If you want a different flatbed, change `Config.Flatbed.model` in `config.lua` to the spawn name of your preferred vehicle (e.g. stock `flatbed`, or any other addon you've installed). You can then leave out the `ensure f550rollback` line.

## Configuration

Everything's in [`config.lua`](config.lua). Highlights:

```lua
Config.Yard = {
    ped       = { coords = vec4(409.0, -1623.0, 29.29, 226.0) },
    flatbedSpawn = vec4(412.13, -1636.03, 28.29, 137.0),
    dropoff   = { coords = vec3(396.46, -1644.13, 28.74), radius = 18.0 },
}

Config.Flatbed = { model = 'f550rollback', plate = 'TOW', color = { 88, 88 } }

Config.Dispatch = {
    callCooldownSeconds = 60,
    callTimeoutSeconds  = 600,
}

Config.Payout = {
    account            = 'cash',     -- 'cash' | 'bank' | 'dirty'
    base               = 350,
    perKilometer       = 25,
    damagePenaltyPerHp = 0.10,
    minFloor           = 100,
}

Config.Spawner = {
    command       = 'towjob',        -- /towjob opens the catalog
    rayDistance   = 7.5,
    rotateStep    = 15.0,
    maxPerPlayer  = 12,
    items         = { ... },         -- 8 props ship by default
}

Config.Audio = {
    enabled       = true,
    chirps        = true,            -- needs files in html/sounds/
    voice         = true,            -- TTS via CEF SpeechSynthesis (no asset)
    voiceTemplate = 'Attention available tow unit. Ten eighty six at {location}. ...',
}
```

## Audio assets

The script ships with optional radio-chirp slots. Drop short `.mp3` / `.ogg` / `.wav` files in `html/sounds/`:

```
html/sounds/
├── dispatch_open.mp3    (radio click before voice)
└── dispatch_close.mp3   (radio click after voice)
```

The voice itself uses CEF's built-in `SpeechSynthesis` — **no asset required**. Tune voice rate / pitch / volume / preferred voice in `Config.Audio`. Set `Config.Audio.voice = false` to disable voice entirely; set `chirps = false` to skip the click sounds.

Free SFX libraries: [zapsplat.com](https://www.zapsplat.com), [freesound.org](https://freesound.org), [pixabay.com/sound-effects](https://pixabay.com/sound-effects/) — search "police radio chirp" or "walkie talkie click."

## Adding spawn locations

Edit `Config.SpawnPool` in `config.lua`. Each entry needs coords + a plain place-name label:

```lua
{ coords = vec4(133.39, -1057.16, 28.19, 68.0), label = 'Elgin Ave parking lot' },
```

**Tip:** keep labels as place names. The reason field is rolled separately from the 46-reason pool, so descriptive labels like `'Strawberry — fire hydrant blocked'` will conflict when the rolled reason is something else (e.g. `'DUI arrest at the scene'`).

## Adding tow reasons

Edit `Config.TowReasons` in `config.lua`. The reason rolls per-call independent of location.

## Version checking

Set `Config.VersionCheck.enabled = true` (default) and `distortionz_towjob` will fetch the repo's `version.json` on boot and print a console banner if a newer version exists.

## Credits

- **Script:** Distortionz
- **Framework:** [Qbox Project](https://github.com/Qbox-project)
- **Patterns:** ox_lib, ox_target, qbx_core, qbx_vehiclekeys
- **Bundled flatbed model (`f550rollback`):** **Scorpionfam** — `[NON-ELS][ELS][Addon][FiveM-Ready] F550 Rollback` v1.1.0 — [original page on lcpdfr.com](https://www.lcpdfr.com/downloads/gta5mods/vehiclemodels/50437-non-elselsaddonfivem-ready-f550-rollback/). All credit for the model goes to Scorpionfam; please honor the original author's terms.

## License

The script itself is released under MIT — see [LICENSE](LICENSE). The bundled `f550rollback` vehicle addon retains its original author's license; this script's MIT license does **not** extend to that asset.

# EWRS v12.0 Imperfect Radar Fork - onyames - oh no yet another modded ewrs script

This fork adds two realism layers on top of the EWRS geometry fork:

1. **Radar geometry filtering**
   - radar horizon
   - minimum elevation angle
   - maximum elevation angle
   - maximum range
   - per-radar-type profiles

2. **Imperfect radar scan / track model**
   - radar scan period
   - three-sweep confirmation logic
   - random ON/OFF emission windows
   - stale tracks
   - track memory / drop logic

## Current 55G6 model

The included `55G6 EWR` profile uses:

```lua
scanPeriodSec = 10
hitsToConfirm = 3
requiredConsecutiveHits = true
staleAfterSec = 35
trackMemorySec = 100
useEmissionCycle = true
initialDelaySec = 30
onMinSec = 25
onMaxSec = 40
offMinSec = 30
offMaxSec = 90
forceDcsOnOff = true
```

Meaning:

```text
First ON roughly 30 seconds after start
Radar scans every 10 seconds while ON
Target needs 3 consecutive valid detections before EWRS reports it
Old contacts remain as stale tracks
Tracks drop after memory timeout
```

## Delayed start

By default, the imperfect radar model starts automatically:

```lua
auto_start = true
```

To start it from a trigger instead:

```lua
auto_start = false
```

Then use a DCS trigger:

```lua
EWRS_IMPERFECT_RADAR.start()
```

Other trigger controls:

```lua
EWRS_IMPERFECT_RADAR.stop()
EWRS_IMPERFECT_RADAR.reset()
```

## DCS radar ON/OFF control

The profile currently has:

```lua
forceDcsOnOff = true
```

This means the script physically toggles the profiled DCS radar controller ON/OFF.

If this causes unwanted side effects, such as AI/RWR behavior you do not like, set:

```lua
forceDcsOnOff = false
```

Then the imperfection exists only inside EWRS reporting, while the DCS radar keeps emitting normally.

## Compatibility

Unprofiled radars still use original EWRS behavior because:

```lua
unprofiled_live_passthrough = true
```

So only radars with a scan profile, currently the 55G6, use the new confirmation/stale-track model.

## Testing recommendation

For first mission tests, enable:

```lua
Config.EWRS.radar_geometry.log_rejections = true
Config.EWRS.radar_scan_model.log_state_changes = true
Config.EWRS.radar_scan_model.log_tracks = true
```

Then check `dcs.log` to tune altitude limits, scan windows, and track memory.

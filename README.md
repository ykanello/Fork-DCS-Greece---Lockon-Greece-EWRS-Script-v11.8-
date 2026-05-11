````markdown
# EWRS v11.9 Geometry Fork

This fork adds **radar-type-aware visibility limits** to EWRS.

The goal is to make GCI/EWRS less omniscient by modeling basic radar behavior:

- radar horizon
- minimum elevation angle
- maximum elevation angle
- maximum radar range
- per-radar-type profiles

This allows large EWR radars, such as the **55G6 Tall Rack**, to behave differently from local search radars such as **Flat Face / Spoon Rest / Bar Lock**.

## Main change

EWRS no longer relies only on a single global altitude floor.

Instead, when a radar detects a target, EWRS checks the detecting radar type and applies a matching geometry profile.

Example profile:

```lua
["55G6 EWR"] = {
    name = "55G6 Tall Rack / Nebo EWR",
    maxRangeNm = 150,
    minElevationDeg = 2,
    maxElevationDeg = 16,
    antennaHeightM = 10,
    useRadarHorizon = true,
}
````

## Behaviour

For every radar contact, EWRS now checks:

```text
target range <= radar max range
target above radar horizon
target above minimum elevation beam
target below maximum elevation beam
```

If the target fails the check, EWRS ignores that detection.

This allows aircraft flying low and far away to remain hidden from strategic EWR, while still allowing closer local search radars to detect them.

## Compatibility

By default, unknown radar types are still allowed:

```lua
default_policy = "ALLOW"
```

This means existing missions should continue to work unless a radar type is explicitly configured.

## Debugging

To log rejected detections in `dcs.log`, enable:

```lua
log_rejections = true
```

This helps tune radar profiles during testing.

## Initial supported radar

Currently configured:

```text
55G6 EWR
```

More DCS radar types can be added later by extending the radar geometry table.

## Intended use

This fork is designed for missions where players rely on GCI/EWRS, but the air picture should be imperfect, delayed, and limited by radar placement and altitude.

It pairs well with separate scripts that cycle radar emissions ON/OFF to simulate rotating scan windows, outages, operator delay, or radar discipline.

```
```

# StepOff

Ride most of the way, walk the rest. A native iOS app for NYC that plans a
subway trip and tells you **which stop to get off at** to hit a walking goal —
"I want to walk 20 minutes" or "I want 4,000 steps."

> From 315 W 33rd St to 100 5th Ave, 20 minutes → *"Take the C/E, get off at
> 23 St (instead of 14 St), ~18 min walk."*

## How it works

- **Transit brain — bundled MTA subway GTFS.** Apple's MapKit can't do transit
  routing, so the line/stop knowledge comes from the official MTA feed, distilled
  into `StepOff/Resources/mta_subway.json` (stations + per-line stop sequences,
  express vs. local preserved). Free, offline, no API keys.
- **Walking — MapKit.** Real walking times/distances and the map come from
  `MKDirections` (`.walking`).
- **The idea:** find the line you'd actually board (nearest your origin heading
  toward the destination), then walk *backward* along it from the natural nearest
  stop until the remaining walk matches your target.

## Project layout

```
Scripts/build_mta_data.py   # download + distill the MTA GTFS feed
StepOff/Models/             # WalkTarget, SubwayGraph, Journey
StepOff/Services/           # Geocode, Walk (MapKit), TransitPlanner, GetOffEarlyPlanner, PlannerModel
StepOff/Views/              # PlanView, RoutePreviewMap, SubwayLineBadge
StepOffTests/               # pure-logic unit tests (no simulator/network)
```

## Build & run

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
python3 Scripts/build_mta_data.py      # refresh bundled subway data (optional)
xcodegen generate
xcodebuild -project StepOff.xcodeproj -scheme StepOff \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Open `StepOff.xcodeproj` in Xcode and run, or `xcodebuild ... test` for the unit
tests.

## Scope

**v1** handles single-line trips (no transfer), which covers most short Manhattan
commutes. Later: one-transfer trips, GTFS-realtime arrivals, HealthKit stride
personalization.

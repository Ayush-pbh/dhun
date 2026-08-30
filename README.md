<div align="center">

<img src="docs/icon.png" width="128" alt="Dhun icon">

# Dhun · धुन

**Whatever Spotify is playing, living on your desktop as art.**

*Dhun* (Hindi: धुन, "melody") is a tiny native macOS app — 100% Swift, AppKit + SwiftUI.
No Electron. No JavaScript. No web views.

[![Release](https://img.shields.io/github/v/release/Ayush-pbh/dhun?color=E8912D&label=release)](https://github.com/Ayush-pbh/dhun/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Ayush-pbh/dhun/total?color=E8912D)](https://github.com/Ayush-pbh/dhun/releases)
![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/Ayush-pbh/dhun?color=blue)](LICENSE)

<img src="docs/banner.png" alt="Dhun banner" width="100%">

**[⬇ Download Dhun.dmg](https://github.com/Ayush-pbh/dhun/releases/latest/download/Dhun-1.0.dmg)**

</div>

---

## What it does

Play something in Spotify. Dhun turns it into a piece of your desk:

🎨 **The floating square** — a borderless, chromeless window showing nothing but the
album art. Drag it anywhere. Double-click to open Spotify. Right-click for a quick menu.

💿 **Vinyl persona** — flip a switch and the square becomes a record that *actually
spins* while music plays (5–78 RPM, your call) and freezes on pause. Color it with five
curated duotones — or **Album colors**, which tints the grooves from the current cover.

🌈 **Palette everywhere** — Dhun extracts the dominant colors from every cover and
feeds them into an ambient glow behind the art, gradient wallpapers, and the vinyl tint.

🖼️ **Wallpaper mode** — the album art becomes your desktop background on every track
change: centered on blurred art, full-bleed, or a palette gradient.

🌀 **Live vinyl desktop** — a record rendered *above* your wallpaper but *below* your
desktop icons, spinning while music plays. A wallpaper that moves.

🏝️ **Notch island** — glide your pointer to the camera and an island expands with
artwork, live progress, and playback controls.

✨ **Moments** — a brief toast on track change, and a full-screen **Ambient mode**
(drifting blurred backdrop, sharp cover, big type) for when the Mac is docked.

🌌 **Seven visualizers** — full-screen generative Metal scenes in Ambient mode, all
steered by Spotify's *actual audio* (ScreenCaptureKit filtered to Spotify + Accelerate
FFT), never a bar chart: **Ambience Plasma** (WMP-era energy clouds and tendrils),
**Nebula** (raymarched volumetric flight), **Ferrofluid** (a spiking liquid-metal
creature), **Aurora** (swaying light curtains), **Ink in Water** (frame-feedback blooms
that remember the song), **Warp Field** (hyperspace streaks that accelerate with bass),
and **Murmuration** (a 14,000-bird GPU flock). Five color moods or live album-palette
tints; bass moves the large masses, mids stir turbulence, highs add flicker, and every
scene stays alive in quiet passages. Needs the screen & system audio recording
permission — never touches the microphone.

🕹️ **Controls where you want them** — hover the square for a **Liquid Glass** control
pill (macOS 26), scroll on it for volume, or use the menu bar item.

🫥 **Quiet by design** — optional click-through mode, invisible-to-screen-sharing mode,
hideable Dock icon, launch at login. Everything is a toggle in **Settings (⌘,)**.

## Install

1. **[Download Dhun-1.0.dmg](https://github.com/Ayush-pbh/dhun/releases/latest/download/Dhun-1.0.dmg)**
2. Open it and drag **Dhun** into **Applications**.
3. First launch: **right-click → Open** (Dhun is not notarized yet, so plain
   double-click will be blocked by Gatekeeper the first time).
4. Approve the **Automation** prompt — that's how Dhun reads the current track from
   Spotify. (Changed your mind later? System Settings → Privacy & Security →
   Automation → Dhun → Spotify.)

Needs macOS 13+ and the [Spotify desktop app](https://www.spotify.com/download/mac/) —
the web player is not scriptable.

## Build from source

```sh
git clone https://github.com/Ayush-pbh/dhun.git
cd dhun
./build.sh
open build/Dhun.app
```

Build with `build.sh` rather than `swift run` — macOS ties the automation permission to
the app bundle. To hack on it in Xcode, just open `Package.swift`.

Regenerate the icon or banner after tweaking the scripts:

```sh
swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Dhun.icns
swift scripts/make-banner.swift
```

## How it works

- **`SpotifyController`** talks to the Spotify app over Apple events: current track,
  artwork URL, playback position, and commands (play/pause/next/previous/volume). It
  never launches Spotify — it only queries when Spotify is already running.
- **`PaletteExtractor`** downsamples each cover to 32×32 and scores quantized color
  clusters by frequency × vibrancy.
- **`VinylLayer`** is one Core Animation record shared by the square and the desktop
  scene; rotation pauses and resumes via layer time manipulation, and speed changes
  rebuild the animation from the current angle so the disc never jumps.
- **`WallpaperManager`** renders per-screen wallpapers with Core Image into
  `~/Library/Application Support/Dhun/Wallpapers/` and applies them with
  `NSWorkspace.setDesktopImageURL`.
- The notch island, toast, ambient scene, and desktop vinyl are independent borderless
  windows driven by one shared `NowPlayingModel`.

## Roadmap

- Album wall — listening-history collage wallpaper
- Cassette & CD personas
- Shortcuts / App Intents automation
- Developer ID signing + notarization

## License

[CC BY-NC-SA 4.0](LICENSE) — © 2026 Ayush Tripathi. Free to use, modify, and share
for **non-commercial** purposes, with attribution, under the same license.

Dhun deliberately uses this license so it can adapt visualizer shaders from the
[Shadertoy](https://www.shadertoy.com) community, whose default license is
CC BY-NC-SA 3.0. Every adapted shader is credited below and carries an attribution
header in the source.

### Shader credits

- **Butterfly** — adapted from an unattributed Shadertoy sketch (Shadertoy default
  license, CC BY-NC-SA 3.0): spectrum-driven radial displacement with mirrored
  butterfly symmetry. Changes: GLSL → Metal, the source image is the current album
  cover, Spotify's live spectrum drives the warp (remapped to span the full range),
  aspect-filled sampling.
- **Calm Flow** — adapted from "Calm Flow" by **Sebastien Durand**, 2014
  (CC BY-NC-SA 3.0), building on iq's
  [bicubic filtering](https://www.shadertoy.com/view/XsSXDy), the
  [heatmap palette study](https://www.shadertoy.com/view/4dsSzr), and iq's
  [distance-to-isoline article](https://iquilezles.org/articles/distance).
  Changes: GLSL → Metal, bicubic noise texture → procedural noise, heatmap
  palette → Dhun's tint ramp, mouse control removed. Intentionally not
  audio-reactive — only its colors follow the scheme.
- **Cloud Canal** — adapted from "Cloud Canal" by
  **[Stephane Cuillerdier (Aiekick)](https://www.shadertoy.com/user/aiekick)**, 2015
  (CC BY-NC-SA 3.0), a variation of his
  ["Another Cloudy Tunnel"](https://www.shadertoy.com/view/4lSXRK); cloud technique
  from duke's ["Cloudy spikeball"](https://www.shadertoy.com/view/MljXDw), itself a
  port of a demo part by Las. Changes: GLSL → Metal, texture noise → procedural,
  cloud whites softened toward the accent tint, palette via Dhun's tint system.
  Intentionally not audio-reactive — only its colors follow the scheme.
- **Gilled** — an original Gray-Scott reaction-diffusion simulation written
  for Dhun (no ported code), inspired by the reaction-diffusion visualizers
  on Shadertoy. Bass onsets splash droplets into the dish; the labyrinthine
  "gill" stripes grow from there.
- **MoonWalk** — adapted from "MoonWalk" by
  **[Nikos Papadopoulos (4rknova)](https://www.shadertoy.com/user/4rknova)**, 2015
  (CC BY-NC-SA 3.0). Changes: GLSL → Metal, the fixed flight speed replaced with a
  music-driven integrated travel distance, moonlight routed through Dhun's tint
  system, grain follows the highs, camera sway follows the mids.

- **Volumetric Explosion** — adapted from ["Volumetric explosion"](https://www.shadertoy.com/view/lsySzd)
  by **Duke** (CC BY-NC-SA 3.0), itself building on Duke's
  ["Supernova remnant"](https://www.shadertoy.com/view/MdKXzc), otaviogood's
  ["Alien Beacon"](https://www.shadertoy.com/view/ld2SzK), and Shane's
  ["Cheap Cloud Flythrough"](https://www.shadertoy.com/view/Xsc3R4).
  Changes: GLSL → Metal, texture noise → procedural, the looping animation clock
  replaced with a bass-onset-driven explosion lifecycle on continuous time,
  colors routed through Dhun's tint system.

<div align="center">
<sub>Dhun is an independent project and is not affiliated with or endorsed by Spotify.</sub>
</div>

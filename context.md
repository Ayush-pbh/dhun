# Dhun — context brief for article writing

This file is source material for writing an article about Dhun. Everything in
it is factual as of v1.1.0 (August 2026). Structure: pitch → facts → features
→ tech → development stories → numbers → guardrails.

---

## The pitch

**Dhun** (धुन, Hindi for "melody") is a tiny native macOS app that turns
whatever Spotify is playing into a living piece of your desktop. At its
smallest it's a borderless, chromeless square of album art floating on your
screen. At its biggest it's a full-screen generative Metal visualizer driven
by the *actual audio* coming out of Spotify. It is 100% Swift — AppKit +
SwiftUI + Metal. No Electron, no JavaScript, no web views. The whole app is
about 1.4 MB.

- Repo: https://github.com/Ayush-pbh/dhun
- Latest release: v1.1.0 — https://github.com/Ayush-pbh/dhun/releases/tag/v1.1.0
- Author: **Ayush Tripathi** — https://ayusht.me (GitHub: Ayush-pbh)
- License: CC BY-NC-SA 4.0 (v1.1+; v1.0 was MIT — see the license story below)
- Requirements: macOS 13+, Spotify desktop app
- Not affiliated with or endorsed by Spotify

## Feature inventory

**The floating square** — a borderless window showing only the album art.
Draggable anywhere, double-click opens Spotify, right-click for a quick menu,
optional momentum physics when you "throw" it, optional click-through mode
(pure decoration), optional invisibility to screen sharing.

**Vinyl persona** — the square becomes a record that actually spins while
music plays (5–78 RPM, user-set) and freezes on pause. Five curated duotone
color schemes, or "Album colors" which tints the grooves live from the cover.

**Palette extraction** — Dhun pulls dominant colors from each cover
(32×32 downsample, clusters scored by frequency × vibrancy) and feeds them
everywhere: glow, wallpapers, vinyl tint, visualizer colors.

**Wallpaper mode** — album art becomes the desktop wallpaper on every track
change: centered-on-blurred-art, full-bleed, or palette gradient.

**Live vinyl desktop** — a spinning record rendered above the wallpaper but
*below* the desktop icons. A wallpaper that moves.

**Notch island** — glide the pointer to the camera notch and an island
expands with artwork, progress, and playback controls.

**Ambient mode** — full-screen now-playing scene: sharp cover, big
typography, and either a drifting blurred backdrop or a visualizer. Click or
Esc to leave.

**Liquid Glass controls** — hovering the square reveals a control pill using
macOS 26's glass effect; scroll on it for volume.

**Everything is a toggle** — every feature above lives behind a switch in a
native Settings pane (⌘,) with tabs: Square, Wallpaper, Extras, General,
About (version, links, credits, license, roadmap).

## The visualizers (the headline feature of v1.1)

Eight full-screen generative Metal scenes in ambient mode. The design rule,
set explicitly from day one: **never a bar chart** — no equalizer bars, no
spectrum columns, no waveforms. The FFT is a *control signal* steering a
generative simulation: bass moves large masses, mids stir turbulence, highs
add fine flicker, and every scene stays alive during silence.

1. **Ambience Plasma** — Windows-Media-Player-era energy clouds and tendrils.
   Original, by Ayush Tripathi.
2. **Ink in Water** — frame-feedback ink blooms that "remember" the song;
   the frame literally feeds on its own past. Original.
3. **Murmuration** — a 14,000-bird GPU flock (compute shader) with trails.
   Original.
4. **Movement** — the live spectrum painted as a breathing ring of tinted
   light (angle = frequency), smeared into drifting paint by a feedback
   current. Original.
5. **Volumetric Explosion** — raymarched explosions that detonate ONLY on
   bass onsets and never loop. Adapted from "Volumetric explosion" by Duke
   (Shadertoy, CC BY-NC-SA 3.0).
6. **MoonWalk** — a moonlit flight whose speed rides the music via an
   integrated travel distance (speed changes, position never jumps). Adapted
   from Nikos Papadopoulos (4rknova).
7. **Cloud Canal** — drifting volumetric cloud tunnel. Adapted from Stéphane
   Cuillerdier (Aiekick). Deliberately NOT audio-reactive — only its colors
   follow the scheme.
8. **Calm Flow** — serene isoline flow. Adapted from Sebastien Durand. Also
   deliberately non-reactive.

Every scene takes five color moods or live album-palette tints. A **React to
sound** toggle mutes the reaction (and stops audio capture entirely). A
debug overlay shows the raw capture waveform, real FPS, and live controls to
hop between scenes.

## How the audio pipeline works (the most article-worthy tech)

macOS has no public "what is Spotify playing" audio API. Dhun's route:

1. **ScreenCaptureKit** captures system audio *filtered to the Spotify app*
   (the mandatory video stream is configured to 2×2 pixels at 1 fps and
   dropped — as close to free as the API allows). It never touches the mic.
   If the app-filtered stream turns out silent (audio routed via a helper
   process), a watchdog falls back to display-wide capture after 3 s.
2. **Accelerate vDSP FFT** — 1024 samples, Hann window, reduced to 48
   log-spaced bands (~45 Hz–16 kHz).
3. Bands are condensed into smoothed control signals — bass/mid/high/level,
   each with its own attack/decay (bass slow and heavy, highs twitchy) —
   plus a **bass-onset detector**: the instantaneous bass jumping above its
   own long-term average (ratio-based, so it still fires on heavily
   compressed EDM masters), with a cooldown so one drop fires one event.
   That onset is what triggers the explosions.
4. A single Metal view renders via three strategies: pure fragment shaders,
   ping-pong feedback accumulation (ink, movement), and a compute-driven
   particle system (murmuration). Heavy raymarchers render at reduced
   resolution and upscale invisibly.

Spotify control/metadata is classic Apple events (AppleScript) — track,
artwork URL, position, play/pause/next/volume.

## Development stories (the narrative gold)

**The permission saga.** The visualizers need macOS's Screen & System Audio
Recording permission. During development the waveform kept flatlining after
every rebuild: macOS ties the permission grant to the app's code signature,
and ad-hoc signatures change on every build — so each rebuild silently
revoked the permission, and macOS never re-asks after a denial. The fix was
a local self-signed "Dhun Dev" certificate so the signature stays stable
across builds (the repo ships `scripts/make-signing-cert.sh`). The debug
overlay (waveform + FPS) was built during this saga to prove whether audio
was even arriving.

**The license pivot.** v1.0 shipped MIT. The best visualizer material lives
on Shadertoy, whose default license is CC BY-NC-SA 3.0 — incompatible with
MIT distribution. Decision: relicense the whole project to CC BY-NC-SA 4.0
so Shadertoy work could be adapted legally, with attribution headers in the
source, credits in the README, and credits in the app's About tab. The
trade: Dhun can never be sold while it contains those shaders. (v1.0
remains MIT — that grant is irrevocable.)

**Curation by murder.** Far more visualizers were built than shipped:
Nebula, Ferrofluid, Aurora, Warp Field, Butterfly (album art warped by the
spectrum with mirrored wings), Gilled (an original Gray-Scott
reaction-diffusion sim fed by bass onsets), Dream, and an "Ambience" ring
were all built, evaluated against real music, and cut. The final eight are
the survivors of a taste filter, not a feature list.

**The Gatekeeper problem.** Dhun isn't notarized (that needs Apple's
$99/year Developer Program), so browser-downloaded DMGs trigger macOS's
"Apple could not verify" dialog — and macOS Sequoia removed the old
right-click→Open bypass. Solution: a one-line curl installer
(`curl -fsSL https://raw.githubusercontent.com/Ayush-pbh/dhun/main/install.sh | sh`)
— browsers stamp downloads with the quarantine flag, `curl` doesn't, so the
installed app opens with zero dialogs. Same pattern Homebrew itself uses.

**Homebrew.** Dhun is installable via a personal tap
(`brew install --cask ayush-pbh/tap/dhun`). Discovery made while setting it
up: Homebrew 6 removed the `--no-quarantine` flag entirely, so brew installs
of unnotarized apps now always face the Gatekeeper dialog — the tap's value
is `brew upgrade`, not dialog avoidance. Getting into the official
homebrew-cask repo requires "notability" (roughly 75+ GitHub stars).

**Built with an AI pair.** The app was developed collaboratively with
Claude Code (Anthropic's coding agent) driving implementation under Ayush's
direction and taste calls. (Include or omit in the article as desired —
listed here for completeness.)

## Numbers that make good copy

- ~1.4 MB DMG (compare: Electron apps start ~100 MB)
- 100% Swift; zero JavaScript
- 8 shipped visualizers; ~7 more built and cut
- 14,000 birds in the murmuration
- 1024-sample FFT → 48 log-spaced bands, 60 fps rendering
- 5–78 RPM vinyl range (33⅓ default)
- 2×2 pixels — the size of the throwaway video stream the audio capture requires
- 2 releases: v1.0.0 (the square, vinyl, wallpaper era) → v1.1.0 (the
  visualizer era)

## Accuracy guardrails — do NOT claim

- Dhun is not affiliated with, endorsed by, or connected to Spotify.
- It does not use the microphone, and captures no audio when React to sound
  is off.
- It is not notarized; don't promise a friction-free double-click install
  from the DMG.
- License is non-commercial (CC BY-NC-SA 4.0) — it cannot be sold.
- It requires the Spotify *desktop* app; the web player is not scriptable.
- Don't invent Shadertoy URLs for the adapted shaders; credit the authors as
  named above (full details in the README's "Shader credits" section).

## Suggested angles (writer's choice)

- "A 1.4 MB answer to Electron" — native minimalism as a statement.
- The audio-capture-permission saga as a window into macOS's TCC system.
- Choosing a *worse* license on purpose: NC as the price of beautiful shaders.
- Generative visualizers vs. bar-chart visualizers — the taste manifesto.
- Shipping unsigned software in the Gatekeeper era (curl installer, Homebrew,
  the $99 question).

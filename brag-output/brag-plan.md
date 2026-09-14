# Brag Plan: Gitlines

## What is this app?
Gitlines is a native macOS widget that puts your real GitHub commit activity — exact additions, deletions, net lines, peak hours, and repository rankings — on your desktop, in six completely different visual themes across four purpose-built widget sizes.

## The angle
This is a craft flex, not a feature list. The absurd, specific, brag-worthy fact about Gitlines is the ratio of design effort to surface area: it is *a widget*, and it has six full bespoke themes — a translucent glasshouse, a phosphor terminal, a newsprint broadsheet, a four-color arcade handheld, a modular Blockwork studio — each with four hand-built layouts, all rendering the identical snapshot. The README says it plainly: "Every theme uses the same activity snapshot; changing the look never changes the numbers." That line is the whole video.

And then, buried in the same codebase that carefully deduplicates commits across branches by SHA, there is a snake whose internal states are literally named `smol snek`, `growing snek`, and `snek happy`. The video takes the craft completely seriously for 14 seconds and then shows you the snake. The joke is that both things are true.

## Hook (first 2-3 seconds)
Near-black screen. A single huge mint number counts up — `+1,247` — then a coral `−389` drops in beneath it. No logo, no product name yet. Just the numbers a developer recognizes instantly as their own day. The viewer reads it as a stat card; they don't yet know it's a widget.

## Key moments (the middle)
- The pull-back: the numbers turn out to be *inside* a widget sitting on a macOS desktop. The abstract stat becomes a real product in one move.
- The theme carousel: the same widget re-skins six times on the beat — Default, Glasshouse, Phosphor, Broadsheet, Arcade, Blockwork — while `+1,247 / −389 / 23 commits` never moves. The numbers are the control variable; the design is the variable.
- The snek: hard cut to the commit snake, with its own real state labels ticking `smol snek → growing snek → snek happy`.

## Outro / punchline
Logo mark lands. "Six themes. Four sizes. One honest number." Then the small line underneath, deadpan: `also: a snake`.

## User flow worth showing
Entry → key action → result:
1. Widget sits on the desktop showing today's real commit activity (entry — the always-on state).
2. Open Widget Studio and change the theme (key action).
3. The widget re-skins instantly; the snapshot is untouched (result).
The carousel scene *is* this flow, compressed — it shows the theme change and the invariant numbers simultaneously.

## Tone
- Preset: `polished`
- Creative direction: quiet macOS product film that takes six themes extremely seriously, then admits there is a snake
- Interpretation: Restraint for the first four-fifths — long holds, real product surfaces, no motion for motion's sake, type that behaves like Apple marketing. The snek scene keeps the exact same visual composure; the humor lands *because* nothing about the delivery changes. No wink, no comedy typography.

## Format: landscape — 1920x1080
## Duration: 21s

## Visual identity (from the project)
Pulled from `widtget/Views/Palette.swift`, `widtgetApp/ThemePalette.swift` (`DashboardPalette` + per-theme cases), and `logo/README.md`.

- Background: `#090C10` (DashboardPalette.ink — rgb 0.035/0.047/0.063)
- Panel: `#12161B` (panel) · Lifted: `#171D23` (lifted) · Hairline: `rgba(255,255,255,0.09)`
- Primary text: `#EDF2F7` (text) · Muted: `#8592A3` (muted)
- Accent (additions): `#38CC75` (green) · Deletions: `#F26166` (coral)
- Display font: SF Pro Display / -apple-system stack (native macOS — the product is a macOS widget, so system type is correct, not a web font)
- Body font: same stack; `ui-monospace / SF Mono` for numerics, repo rows, and the Phosphor theme
- Strongest visual element: the widget surface itself — big signed numerics, activity bar row, repo ledger rows, and the commit snek

### Theme palettes (exact, from `ThemePalette.swift`)
| Theme | ink | text | green | coral |
|---|---|---|---|---|
| Default | `#090C10` | `#EDF2F7` | `#38CC75` | `#F26166` |
| Glasshouse | `#1C1D21` | `#F2F3F5` | `#7EE2A8` | `#F0868C` |
| Phosphor | `#06090A` | `#4AF08A` | `#4AF08A` | `#FFB340` |
| Broadsheet | `#E9E4D5` | `#19170F` | `#19170F` | `#9E2F1B` |
| Arcade | `#0F380F` | `#8BAC0F` | `#9BBC0F` | `#D94F1E` |
| Blockwork | `#090C10` | `#EDF2F7` | `#38CC75` | `#F26166` |

## Share copy (draft)
Six themes. Four sizes. One commit snapshot that never changes when the look does. Gitlines puts your real GitHub activity on your Mac desktop — and yes, there is a snake.

## Audio direction
- Role: warm restrained bed with beat-locked structural moments
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (114.84 BPM; dense, evenly-spaced strong cues from 1.60s make the theme carousel land musically)
- Music treatment: start at 0, sit at ~0.34 under the whole video, gentle fade-in over the first 0.6s, fade out from 19.5s to 21.0s so the final line reads in near-silence
- Music cue guidance: bundled preset read from `assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.json`. Strong cues in window: 1.60, 3.18, 3.70, 5.28, 5.80, 6.34, 8.44, 8.96, 9.50, 12.12, 12.65, 14.22, 17.91, 19.49. Beat grid ~0.525s apart. Lock three: coral number at 1.60, widget landing at 3.70, logo at 17.91. Theme swaps ride every-other-beat (8.96 / 10.01 / 11.06 / 12.12 / 13.18) — never every beat, the labels must stay readable.
- Audio-reactive treatment: subtle. Widget surface presence/glow and desktop background depth breathe with RMS/bass only. No waveform, equalizer, or particle visuals.
- SFX posture: sparse and motion-matched. A soft interface tick per theme swap, one dry accent on the widget landing, one on the logo. Nothing on the snek scene — silence sells the deadpan.
- Audio-coupled moments: count-up on the hook number; widget landing; five theme swaps on the beat grid; logo landing.
- Restraint rule: audio must never outrun readability. No SFX stacking on the carousel, no music swell over the final line, and no beat snap that shortens a theme label below its reading floor.

## Storyboard

### Scene 1 — The number — 3.7s
Near-black `#090C10`. Centered: `+1,247` in `#38CC75`, huge, tabular numerics, counting up from 0. At 1.60s `−389` drops in beneath it in `#F26166`. Below both, small muted caption: `Today. Across every branch.` No branding yet.
Sequential/interaction: yes — additions count up first, deletions land second on the strong cue.
Audio intent: quiet confidence; the bed establishes, the coral number lands on a hit.
Audio-coupled idea: counter ticks under the count-up; the `−389` entrance is beat-locked to 1.60s.
Music: warm restrained bed, fading in.
Transition mood: soft → Scene 2

### Scene 2 — It's a widget — 4.2s
Camera pulls back (seek-safe scale/position keyframes). The numbers are revealed to be inside a Gitlines medium widget resting on a macOS desktop surface. The widget fills in around them: `@yuuv · Daily` header, `23 commits`, the activity bar row, two repo ledger rows. Title lockup enters at the side: **Gitlines** / `Your GitHub activity, on your desktop.`
Sequential/interaction: yes — widget chrome assembles around the existing numbers; the numbers themselves never re-animate.
Audio intent: the payoff of the hook; one dry accent as the widget seats itself.
Audio-coupled idea: widget landing beat-locked to 3.70s.
Music: bed continues, bass presence subtly modulating the widget's glow.
Transition mood: clean → Scene 3

### Scene 3 — Same snapshot, six faces — 6.3s
The widget stays locked in frame and re-skins through all six themes. A small theme-name chip sits beneath it and swaps in step: Default → Glasshouse → Phosphor → Broadsheet → Arcade → Blockwork. A persistent line holds above: `Same snapshot. Six faces.` The three numbers (`+1,247`, `−389`, `23 commits`) are pinned and visibly identical through every swap — this is the point of the scene.
Sequential/interaction: yes — five theme swaps at ~1.05s each, each a full palette + typography change (Phosphor goes monospace green, Broadsheet goes serif on newsprint, Arcade goes four-color LCD).
Audio intent: rhythmic but controlled; each swap ticks with the music instead of over it.
Audio-coupled idea: swaps on the every-other-beat grid at 8.96 / 10.01 / 11.06 / 12.12 / 13.18, each with one soft interface tick at the same timestamp.
Music: bed at full presence, the most musical stretch of the video.
Transition mood: hard → Scene 4

### Scene 4 — The snake — 3.7s
Hard cut, same composure. Close on the commit snek inside the widget — the snake grows segment by segment as commits accumulate. Its real state label ticks beneath it in the product's own words: `smol snek` → `growing snek` → `snek happy`. One caption, dry: `It also grows a snake.`
Sequential/interaction: yes — snake segments extend; the three state labels swap in place.
Audio intent: pull back. Music thins, no SFX at all — the restraint is the joke.
Audio-coupled idea: none. Deliberate SFX silence.
Music: bed drops in presence, no accents.
Transition mood: soft → Scene 5

### Scene 5 — Lockup — 3.1s
The Gitlines monoline mark draws in on `#090C10` (chalk `#EDECE8` branch lines, sage `#7B9E87` addition path, terracotta `#C86C5A` deletion path). Wordmark **Gitlines** beneath. One line: `Six themes. Four sizes. One honest number.` Then, small and muted, a beat later: `also: a snake`. Footer: `macOS · App Store`.
Sequential/interaction: yes — mark draws, wordmark settles, primary line holds, the small line arrives last and holds to the end.
Audio intent: resolve and clear out; the last line reads in near-silence.
Audio-coupled idea: logo landing beat-locked to 17.91s; music fades 19.5s → 21.0s.
Music: fading to silence.

**Music mood for this video:** upbeat-restrained (polished bed, beat-locked structure, no swell)
**Audio summary:** A warm bed fades in under the opening numbers, locks three structural moments (the coral number, the widget landing, the logo), ticks lightly through the six-theme carousel on an every-other-beat grid, deliberately goes quiet for the snake, and fades out so the final deadpan line lands in near-silence.

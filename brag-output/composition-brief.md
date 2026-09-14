# Hyperframes Composition Brief: Gitlines

## Objective
Create a short launch-style brag video for Gitlines, a native macOS widget for GitHub commit activity.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 21s

## Source Material
- Project root: `/Users/yuuvjauhari/widget-github`
- Primary files read: `README.md`, `widtget/Views/Palette.swift`, `widtgetApp/ThemePalette.swift` (per-theme palette cases), `widtgetApp/AnalyticsDashboardView.swift` (`DashboardPalette`), `Shared/WidgetPreferences.swift` (`WidgetVisualTheme`), `widtget/Views/ActivityVisualization.swift` (commit snek states), `widtget/Views/DefaultWidgetView.swift` (widget layout), `logo/README.md` + `logo/gitlines-mark.svg`
- Product name: Gitlines
- Tagline / strongest claim: "Every theme uses the same activity snapshot; changing the look never changes the numbers."
- Key UI to recreate: the Gitlines medium widget — signed additions/deletions numerics, `@user · Daily` header, commit count, activity bar row, repository ledger rows, and the commit snek — rendered faithfully in all six real theme palettes.
- Copy that must appear verbatim (all from the product's own source or README):
  - `smol snek`
  - `growing snek`
  - `snek happy`
  - `Default` / `Glasshouse` / `Phosphor` / `Broadsheet` / `Arcade` / `Blockwork`

## Creative Direction
- Tone preset: `polished`
- Creative direction: quiet macOS product film that takes six themes extremely seriously, then admits there is a snake
- Interpretation: Long holds, real product surfaces, restrained motion, Apple-marketing type discipline. The snek scene keeps identical composure — the humor works because the delivery never winks.
- Angle: The brag is the ratio of design effort to surface area. It is *a widget*, and it has six bespoke themes across four hand-built sizes, all rendering one identical snapshot. Fourteen seconds of genuine craft, then the snake.
- Hook: A huge mint `+1,247` counting up on near-black, joined by a coral `−389`. Numbers only — the viewer does not yet know it is a widget.
- Outro / punchline: "Six themes. Four sizes. One honest number." then, small and muted: `also: a snake`
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign (do not invent a brand — the palettes are all real)

## Visual Identity
- Background: `#090C10` · Panel `#12161B` · Lifted `#171D23` · Hairline `rgba(255,255,255,.09)`
- Text: `#EDF2F7` · Muted `#8592A3`
- Accent: additions `#38CC75` · deletions `#F26166`
- Display font: `-apple-system / SF Pro Display` system stack (native macOS product — system type is correct here, not a web font)
- Body font: same stack; `ui-monospace / SF Mono` for numerics, repo rows, and the Phosphor theme
- Per-theme palettes: see the exact table in `brag-plan.md` (transcribed from `ThemePalette.swift`)
- Visual references from the project: the widget surface, the commit snek, the monoline logo mark (`logo/gitlines-mark.svg` — chalk `#EDECE8` branches, sage `#7B9E87` addition path, terracotta `#C86C5A` deletion path)

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. The number — 3.7s — `+1,247` counts up, `−389` lands on the beat, caption `Today. Across every branch.`
2. It's a widget — 4.2s — pull-back reveals the numbers inside the Gitlines widget on a macOS desktop; title lockup enters
3. Same snapshot, six faces — 6.3s — the widget re-skins through all six themes on an every-other-beat grid; the three numbers stay pinned and identical
4. The snake — 3.7s — close on the commit snek; state labels tick `smol snek` → `growing snek` → `snek happy`
5. Lockup — 3.1s — monoline mark draws, wordmark, `Six themes. Four sizes. One honest number.`, then `also: a snake`

## Audio
- Audio role: warm restrained bed with three beat-locked structural moments
- Audio arc: fades in under the opening numbers → full presence through the carousel → thins deliberately for the snake → fades out so the final line reads in near-silence
- Music: `assets/music/happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (114.84 BPM)
- Music treatment: starts at 0, sits at ~0.34, 0.6s fade-in, fade out 19.5s → 21.0s
- Music cue guidance: bundled preset at `assets/music/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.json`. Strong cues: 1.60, 3.18, 3.70, 5.28, 5.80, 6.34, 8.44, 8.96, 9.50, 12.12, 12.65, 14.22, 17.91, 19.49. Beat grid ~0.525s. Lock three only: `−389` at 1.60, widget landing at 3.70, logo at 17.91. Theme swaps on every-*other*-beat (8.96 / 10.01 / 11.06 / 12.12 / 13.18) so each theme label clears its reading floor.
- Audio-reactive treatment: subtle — widget surface presence and desktop background depth breathe with RMS/bass. No waveform, equalizer, or particle visuals.
- Audio-coupled moments:
  - Scene 1 `−389` landing — beat-locked accent (`interface/bong_001.ogg`)
  - Scene 2 widget landing — one dry major-reveal hit (`impact/impactSoft_medium_001.ogg`)
  - Scene 3 five theme swaps — one soft tick each, same timestamp as the visual (`ui/click2.ogg`)
  - Scene 4 — deliberate SFX silence
  - Scene 5 logo landing — one warm accent (`impact/impactSoft_medium_004.ogg`)
- SFX selection guidance: all picks are low high-frequency risk per `sfx-analysis.md`, appropriate for a polished tone with a repeated element (the five carousel ticks).
- SFX analysis guidance: `~/.claude/skills/brag/assets/sfx/sfx-analysis.md` — low-HF-risk files chosen because the carousel repeats a sound five times.
- Audio files: already copied into `brag-output/composition/assets/` (music, cues JSON, and the four SFX above).

## Hyperframes Instructions
Build with `hyperframes-core` (composition contract + `data-*` timing), `hyperframes-animation` (motion), `hyperframes-creative` (design spec, audio-reactive), `hyperframes-keyframes` (the Scene 2 pull-back must be seek-safe), and `hyperframes-cli` (check/render). This is the `/brag` workflow — do not enter the `hyperframes` entry-point intent interview.

Requirements:
- Show real product UI: the widget surface in all six real theme palettes, with the product's own verbatim snek copy.
- Keep every line readable: theme labels get ~1.05s each; the three snek state labels get ~1.0s each.
- Total duration 21s.
- Include the music bed and the five SFX moments above.
- Registry/catalog is unreachable in this environment (`hyperframes catalog` fails to fetch) — hand-author the motion rather than installing blocks.
- Run `npx hyperframes check` before render — brag's single gate.

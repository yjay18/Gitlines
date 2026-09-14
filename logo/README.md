# GitLines — Brand & Logo Assets

This directory contains vector assets (SVG) for the **GitLines** product brand and macOS app icon.

## Files

| File | Purpose | Canvas | Background |
| :--- | :--- | :--- | :--- |
| [`gitlines-icon.svg`](gitlines-icon.svg) | Official macOS App Icon | `1024 × 1024` | Dark squircle (`#1E2026` → `#141519`) |
| [`gitlines-mark.svg`](gitlines-mark.svg) | Brand vector mark for headers, docs, websites | `800 × 500` | Transparent |
| [`gitlines-mark-monochrome.svg`](gitlines-mark-monochrome.svg) | Monochrome / Menu bar vector mark | `800 × 500` | Transparent (`currentColor`) |

---

## Palette Specifications

| Token | Name | Hex Code | Role |
| :--- | :--- | :--- | :--- |
| **Canvas Background** | Obsidian Dark | `#141519` · `#1E2026` | macOS App Icon Squircle body |
| **Branch / Track Line** | Chalk Monoline | `#EDECE8` | Continuous git branch lines |
| **Commit Core** | Git Commit Center | `#18191E` | Inner commit node |
| **Additions (`+`)** | Muted Sage Green | `#7B9E87` | Additions diff indicator |
| **Deletions (`-`)** | Muted Terracotta Red | `#C86C5A` | Deletions diff indicator |

---

## Design Rationale

- **Metaphor**: A central git commit node acting as the core hub, merging incoming branch flows and diverging into code additions (`+`) and deletions (`-`).
- **2D Aesthetic**: Clean, modern, flat vector linework inspired by modern developer tooling (Linear, Zed, Raycast).
- **Scalability**: Pure SVG paths with `stroke-linecap="round"` and `stroke-linejoin="round"` that scale cleanly from a 16px menu bar icon up to 1024px retina displays.

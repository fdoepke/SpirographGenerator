# Spirograph Generator (macOS)

SwiftUI app for designing spirographs and exporting them as **SVG** or **G-code** (pen plotters, CNC with a pen holder, laser/servo setups).

## Requirements
- macOS 14 Sonoma or later
- Xcode 15 or later

## Run
1. Open `SpirographGenerator.xcodeproj` in Xcode.
2. Select the *SpirographGenerator* scheme and *My Mac*, then press ⌘R.
   (Signing is "Sign to Run Locally"; pick your Team under *Signing & Capabilities* if you want to distribute it.)

## Controls
| Setting | Meaning |
|---|---|
| Mode | Wheel rolls inside the ring (hypotrochoid) or outside it (epitrochoid) |
| Fixed ring radius R | Size of the stationary ring ("teeth") |
| Rolling wheel radius r | Size of the moving wheel |
| Pen offset d | Distance of the pen hole from the wheel centre |
| Close curve automatically | Draws exactly the number of turns needed to close the curve (r / gcd(R, r)) |
| Turns | Manual number of loops around the ring when auto-close is off |
| Smoothness | Points per turn |
| Copies / angle / rotation | Repeat the curve rotated by a fixed angle – great for mandalas |
| Drawing size | Width & height of the exported drawing in mm |

## Export
- **SVG** (⌘E): size in mm, one `<path>` per copy in a `spirograph` group (rainbow / MMU colours preserved), optional background, and an optional **skirt** as a separate `skirt` group in its own colour – traced around the outer contour with exact distances and written as smooth cubic Béziers (the SVG grows to fit it).
- **G-code** (⇧⌘E) – choose the format from the *Format* popup in the G-code section:
  - **Plain** – minimal G21/G90 + G0/G1. Pen via Z axis or custom commands (e.g. `M3 S30` / `M5` for a GRBL servo or laser). Origin at centre or bottom-left.
  - **CNC (GRBL / LinuxCNC / Mach3)** – `%`-delimited program, `(parenthesis)` comments, `G17 G21 G90 G94` setup, safe-Z retract between paths, plunge feed, optional `N` line numbers, `M30` end.
  - **Prusa 3D printer (PrusaSlicer)** – prints the spirograph line as a thin wall with real extrusion, so it shows up in PrusaSlicer's G-code viewer and runs on the printer. Choose printer (MK4S, MK4, CORE One, MK3S, MK3S + MMU3 with filament slot 1–5, MINI), nozzle (0.25–0.8 mm) and filament (PLA, PETG, ASA, ABS, PC, Flex) – temperatures, fan and retraction fill in from the filament and can be tweaked. Set layer heights, number of layers, extrusion width, flow, speeds (capped by the filament's max volumetric speed), retraction and Z-hop. Each printer has standard start/end G-code (heat, home, mesh bed levelling, purge line, park), which you can customise with placeholders. Output includes M73 progress and PrusaSlicer-style filament/time metadata.
  - **Line width (mm)** – the printed line thickness. It is built from several side-by-side extrusion passes (e.g. 2 mm with a 0.4 mm nozzle → 4 passes × 0.53 mm), offset from the curve and spaced so neighbouring beads fuse. The preview draws the line at true scale. *Preferred single-pass width* controls how many passes are used.
  - **Skirt** – optional loops around the *outer contour* of the whole drawing only, at an adjustable distance so they never touch it (number of loops, distance, height in layers). Printed first on each skirt layer to prime the nozzle; shown faintly in the preview.
  - **Line crossings** – where the line runs over a line already printed on the same layer (self-crossings, other copies, other colours), choose *Stop extrusion* (keep moving, no filament) or *Retract & lift* (retract, hop by the Z-hop height, unretract), or extrude normally. *Crossing clearance* sets how far around the existing bead extrusion stops.
  - **MK3S + MMU3 multi-colour** – turn on *Multi-colour* in the MMU3 section to print each copy in the next filament slot (2–5 colours; set Copies ≥ 2). Pick each slot's colour so the preview and SVG match your filaments. Tool changes happen on a wipe tower at the right edge of the bed (the drawing shifts left to make room): ramming of the old filament, `Tn`, then purging the new one (purge volume adjustable). The colour order alternates every layer so the loaded filament is printed first, giving (colours − 1) changes per layer. All slots use the same filament settings.

Export settings (format, sizes, pen/CNC options and all Prusa/MMU/skirt settings, incl. custom start/end G-code) are saved automatically and restored on the next launch. *File › Reset Export Settings to Defaults* restores the factory values.

Shortcuts: ⌘R randomize, presets in the *Spirograph* menu.

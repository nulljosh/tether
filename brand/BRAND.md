# Tether brand kit and design system

A mouse on a cord: Tether keeps your mouse tied to your Mac.

## The mark
A white Liquid Glass mouse and a dark glossy cord on a blue tile, with two soft light bands behind. Two objects, two tones: the mouse is light, the cord is the one dark thing. In dark mode the cord turns light blue so it never disappears.

- `../Tether.icon` is the source of truth (Icon Composer). Three layers: Cord and Mouse are glass with shadows, Sweep is the flat light behind. Preview with `ictool Tether.icon --export-image ... --platform macOS`.
- `../icon.svg` is the flat copy for READMEs (80 px), `icon-1024.png` the rendered 1024, `mark.svg` the glyph alone in `currentColor`.
- Clear space equal to the cord's width. Smallest size 16 px.

## Colour
| Role | Value |
|---|---|
| Accent | `#0b66e4` |
| Accent light (gradient top, dark-mode accent) | `#4cb0ff` |
| Ink (the cord) | `#1d1d1f`, `#cce6ff` in dark mode |
| Text | `#1d1d1f` light, `#f5f5f7` dark |
| Background | `#ffffff` light, warm black from the shared tokens dark |
| Surface | `#f5f5f7` light, `#2a2a2c` dark |

Blue is for actions, links, the connected state and the icon. Orange is only for a problem (mouse not answering, Bluetooth off). Never purple, never green again.

## Motif: the light bands
The icon's two soft bands are the one decoration Tether owns. On the web they sit behind the hero in the accent at 7 percent (`--sweep`), the same two curves as the icon. Nowhere else. No gradients on UI, no drop shadows on cards.

## Type
Tether Sans for text and Tether Display for headlines, both cut from Inter's text and display optical sizes (SF-style, proportional figures, OFL). `scripts/gen_font.py` makes them. The app falls back to the system font if they fail to load.

## Space and shape
- The app: the shared 8 point grid. 96 point badge, 22 point title, 13 point detail, one full-width capsule button.
- The landing: golden ratio. Type steps by phi (13, 16, 20, 26, 42, 68), space by Fibonacci (8, 13, 21, 34, 55, 89, 144).
- Radii: windows 16, controls fully round, icon by Icon Composer.
- Motion is short and honours reduced motion: the badge pulses while connecting, nothing else moves in the app.

`tokens.css` holds Tether's own colours. Everything else comes from the shared jaybulb token file.

# Solitaire Win

A macOS screensaver: the Windows Solitaire win screen, cards bouncing off the foundations and leaving trails. It starts faithful. After a couple of minutes it begins to go wrong (slow motion, bursts of speed, colour cycling, odd paths, broken physics, corrupted drawing), gets worse until it is fully broken, then "reboots" and starts drifting again.

## Install

```sh
brew install xcodegen
./scripts/install.sh
```

Then pick **Solitaire Win** in System Settings → Screen Saver. **Options…** sets how many minutes until it is fully broken, how broken it gets, which kinds of trouble are allowed, and whether to start already broken.

## Harness

`xcodegen generate`, open `SolitaireSaver.xcodeproj`, run the **Harness** scheme. It shows the saver in a window; the title bar shows the chaos level and running effects.

| Key | Action |
|---|---|
| space | pause |
| 1–5 | force an effect: time, colour, path, physics, glitch |
| 0 | clear effects |
| + / − | set chaos by hand |
| a | back to automatic chaos |
| f | chaos clock ×10 |
| r | reboot |
| s | print seed |
| p | save a PNG to the temp folder |

Command-line arguments, for scripted checks: `-seed N -chaos X -force glitch,time -size 2560x1440 -fps YES -ff YES -snap DIR -snaps N -every SECONDS`.

## Layout

- `Sources/Engine.swift` — the win screen: deck order, launch, gravity, bounce, trails.
- `Sources/Chaos.swift` — chaos level over time, which effects start, reboots.
- `Sources/Effects/` — the effects, one file per kind. Each one changes a copy of `Params` every frame.
- `Sources/Renderer.swift`, `Sources/Shaders.swift` — Metal: a canvas that is never cleared, card stamps, canvas glitches, screen effects.
- `Sources/CardArt.swift` — the deck, drawn pixel by pixel at the original 71×96.

# Solitaire Win

A macOS screensaver: the Windows Solitaire win screen, cards bouncing off the foundations and leaving trails. It starts faithful. After a minute or so it begins to go wrong (slow motion, bursts of speed, colour cycling, odd paths, broken physics, corrupted drawing), gets worse until it is fully broken, then "reboots" and starts drifting again.

**[Download and install](https://osfa.github.io/solitaire-win/)** · **[Run it in the browser](https://osfa.github.io/solitaire-win/demo/)** · **[Every effect](https://osfa.github.io/solitaire-win/effects/)**

## Install

1. Download **Solitaire-Win.zip** from the [latest release](https://github.com/osfa/solitaire-win/releases/latest) and unzip it.
2. The screensaver is not notarised by Apple, so clear the download flag first:
   ```sh
   xattr -dr com.apple.quarantine ~/Downloads/"Solitaire Win.saver"
   ```
   Or double-click it, and when macOS refuses, go to System Settings → Privacy & Security and click **Open Anyway**.
3. Double-click **Solitaire Win.saver** and choose to install it.
4. Pick **Solitaire Win** in System Settings → Screen Saver.

Needs macOS 13 or later, on Apple silicon or Intel.

**Options…** sets how many minutes until it is fully broken, how broken it gets, which kinds of trouble are allowed, whether to start already broken, and whether to use the code-drawn deck instead of the original cards.

## Build from source

```sh
brew install xcodegen
./scripts/install.sh
```

This builds the saver and copies it to `~/Library/Screen Savers`. Pushing a `v*` tag builds a release on GitHub Actions and attaches the zip.

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

Command-line arguments, for scripted checks: `-seed N -chaos X -force glitch,time -effect "card cycle,rainbow cards" -effectat SECONDS -size 2560x1440 -fps YES -ff YES -drawn YES -list YES -snap DIR -snaps N -every SECONDS`.

## How it works

- `Sources/Engine.swift` — the win screen: deck order, launches, gravity, bounce, trails. Speeds, bounce and launch directions are measured from a recording of the original.
- `Sources/Chaos.swift` — chaos level over time, which effects start, reboots.
- `Sources/Effects/` — the effects, one file per kind. Each one changes a copy of `Params` every frame.
- `Sources/Renderer.swift`, `Sources/Shaders.swift` — Metal: a canvas that is never cleared, card stamps, canvas glitches, screen effects.
- `Sources/CardArt.swift` — a fallback deck drawn pixel by pixel at the original 71×96.
- `docs/` — the download page, the effects catalogue, and `docs/demo/`, a WebGL2 port of the saver in plain JavaScript (`?warmup=SECONDS`, `?effect=name,name`, `?chaos=X`, `?fast` help testing). `scripts/effect-shots.sh` renders the catalogue's pictures.

## Credits

Card art in `Resources/cards.png` is from Microsoft Windows Solitaire, via a sprite sheet from The Spriters Resource. This project is not affiliated with or endorsed by Microsoft. The source code is MIT licensed; the card art is not covered by that licence.

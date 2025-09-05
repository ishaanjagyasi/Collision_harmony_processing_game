# Collision Harmony

A tiny **Processing** + **OscP5** playground where you **spawn note‑blobs** and **nudge** them with a movable pad. When two blobs touch, the game sends their **pitch classes** to **Max/MSP** for sonification.

## Requirements
- Processing (Java mode)
- Library: **OscP5** (Install via *Sketch → Import Library… → Add Library…*)
- Optional: **Max/MSP** (receiver)

## Run
1. Open the `.pde` sketch in Processing.
2. Press **Run**.  
   OSC is sent to `127.0.0.1:7400` by default.

## Controls
- **Arrows** — move pad  
- **W / S** — change current pitch class (big popup shows note)  
- **A / D** — pad length − / +  
- **Mouse click** — spawn blob at cursor (current pitch)  
- **X** — delete all blobs of current pitch class  
- **Backspace / Delete** — delete nearest blob  
- **V** — toggle pad vertical/horizontal  
- **C** — clear all blobs

## OSC Messages (to Max)
```text
/collision   i i s f f f     # pcA pcB label score cx cy
/blob/update i i f f f f f   # id pc x y vx vy speed   (sent every frame)
```
Pitch‑class map: `0:C 1:C# 2:D 3:Eb 4:E 5:F 6:F# 7:G 8:Ab 9:A 10:Bb 11:B`.

## Max Quick Start
```
[udpreceive 7400] → [oscparse] → [route /collision /blob/update]
```
- `/collision`: convert `pcA/pcB` with `+60 → mtof` and trigger envelopes.  
- `/blob/update`: use `x` for pan, `y` for filter cutoff, `speed` for vibrato depth.

---

MIT License (or choose your own). Contributions welcome!

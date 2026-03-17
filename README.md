# chordoma

**norns script** — Jazz/funk/electronic grid chord sequencer with arpeggiators and 5 themes

Turns the monome Grid into a 120-chord instrument. Each load generates a musically curated chord layout based on the selected theme. The center row follows a hand-crafted progression; outer rows get progressively more complex and adventurous chords.

## Grid Layout

```
Cols 1-15  : Chord pads (8 rows x 15 cols = 120 unique chords)
Col 16     : Arpeggiator toggles (one per row)
```

**Row brightness = complexity:**
- Row 4 (center) — brightest, follows theme progression (simple–complex left→right)
- Rows 3 & 5 — extended chords (9ths, 11ths)
- Rows 2 & 6 — adventurous (dom7#9, maj7#11, etc.)
- Rows 1 & 8 — wildcard tier

## Controls

| Control | Action |
|---------|--------|
| ENC1 | Page select (Play / Tempo / Theme) |
| ENC2 | BPM (Tempo page) or Theme select (Theme page) |
| ENC3 | Arp rate (Tempo page) |
| K2 | Panic — all notes off |
| K3 | Regenerate chord layout |

## Norns Screen (3 pages)
1. **Play** — shows chord name, theme, arp status per row
2. **Tempo** — BPM and arp rate
3. **Theme** — select vibe/scale preset, K3 to regenerate

## 5 Themes
- **Jazz Nights** — ii-V-I, altered dominants, maj7#11
- **Funk Machine** — dom7, dom9, dom7#9 groove
- **Electronic** — minor modal, sus chords
- **Neo Soul** — maj9, min9, dom13 lush extensions
- **Modal Drift** — sus chords, Dorian/Mixolydian

## Installation
```
~/dust/code/chordoma/chordoma.lua
```
Load from the norns SELECT menu. Connect a monome Grid and a MIDI output device.

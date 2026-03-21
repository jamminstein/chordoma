-- chordoma.lua
-- Jazz/funk/electronic chord grid for monome norns + grid (v1)
-- 120 chord pads with arpeggiator and internal synth

engine.name = "MollyThePoly"

local g = grid.connect()
local midi_out = midi.connect(1)

-- helpers
local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function midi_to_hz(note)
  return 440 * 2^((note - 69) / 12)
end

-- chord definitions
local CHORDS = {
  maj = {0,4,7},
  min = {0,3,7},
  maj7 = {0,4,7,11},
  min7 = {0,3,7,10},
  dom7 = {0,4,7,10},
  min7b5 = {0,3,6,10},
  dim = {0,3,6,9},
  aug = {0,4,8},
  sus2 = {0,2,7},
  sus4 = {0,5,7},
  maj9 = {0,4,7,14},
  min9 = {0,3,7,14},
  maj13 = {0,4,7,11,21},
  min13 = {0,3,7,10,21},
}

local CHORD_TYPES = {
  "maj", "min", "maj7", "min7", "dom7",
  "min7b5", "dim", "aug", "sus2", "sus4",
  "maj9", "min9", "maj13", "min13"
}

local THEMES = {
  jazz = {root=0, progression={0,5,10,3}},
  funk = {root=0, progression={0,7,3,10}},
  electronic = {root=0, progression={0,12,5,7}},
  neosoul = {root=0, progression={0,4,9,2}},
  modal = {root=0, progression={0,2,7,5}},
}

local state = {
  root_notes = {},
  held_chords = {},
  arps = {},
  tempo = 120,
  theme = "jazz",
  page = 1,
  arp_rate = 4,
  arp_dir = 1,
}

-- initialize chord grid (8 rows x 15 cols)
for row = 1, 8 do
  state.root_notes[row] = {}
  for col = 1, 15 do
    state.root_notes[row][col] = 36 + (row * 4) + (col % 12)
  end
end

local function engine_note_on(note, vel)
  local freq = midi_to_hz(note)
  engine.noteOn(note, freq, vel / 127)
end

local function engine_note_off(note)
  engine.noteOff(note)
end

local function note_on(note, vel)
  if midi_out then midi_out:note_on(note, vel, 1) end
  engine_note_on(note, vel)
end

local function note_off(note)
  if midi_out then midi_out:note_off(note, 0, 1) end
  engine_note_off(note)
end

local function build_chord(root, chord_type, octave)
  local intervals = CHORDS[chord_type] or CHORDS.maj
  local notes = {}
  for _, interval in ipairs(intervals) do
    table.insert(notes, root + octave * 12 + interval)
  end
  return notes
end

local function play_chord(root, chord_type, vel)
  local notes = build_chord(root, chord_type, 4)
  for _, note in ipairs(notes) do
    note_on(note, vel)
  end
  return notes
end

local function release_chord(notes)
  for _, note in ipairs(notes) do
    note_off(note)
  end
end

function redraw()
  screen.clear()
  screen.aa(1)
  
  if state.page == 1 then
    -- Play page
    screen.level(15)
    screen.font_face(7)
    screen.font_size(8)
    screen.move(2, 10)
    screen.text("CHORDOMA")
    
    screen.level(8)
    screen.font_size(7)
    screen.move(2, 20)
    screen.text("THEME: " .. state.theme:upper())
    
    screen.move(2, 30)
    screen.text("BPM: " .. state.tempo)
    
    screen.move(2, 40)
    screen.text("ARP RATE: " .. state.arp_rate)
    
  elseif state.page == 2 then
    -- Tempo page
    screen.level(15)
    screen.font_size(8)
    screen.move(64, 30)
    screen.text_align_center()
    screen.text("TEMPO")
    
    screen.level(12)
    screen.font_size(16)
    screen.move(64, 50)
    screen.text(state.tempo)
    screen.text_align_left()
    
  elseif state.page == 3 then
    -- Theme page
    screen.level(15)
    screen.font_size(8)
    screen.move(64, 30)
    screen.text_align_center()
    screen.text("THEME")
    
    screen.level(12)
    screen.font_size(12)
    screen.move(64, 50)
    screen.text(state.theme:upper())
    screen.text_align_left()
  end
  
  screen.update()
end

function grid_redraw()
  if not g then return end
  g:all(0)
  
  -- Draw chord pads (cols 1-15)
  for row = 1, 8 do
    for col = 1, 15 do
      local brightness = 4
      if state.held_chords[row] and state.held_chords[row][col] then
        brightness = 15
      end
      g:led(col, row, brightness)
    end
    -- Arpeggiator toggle (col 16)
    local arp_on = state.arps[row] and 10 or 3
    g:led(16, row, arp_on)
  end
  
  g:refresh()
end

local function grid_key(x, y, z)
  if z == 0 then return end
  
  if x <= 15 then
    -- Chord pad
    local root = state.root_notes[y][x]
    if not state.held_chords[y] then state.held_chords[y] = {} end
    
    if z == 1 then
      local chord_type = CHORD_TYPES[(y - 1) % #CHORD_TYPES + 1]
      local notes = play_chord(root, chord_type, 100)
      state.held_chords[y][x] = notes
    else
      if state.held_chords[y][x] then
        release_chord(state.held_chords[y][x])
        state.held_chords[y][x] = nil
      end
    end
  elseif x == 16 then
    -- Arpeggiator toggle
    state.arps[y] = not state.arps[y]
  end
  
  redraw()
  grid_redraw()
end

if g then g.key = grid_key end

function enc(n, d)
  if n == 1 then
    state.page = ((state.page - 1 + d) % 3) + 1
  elseif n == 2 then
    if state.page == 2 then
      state.tempo = clamp(state.tempo + d, 40, 240)
    else
      local themes = {"jazz", "funk", "electronic", "neosoul", "modal"}
      local idx = 1
      for i, t in ipairs(themes) do
        if t == state.theme then idx = i break end
      end
      idx = ((idx - 1 + d) % #themes) + 1
      state.theme = themes[idx]
    end
  elseif n == 3 then
    if state.page == 2 then
      state.arp_rate = clamp(state.arp_rate + d, 1, 7)
    end
  end
  redraw()
  grid_redraw()
end

function key(n, z)
  if n == 2 and z == 1 then
    -- Panic: all notes off
    for row = 1, 8 do
      if state.held_chords[row] then
        for col = 1, 15 do
          if state.held_chords[row][col] then
            release_chord(state.held_chords[row][col])
            state.held_chords[row][col] = nil
          end
        end
      end
    end
  elseif n == 3 and z == 1 then
    -- Randomize layout
    for row = 1, 8 do
      for col = 1, 15 do
        state.root_notes[row][col] = 36 + math.random(0, 24)
      end
    end
  end
  redraw()
  grid_redraw()
end

function init()
  redraw()
  grid_redraw()
end

function cleanup()
  engine.noteOffAll()
  if midi_out then midi_out:all_notes_off(1) end
end
-- chordoma.lua
-- Professional Jazz/Funk/Electronic Chord Grid Sequencer for Monome Norns
-- MollyThePoly synth engine + 5 voice presets + arpeggiator + MIDI/OP-XY output
-- Grid: 8 rows x 15 cols for chords, col 16 toggles arp per row

engine.name = "MollyThePoly"

local g = grid.connect()
local midi_out = nil
local opxy_out = nil

-- ============================================================================
-- VOICE PRESETS (5 jazz/funk/electronic themes)
-- ============================================================================

local VOICE_PRESETS = {
  Rhodes = {
    description = "Warm bell-like Rhodes, medium attack, soft filter",
    osc_wave = 1,
    pw = 0.5,
    freq_mod_lfo = 0.0,
    freq_mod_env = 0.0,
    glide = 0.05,
    amp = 0.85,
    amp_env_attack = 0.01,
    amp_env_decay = 0.8,
    amp_env_sustain = 0.4,
    amp_env_release = 1.2,
    filter_type = 1, -- lpf
    filter_freq = 2500,
    filter_resonance = 0.2,
    filter_env_attack = 0.01,
    filter_env_decay = 0.5,
    filter_env_sustain = 0.0,
    filter_env_release = 0.2,
    filter_env_amount = 1500,
    lfo_rate = 6.0,
    lfo_shape = 1,
  },
  Pad = {
    description = "Lush pad, slow attack, long release, low cutoff",
    osc_wave = 1,
    pw = 0.5,
    freq_mod_lfo = 0.1,
    freq_mod_env = 0.0,
    glide = 0.2,
    amp = 0.7,
    amp_env_attack = 1.5,
    amp_env_decay = 2.0,
    amp_env_sustain = 0.7,
    amp_env_release = 3.0,
    filter_type = 1,
    filter_freq = 1200,
    filter_resonance = 0.3,
    filter_env_attack = 0.5,
    filter_env_decay = 1.0,
    filter_env_sustain = 0.5,
    filter_env_release = 2.0,
    filter_env_amount = 2000,
    lfo_rate = 0.5,
    lfo_shape = 1,
  },
  FunkClav = {
    description = "Punchy funk clavinet, short attack/release, bright",
    osc_wave = 2,
    pw = 0.5,
    freq_mod_lfo = 0.0,
    freq_mod_env = 0.0,
    glide = 0.0,
    amp = 1.0,
    amp_env_attack = 0.005,
    amp_env_decay = 0.15,
    amp_env_sustain = 0.0,
    amp_env_release = 0.1,
    filter_type = 1,
    filter_freq = 4000,
    filter_resonance = 0.4,
    filter_env_attack = 0.002,
    filter_env_decay = 0.2,
    filter_env_sustain = 0.0,
    filter_env_release = 0.1,
    filter_env_amount = 3000,
    lfo_rate = 4.0,
    lfo_shape = 2,
  },
  Strings = {
    description = "Smooth strings, slow attack, long sustain, subtle vibrato",
    osc_wave = 1,
    pw = 0.5,
    freq_mod_lfo = 0.05,
    freq_mod_env = 0.0,
    glide = 0.15,
    amp = 0.75,
    amp_env_attack = 1.0,
    amp_env_decay = 0.5,
    amp_env_sustain = 0.8,
    amp_env_release = 1.5,
    filter_type = 1,
    filter_freq = 3500,
    filter_resonance = 0.15,
    filter_env_attack = 0.2,
    filter_env_decay = 0.8,
    filter_env_sustain = 0.6,
    filter_env_release = 1.0,
    filter_env_amount = 1200,
    lfo_rate = 3.0,
    lfo_shape = 1,
  },
  SynthLead = {
    description = "Bright synth lead, moderate attack, responsive filter",
    osc_wave = 2,
    pw = 0.3,
    freq_mod_lfo = 0.08,
    freq_mod_env = 0.05,
    glide = 0.08,
    amp = 0.9,
    amp_env_attack = 0.05,
    amp_env_decay = 0.3,
    amp_env_sustain = 0.6,
    amp_env_release = 0.5,
    filter_type = 1,
    filter_freq = 3200,
    filter_resonance = 0.5,
    filter_env_attack = 0.01,
    filter_env_decay = 0.4,
    filter_env_sustain = 0.3,
    filter_env_release = 0.3,
    filter_env_amount = 2500,
    lfo_rate = 5.5,
    lfo_shape = 2,
  },
}

local PRESET_NAMES = {"Rhodes", "Pad", "FunkClav", "Strings", "SynthLead"}

-- ============================================================================
-- CHORD DEFINITIONS
-- ============================================================================

local CHORDS = {
  maj = {0, 4, 7},
  min = {0, 3, 7},
  maj7 = {0, 4, 7, 11},
  min7 = {0, 3, 7, 10},
  dom7 = {0, 4, 7, 10},
  min7b5 = {0, 3, 6, 10},
  dim = {0, 3, 6, 9},
  aug = {0, 4, 8},
  sus2 = {0, 2, 7},
  sus4 = {0, 5, 7},
  maj9 = {0, 4, 7, 14},
  min9 = {0, 3, 7, 14},
  maj13 = {0, 4, 7, 11, 21},
  min13 = {0, 3, 7, 10, 21},
}

local CHORD_TYPES = {
  "maj", "min", "maj7", "min7", "dom7",
  "min7b5", "dim", "aug", "sus2", "sus4",
  "maj9", "min9", "maj13", "min13"
}

local ARP_DIVISIONS = {
  ["1/4"] = 0.25,
  ["1/8"] = 0.125,
  ["1/8T"] = 0.0833,
  ["1/16"] = 0.0625,
  ["1/16T"] = 0.0417,
  ["1/32"] = 0.03125,
}

local ARP_DIVISION_NAMES = {"1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32"}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  root_note = 60,              -- C4
  chord_type_idx = 1,          -- index into CHORD_TYPES
  preset_idx = 1,              -- index into PRESET_NAMES
  octave = 4,
  
  -- Grid note tracking
  held_chords = {},             -- held_chords[row][col] = {note list}
  
  -- Arpeggiator state per row
  arp_active = {},              -- arp_active[row] = true/false
  arp_clocks = {},              -- arp_clocks[row] = clock handle
  arp_notes = {},               -- arp_notes[row] = {note list}
  arp_direction = {},           -- arp_direction[row] = 1 or -1
  arp_index = {},               -- arp_index[row] = current index
  
  -- Screen
  selected_row = 1,             -- for grid visualization
}

-- Initialize grid layout: root notes per position
for row = 1, 8 do
  state.held_chords[row] = {}
  state.arp_active[row] = false
  state.arp_direction[row] = 1
  state.arp_index[row] = 1
end

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function midi_to_hz(note)
  return 440 * 2 ^ ((note - 69) / 12)
end

local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function apply_preset(name)
  if not VOICE_PRESETS[name] then return end
  local preset = VOICE_PRESETS[name]
  
  for key, val in pairs(preset) do
    if key ~= "description" then
      pcall(params.set, params, key, val)
    end
  end
end

-- ============================================================================
-- NOTE TRIGGERING (engine + MIDI + OP-XY)
-- ============================================================================

local function trigger_note(note, vel)
  local freq = midi_to_hz(note)
  local vel_normalized = vel / 127
  
  -- Engine (MollyThePoly)
  engine.noteOn(note, freq, vel_normalized)
  
  -- MIDI out
  if midi_out and params:get("midi_enabled") == 2 then
    midi_out:note_on(note, vel, params:get("midi_channel"))
  end
  
  -- OP-XY
  if opxy_out and params:get("opxy_enabled") == 2 then
    opxy_out:note_on(note, vel, params:get("opxy_channel"))
  end
end

local function release_note(note)
  -- Engine
  engine.noteOff(note)
  
  -- MIDI out
  if midi_out and params:get("midi_enabled") == 2 then
    midi_out:note_off(note, 0, params:get("midi_channel"))
  end
  
  -- OP-XY
  if opxy_out and params:get("opxy_enabled") == 2 then
    opxy_out:note_off(note, 0, params:get("opxy_channel"))
  end
end

local function trigger_chord(notes, vel)
  for _, note in ipairs(notes) do
    trigger_note(note, vel)
  end
end

local function release_chord(notes)
  for _, note in ipairs(notes) do
    release_note(note)
  end
end

local function all_notes_off()
  engine.noteOffAll()
  
  if midi_out and params:get("midi_enabled") == 2 then
    for ch = 1, 16 do
      midi_out:cc(123, 0, ch)
    end
  end
  
  if opxy_out and params:get("opxy_enabled") == 2 then
    for ch = 1, 8 do
      opxy_out:cc(123, 0, ch)
    end
  end
end

-- ============================================================================
-- CHORD BUILDER
-- ============================================================================

local function build_chord(root, chord_type_name, octave)
  local intervals = CHORDS[chord_type_name] or CHORDS.maj
  local notes = {}
  for _, interval in ipairs(intervals) do
    table.insert(notes, root + octave * 12 + interval)
  end
  return notes
end

-- ============================================================================
-- ARPEGGIATOR
-- ============================================================================

local function advance_arp_index(idx, max, direction, mode)
  if mode == 1 then -- up
    idx = idx + 1
    if idx > max then idx = 1 end
  elseif mode == 2 then -- down
    idx = idx - 1
    if idx < 1 then idx = max end
  elseif mode == 3 then -- up-down
    idx = idx + direction
    if idx > max then
      idx = max - 1
      direction = -1
    elseif idx < 1 then
      idx = 2
      direction = 1
    end
  elseif mode == 4 then -- random
    idx = math.random(1, max)
  end
  return idx, direction
end

local function start_arp(row, notes)
  if params:get("arp_mode") == 1 then return end -- arp off
  
  if state.arp_clocks[row] then
    clock.cancel(state.arp_clocks[row])
  end
  
  state.arp_notes[row] = notes
  state.arp_active[row] = true
  state.arp_direction[row] = 1
  state.arp_index[row] = 1
  
  state.arp_clocks[row] = clock.run(function()
    while state.arp_active[row] and #state.arp_notes[row] > 0 do
      local div_name = ARP_DIVISION_NAMES[params:get("arp_division")]
      local div = ARP_DIVISIONS[div_name] or 0.125
      local beat_len = div * 4 / (params:get("tempo") / 120) -- normalize to BPM
      
      clock.sleep(beat_len)
      
      -- Trigger current note
      if state.arp_notes[row] and #state.arp_notes[row] > 0 then
        local note = state.arp_notes[row][state.arp_index[row]]
        local vel = params:get("arp_velocity")
        trigger_note(note, vel)
        
        -- Schedule note off
        clock.run(function()
          local gate = params:get("arp_gate")
          clock.sleep(beat_len * gate)
          release_note(note)
        end)
        
        -- Advance index
        local mode = params:get("arp_mode") - 1  -- map from 2-5 to 1-4
        state.arp_index[row], state.arp_direction[row] = 
          advance_arp_index(state.arp_index[row], #state.arp_notes[row], 
                           state.arp_direction[row], mode)
      end
    end
  end)
end

local function stop_arp(row)
  state.arp_active[row] = false
  if state.arp_clocks[row] then
    clock.cancel(state.arp_clocks[row])
    state.arp_clocks[row] = nil
  end
  state.arp_notes[row] = {}
end

-- ============================================================================
-- GRID INTERACTION
-- ============================================================================

local function grid_key(x, y, z)
  if z == 0 then
    -- Key release
    if x <= 15 and state.held_chords[y] and state.held_chords[y][x] then
      release_chord(state.held_chords[y][x])
      state.held_chords[y][x] = nil
      
      -- If arp not active, stop arp on release
      if not state.arp_active[y] then
        stop_arp(y)
      end
    end
  else
    -- Key press
    if x <= 15 then
      -- Chord pad: build chord with current root + offset based on column
      local root_offset = (x - 1) % 12  -- 0-11 semitones
      local chord_root = state.root_note + root_offset
      local chord_type = CHORD_TYPES[state.chord_type_idx]
      local notes = build_chord(chord_root, chord_type, state.octave)
      
      local vel = params:get("midi_velocity")
      trigger_chord(notes, vel)
      
      state.held_chords[y][x] = notes
      
      -- Start arp if enabled
      if params:get("arp_mode") > 1 then
        start_arp(y, notes)
      end
      
      state.selected_row = y
      
    elseif x == 16 then
      -- Arp toggle for this row
      if state.arp_active[y] then
        stop_arp(y)
      else
        if state.held_chords[y] then
          for col = 1, 15 do
            if state.held_chords[y][col] then
              start_arp(y, state.held_chords[y][col])
              break
            end
          end
        end
      end
    end
  end
  
  redraw()
  grid_redraw()
end

if g then
  g.key = grid_key
end

local function grid_redraw()
  if not g then return end
  g:all(0)
  
  -- Chord pads (cols 1-15)
  for row = 1, 8 do
    for col = 1, 15 do
      local brightness = 4
      if state.held_chords[row][col] then
        brightness = state.arp_active[row] and 12 or 15
      end
      g:led(col, row, brightness)
    end
    
    -- Arp toggle column (col 16)
    local arp_brightness = state.arp_active[row] and 10 or 3
    g:led(16, row, arp_brightness)
  end
  
  g:refresh()
end

-- ============================================================================
-- SCREEN REDRAW
-- ============================================================================

function redraw()
  screen.clear()
  screen.aa(1)
  
  -- Header
  screen.level(15)
  screen.font_face(7)
  screen.font_size(8)
  screen.move(2, 10)
  screen.text("CHORDOMA")
  
  -- Preset name
  screen.level(8)
  screen.font_size(7)
  screen.move(2, 20)
  screen.text("Preset: " .. PRESET_NAMES[state.preset_idx])
  
  -- Root note + chord type
  screen.move(2, 30)
  local root_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  local root_name = root_names[(state.root_note % 12) + 1]
  local octave_num = math.floor(state.root_note / 12) - 1
  screen.text(root_name .. octave_num .. " " .. CHORD_TYPES[state.chord_type_idx]:upper())
  
  -- Arp status
  screen.move(2, 40)
  if params:get("arp_mode") > 1 then
    local arp_modes = {"OFF", "UP", "DOWN", "UP-DN", "RNDM"}
    local arp_mode_name = arp_modes[params:get("arp_mode")]
    local div_name = ARP_DIVISION_NAMES[params:get("arp_division")]
    screen.text("Arp: " .. arp_mode_name .. " " .. div_name)
  else
    screen.text("Arp: OFF")
  end
  
  -- MIDI/OP-XY status
  screen.level(5)
  screen.move(2, 50)
  local status = ""
  if params:get("midi_enabled") == 2 then
    status = status .. "MIDI "
  end
  if params:get("opxy_enabled") == 2 then
    status = status .. "OP-XY"
  end
  if status == "" then
    status = "(Local only)"
  end
  screen.text(status)
  
  -- Tempo
  screen.level(8)
  screen.move(100, 20)
  screen.text(params:get("tempo") .. " BPM")
  
  screen.update()
end

-- ============================================================================
-- ENCODER INTERACTION
-- ============================================================================

function enc(n, d)
  if n == 1 then
    -- Cycle presets
    state.preset_idx = ((state.preset_idx - 1 + d) % #PRESET_NAMES) + 1
    apply_preset(PRESET_NAMES[state.preset_idx])
  elseif n == 2 then
    -- Root note
    state.root_note = clamp(state.root_note + d, 36, 84)  -- C2 to C7
  elseif n == 3 then
    -- Chord type
    state.chord_type_idx = ((state.chord_type_idx - 1 + d) % #CHORD_TYPES) + 1
  end
  
  redraw()
  grid_redraw()
end

-- ============================================================================
-- KEY INTERACTION
-- ============================================================================

function key(n, z)
  if n == 2 and z == 1 then
    -- K2: Panic (all notes off)
    all_notes_off()
    for row = 1, 8 do
      state.held_chords[row] = {}
      stop_arp(row)
    end
  elseif n == 3 and z == 1 then
    -- K3: Cycle arp mode
    local mode = params:get("arp_mode")
    mode = (mode % 5) + 1
    params:set("arp_mode", mode)
  end
  
  redraw()
  grid_redraw()
end

-- ============================================================================
-- PARAMETER DEFINITIONS
-- ============================================================================

function init()
  -- Load and register MollyThePoly engine params
  local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
  MollyThePoly.add_params()
  
  -- MIDI Output
  params:add_separator("MIDI OUTPUT")
  params:add_option("midi_enabled", "MIDI out", {"off", "on"}, 1)
  params:add_number("midi_device", "MIDI device", 1, 4, 1)
  params:add_number("midi_channel", "MIDI channel", 1, 16, 1)
  params:add_number("midi_velocity", "velocity", 1, 127, 100)
  
  params:set_action("midi_device", function(val)
    midi_out = midi.connect(val)
  end)
  
  params:set_action("midi_enabled", function(val)
    if val == 1 then
      midi_out = nil
    end
  end)
  
  -- OP-XY Output
  params:add_separator("OP-XY OUTPUT")
  params:add_option("opxy_enabled", "OP-XY out", {"off", "on"}, 1)
  params:add_number("opxy_device", "OP-XY MIDI device", 1, 4, 1)
  params:add_number("opxy_channel", "OP-XY channel", 1, 8, 1)
  
  params:set_action("opxy_device", function(val)
    opxy_out = midi.connect(val)
  end)
  
  params:set_action("opxy_enabled", function(val)
    if val == 1 then
      opxy_out = nil
    end
  end)
  
  -- Arpeggiator
  params:add_separator("ARPEGGIATOR")
  params:add_option("arp_mode", "arp mode", {"off", "up", "down", "up-down", "random"}, 1)
  params:add_option("arp_division", "arp division", ARP_DIVISION_NAMES, 2)
  params:add_number("arp_velocity", "arp velocity", 1, 127, 100)
  params:add_control("arp_gate", "arp gate", controlspec.new(0.1, 1.0, "lin", 0.01, 0.5))
  
  -- Tempo
  params:add_separator("TIMING")
  params:add_number("tempo", "BPM", 40, 240, 120)
  
  redraw()
  grid_redraw()
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

function cleanup()
  -- Stop all arps
  for row = 1, 8 do
    stop_arp(row)
  end
  
  -- All notes off
  all_notes_off()
end

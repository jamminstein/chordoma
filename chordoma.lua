-- chordoma.lua
-- a jazz/funk/electronic chord grid for norns + monome grid
-- 
-- GRID LAYOUT:
--   cols 1-15 : chord pads (8 rows x 15 cols = 120 chords)
--   col  16   : arpeggiator toggles (row 1-8)
--
-- NORNS SCREEN:
--   page 1 (E1) : play  -- shows chord name, root, arp status
--   page 2       : tempo -- BPM + arp rate
--   page 3       : theme -- vibe/scale preset selector
--
-- ENCODERS (global):
--   E1 : page select
--   E2 : BPM (page 2) / theme select (page 3)
--   E3 : arp rate (page 2) / chord density (page 3)
--
-- KEYS:
--   K2 : panic / all notes off
--   K3 : randomize chord layout

engine.name = "PolyPerc"

local MusicUtil = require "musicutil"
local UI = require "ui"

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local GRID_W  = 16
local GRID_H  = 8
local PAD_COLS = 15   -- cols 1-15 are chord pads
local ARP_COL  = 16   -- col 16 is arp toggles

--------------------------------------------------------------------------------
-- THEMES  (root note pool + chord type pool + bass movement)
--------------------------------------------------------------------------------
local THEMES = {
  {
    name  = "Jazz Nights",
    roots = {0,2,4,5,7,9,11},           -- C major scale roots
    center_progression = {               -- left->right center row (row 4)
      -- {root_offset, chord_type}
      {0,"maj7"},{5,"maj7"},{9,"min7"},{2,"dom7"},
      {7,"min7"},{0,"dom7b9"},{5,"maj9"},{9,"min9"},
      {2,"dom13"},{7,"maj7#11"},{0,"min11"},{5,"dom7#9"},
      {9,"maj7"},{2,"min7b5"},{7,"dim7"},
    },
  },
  {
    name  = "Funk Machine",
    roots = {0,3,5,7,10},
    center_progression = {
      {0,"dom7"},{5,"dom7"},{0,"dom9"},{5,"dom7#9"},
      {10,"dom7"},{3,"dom7"},{0,"min7"},{5,"dom13"},
      {10,"dom9"},{3,"min7"},{0,"dom7"},{7,"dom7"},
      {0,"dom7#9"},{5,"dom9"},{10,"dom7"},
    },
  },
  {
    name  = "Electronic",
    roots = {0,2,3,5,7,8,10},
    center_progression = {
      {0,"min7"},{3,"maj7"},{7,"min9"},{10,"maj7"},
      {2,"min7"},{5,"dom7"},{8,"maj7#11"},{0,"min11"},
      {3,"maj9"},{7,"min7"},{10,"dom9"},{2,"maj7"},
      {5,"min9"},{8,"dom7"},{0,"min7"},
    },
  },
  {
    name  = "Neo Soul",
    roots = {0,2,4,7,9},
    center_progression = {
      {0,"maj9"},{9,"min9"},{5,"maj7"},{2,"min11"},
      {7,"dom7"},{0,"maj7#11"},{9,"min7"},{5,"dom9"},
      {2,"maj9"},{7,"min9"},{0,"maj7"},{9,"dom13"},
      {5,"maj9"},{2,"min7"},{7,"maj7"},
    },
  },
  {
    name  = "Modal Drift",
    roots = {0,2,3,5,7,10},
    center_progression = {
      {0,"min7"},{5,"sus2"},{10,"maj7"},{3,"min9"},
      {7,"sus4"},{0,"min11"},{5,"maj7#11"},{10,"min7"},
      {3,"dom7sus4"},{7,"min9"},{0,"sus2"},{5,"min7"},
      {10,"maj9"},{3,"min7"},{7,"dom7sus4"},
    },
  },
}

--------------------------------------------------------------------------------
-- CHORD TYPE DEFINITIONS  {semitone intervals from root}
--------------------------------------------------------------------------------
local CHORD_TYPES = {
  -- triads
  maj       = {0,4,7},
  min       = {0,3,7},
  dim       = {0,3,6},
  aug       = {0,4,8},
  sus2      = {0,2,7},
  sus4      = {0,5,7},
  -- 7ths
  maj7      = {0,4,7,11},
  min7      = {0,3,7,10},
  dom7      = {0,4,7,10},
  dim7      = {0,3,6,9},
  min7b5    = {0,3,6,10},
  dom7b9    = {0,4,7,10,13},
  dom7s9    = {0,4,7,10,15},
  ["dom7#9"]= {0,4,7,10,15},
  min_maj7  = {0,3,7,11},
  -- 9ths
  maj9      = {0,4,7,11,14},
  min9      = {0,3,7,10,14},
  dom9      = {0,4,7,10,14},
  -- 11ths / 13ths
  min11     = {0,3,7,10,14,17},
  dom13     = {0,4,7,10,14,21},
  ["maj7#11"]= {0,4,7,11,14,18},
  dom7sus4  = {0,5,7,10},
}

local CHORD_TYPE_KEYS = {}
for k,_ in pairs(CHORD_TYPES) do table.insert(CHORD_TYPE_KEYS, k) end

-- complexity tiers (used to vary chords by row distance from center)
local TIERS = {
  {keys={"maj","min","sus2","sus4","dim"},                           label="simple"},
  {keys={"maj7","min7","dom7","dim7"},                               label="sevenths"},
  {keys={"maj9","min9","dom9","dom7b9","min7b5"},                    label="extended"},
  {keys={"min11","dom13","maj7#11","dom7#9","min_maj7","dom7sus4"},   label="complex"},
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local g         -- grid
local grid_dirty = true
local screen_dirty = true

local current_theme = 1
local bpm     = 120
local arp_rate_idx = 3   -- index into arp_rates table

local arp_rates = {1/8, 1/4, 1/3, 1/2, 2/3, 3/4, 1}  -- as fraction of beat
local arp_rate_names = {"1/8","1/4","1/3","1/2","2/3","3/4","1 beat"}

-- grid data: chord_grid[row][col] = {root, type_key, notes[]}
local chord_grid = {}
-- arp toggles: arp_on[row] = bool (col 16)
local arp_on = {}
-- currently held pads: held[row][col] = bool
local held = {}
-- active notes being played (for note-off)
local active_voices = {}  -- list of {notes[], clock_id}

-- NEW: voicing mode, chord velocity, sustain mode, tied arp
local voicing_mode = "close"     -- "close", "open", "drop2", "drop3", "shell"
local chord_velocity = 90         -- MIDI velocity (20-127)
local sustain_mode = false        -- if true, hold prev chord notes until new chord
local tied_arp = false            -- if true, arp continues across chord boundaries

local current_page = 1  -- 1=play, 2=tempo, 3=theme
local last_chord_name = ""
local last_chord_root = ""

-- arp state
local arp_clocks = {}     -- arp_clocks[row] = clock id
local sustain_notes = {}  -- sustain_notes[row] = {notes being sustained}
local arp_indices = {}    -- arp_indices[row] = current index in arp pattern (for tied_arp)

--------------------------------------------------------------------------------
-- MIDI
--------------------------------------------------------------------------------
local midi_out = midi.connect(1)

local function note_on(note, vel)
  midi_out:note_on(note, vel or 100, 1)
end

local function note_off(note)
  midi_out:note_off(note, 0, 1)
end

local function all_notes_off()
  for n = 0, 127 do midi_out:note_off(n, 0, 1) end
  active_voices = {}
end

--------------------------------------------------------------------------------
-- CHORD LAYOUT GENERATION
--------------------------------------------------------------------------------
local function root_name(semitone)
  local names = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
  return names[(semitone % 12) + 1]
end

local function apply_voicing(notes, voicing)
  -- Apply voicing variations to rearrange chord notes
  if not voicing or voicing == "close" then
    return notes  -- default close voicing
  end

  local result = {}
  for i, n in ipairs(notes) do table.insert(result, n) end

  if voicing == "open" then
    -- Open voicing: spread notes wider across octaves
    if #result >= 3 then
      result[2] = result[2] + 12  -- second note up an octave
    end
  elseif voicing == "drop2" then
    -- Drop-2: move second-from-top note down an octave
    if #result >= 2 then
      result[#result - 1] = result[#result - 1] - 12
    end
  elseif voicing == "drop3" then
    -- Drop-3: move third-from-top note down an octave
    if #result >= 3 then
      result[#result - 2] = result[#result - 2] - 12
    end
  elseif voicing == "shell" then
    -- Shell voicing: keep only root, 3rd, 7th (if they exist)
    local shell = {}
    if #result >= 1 then table.insert(shell, result[1]) end        -- root
    if #result >= 3 then table.insert(shell, result[3]) end        -- 3rd
    if #result >= 4 then table.insert(shell, result[4]) end        -- 7th
    result = shell
  end

  return result
end

local function build_chord(root_midi, type_key, voicing_type)
  local intervals = CHORD_TYPES[type_key] or {0,4,7}
  local notes = {}
  for _, iv in ipairs(intervals) do
    table.insert(notes, root_midi + iv)
  end
  return apply_voicing(notes, voicing_type or voicing_mode)
end

local function tier_for_row(row)
  -- row 4 (center-ish for 8-row grid) = tier 2
  -- distance from row 4 determines complexity
  local center = 4
  local dist = math.abs(row - center)
  if dist == 0 then return 2
  elseif dist == 1 then return 3
  elseif dist == 2 then return 4
  else return math.random(1, 4)
  end
end

local function random_chord_for_tier(tier_idx, theme)
  local t = THEMES[theme]
  local tier = TIERS[math.min(tier_idx, #TIERS)]
  local root_offset = t.roots[math.random(#t.roots)]
  local type_key = tier.keys[math.random(#tier.keys)]
  local root_midi = 48 + root_offset  -- C3 base
  return {
    root = root_midi,
    type_key = type_key,
    notes = build_chord(root_midi, type_key),
    name = root_name(root_offset) .. type_key,
  }
end

local function generate_grid()
  local t = THEMES[current_theme]
  chord_grid = {}
  for row = 1, GRID_H do
    chord_grid[row] = {}
    local tier = tier_for_row(row)
    for col = 1, PAD_COLS do
      if row == 4 and col <= #t.center_progression then
        -- center row: use the theme's musical progression
        local prog = t.center_progression[col]
        local root_midi = 48 + prog[1]
        local type_key  = prog[2]
        chord_grid[row][col] = {
          root     = root_midi,
          type_key = type_key,
          notes    = build_chord(root_midi, type_key),
          name     = root_name(prog[1]) .. type_key,
        }
      else
        chord_grid[row][col] = random_chord_for_tier(tier, current_theme)
      end
    end
  end
end

--------------------------------------------------------------------------------
-- BRIGHTNESS helpers
--------------------------------------------------------------------------------
-- base brightness per row (center row brightest, fades outward)
local function row_brightness(row)
  local center = 4
  local dist = math.abs(row - center)
  local b = {15, 12, 10, 7, 5}  -- index = dist+1
  return b[math.min(dist + 1, #b)]
end

local function update_grid_leds()
  if not g then return end
  g:all(0)
  for row = 1, GRID_H do
    -- chord pads
    for col = 1, PAD_COLS do
      local bright = row_brightness(row)
      if held[row] and held[row][col] then bright = 15 end
      g:led(col, row, bright)
    end
    -- arp column
    local ab = arp_on[row] and 15 or 3
    g:led(ARP_COL, row, ab)
  end
  g:refresh()
end

--------------------------------------------------------------------------------
-- ARP
--------------------------------------------------------------------------------
local function stop_arp(row)
  if arp_clocks[row] then
    clock.cancel(arp_clocks[row])
    arp_clocks[row] = nil
  end
end

local function start_arp(row, chord)
  stop_arp(row)
  local notes = chord.notes

  -- For tied_arp, continue from last index; otherwise start from 1
  if not arp_indices[row] then arp_indices[row] = 1 end
  if not tied_arp then arp_indices[row] = 1 end

  arp_clocks[row] = clock.run(function()
    while true do
      local note_idx = arp_indices[row]
      local note = notes[note_idx]
      local vel = chord_velocity + math.random(-8, 8)
      vel = util.clamp(vel, 0, 127)
      note_on(note, vel)
      local rate = arp_rates[arp_rate_idx] * (60 / bpm)
      clock.sleep(rate * 0.8)
      note_off(note)
      clock.sleep(rate * 0.2)
      arp_indices[row] = (note_idx % #notes) + 1
    end
  end)
end

local function restart_active_arps()
  for row = 1, GRID_H do
    if arp_on[row] and arp_clocks[row] then
      -- find last held chord in this row
      for col = PAD_COLS, 1, -1 do
        if held[row] and held[row][col] then
          start_arp(row, chord_grid[row][col])
          break
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- PLAY / RELEASE chord
--------------------------------------------------------------------------------
local function play_chord(row, col)
  local chord = chord_grid[row][col]
  if not chord then return end
  last_chord_name = chord.name
  last_chord_root = root_name(chord.root - 48)
  screen_dirty = true

  -- If sustain_mode is on, release previous chord notes first
  if sustain_mode and sustain_notes[row] then
    for _, n in ipairs(sustain_notes[row]) do note_off(n) end
    sustain_notes[row] = nil
  end

  -- Play chord with velocity variation
  for _, n in ipairs(chord.notes) do
    local vel = chord_velocity + math.random(-8, 8)
    vel = util.clamp(vel, 0, 127)
    note_on(n, vel)
  end

  -- Store notes for sustain mode
  if sustain_mode then
    sustain_notes[row] = {}
    for _, n in ipairs(chord.notes) do table.insert(sustain_notes[row], n) end
  end

  if arp_on[row] then
    start_arp(row, chord)
  end
end

local function release_chord(row, col)
  local chord = chord_grid[row][col]
  if not chord then return end

  -- If sustain_mode is off, release chord notes immediately
  if not sustain_mode then
    for _, n in ipairs(chord.notes) do note_off(n) end
  end

  if arp_on[row] then stop_arp(row) end
  screen_dirty = true
end

--------------------------------------------------------------------------------
-- GRID CALLBACK
--------------------------------------------------------------------------------
local function grid_key(x, y, z)
  -- ARP COLUMN
  if x == ARP_COL then
    if z == 1 then
      arp_on[y] = not arp_on[y]
      grid_dirty = true
      screen_dirty = true
    end
    return
  end

  -- CHORD PADS
  if x >= 1 and x <= PAD_COLS then
    if not held[y] then held[y] = {} end
    if z == 1 then
      held[y][x] = true
      play_chord(y, x)
    else
      held[y][x] = false
      release_chord(y, x)
    end
    grid_dirty = true
  end
end

--------------------------------------------------------------------------------
-- NORNS SCREEN
--------------------------------------------------------------------------------
local function draw_play_page()
  screen.font_face(1)
  -- chord name large
  screen.level(15)
  screen.font_size(16)
  screen.move(64, 28)
  screen.text_center(last_chord_name ~= "" and last_chord_name or "--")
  -- subtitle
  screen.font_size(8)
  screen.level(6)
  screen.move(64, 42)
  screen.text_center(THEMES[current_theme].name)
  -- arp indicators
  screen.font_size(7)
  local ax = 4
  for row = 1, GRID_H do
    screen.level(arp_on[row] and 15 or 3)
    screen.move(ax, 58)
    screen.text("ARP" .. row)
    ax = ax + 15
  end
  -- bpm
  screen.level(5)
  screen.move(64, 62)
  screen.text_center("BPM " .. bpm .. "  ARP " .. arp_rate_names[arp_rate_idx])
end

local function draw_tempo_page()
  screen.level(12)
  screen.font_size(10)
  screen.move(64, 18)
  screen.text_center("TEMPO")
  screen.font_size(24)
  screen.level(15)
  screen.move(64, 44)
  screen.text_center(tostring(bpm))  -- fix: tostring() required, screen.text_center does not coerce numbers
  screen.font_size(9)
  screen.level(8)
  screen.move(64, 56)
  screen.text_center("ARP RATE: " .. arp_rate_names[arp_rate_idx])
  screen.level(4)
  screen.font_size(7)
  screen.move(64, 63)
  screen.text_center("E2=BPM  E3=ARP RATE")
end

local function draw_theme_page()
  screen.font_size(10)
  screen.level(12)
  screen.move(64, 18)
  screen.text_center("THEME / VIBE")
  -- list themes
  for i, th in ipairs(THEMES) do
    if i == current_theme then
      screen.level(15)
      screen.move(8, 26 + (i-1)*8)
      screen.text("> " .. th.name)
    else
      screen.level(5)
      screen.move(12, 26 + (i-1)*8)
      screen.text(th.name)
    end
  end
  screen.level(4)
  screen.font_size(7)
  screen.move(64, 63)
  screen.text_center("E2=THEME  K3=REGEN GRID")
end

--------------------------------------------------------------------------------
-- NORNS CALLBACKS
--------------------------------------------------------------------------------
function init()
  -- init state
  for row = 1, GRID_H do
    arp_on[row] = false
    held[row]   = {}
  end

  -- generate chord layout
  math.randomseed(os.time())
  generate_grid()

  -- grid
  g = grid.connect()
  g.key = grid_key

  -- params
  params:add_separator("CHORDOMA")
  params:add{type="number", id="bpm", name="BPM", min=40, max=240, default=120,
    action=function(v) bpm = v; screen_dirty = true end}
  params:add{type="number", id="arp_rate", name="ARP RATE", min=1, max=#arp_rates, default=3,
    action=function(v) arp_rate_idx = v; restart_active_arps(); screen_dirty = true end}
  params:add{type="number", id="theme", name="THEME", min=1, max=#THEMES, default=1,
    -- fix: must call generate_grid() so the chord grid actually updates when theme changes
    action=function(v) current_theme=v; generate_grid(); grid_dirty=true; screen_dirty=true end}

  -- NEW: Voicing, Velocity, Sustain, Tied Arp
  params:add_separator("VOICING & DYNAMICS")
  params:add_option("voicing", "Chord Voicing", {"close", "open", "drop2", "drop3", "shell"}, 1)
  params:set_action("voicing", function(v)
    voicing_mode = {"close", "open", "drop2", "drop3", "shell"}[v]
    generate_grid()
    grid_dirty = true
    screen_dirty = true
  end)

  params:add{type="number", id="chord_velocity", name="Chord Velocity", min=20, max=127, default=90,
    action=function(v) chord_velocity = v; screen_dirty = true end}

  params:add_option("sustain_mode", "Sustain Mode", {"off", "on"}, 1)
  params:set_action("sustain_mode", function(v)
    sustain_mode = (v == 2)
    screen_dirty = true
  end)

  params:add_option("tied_arp", "Tied Arp", {"off", "on"}, 1)
  params:set_action("tied_arp", function(v)
    tied_arp = (v == 2)
    restart_active_arps()
    screen_dirty = true
  end)

  -- screen redraw clock
  clock.run(function()
    while true do
      clock.sleep(1/30)
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
      if grid_dirty then
        update_grid_leds()
        grid_dirty = false
      end
    end
  end)

  update_grid_leds()
  redraw()
end

function redraw()
  screen.clear()
  if current_page == 1 then
    draw_play_page()
  elseif current_page == 2 then
    draw_tempo_page()
  elseif current_page == 3 then
    draw_theme_page()
  end
  screen.update()
end

function enc(n, d)
  if n == 1 then
    current_page = util.clamp(current_page + (d > 0 and 1 or -1), 1, 3)
    screen_dirty = true

  elseif n == 2 then
    if current_page == 2 then
      bpm = util.clamp(bpm + d, 40, 240)
      params:set("bpm", bpm)
    elseif current_page == 3 then
      current_theme = util.clamp(current_theme + (d > 0 and 1 or -1), 1, #THEMES)
      params:set("theme", current_theme)
    end
    screen_dirty = true

  elseif n == 3 then
    if current_page == 2 then
      arp_rate_idx = util.clamp(arp_rate_idx + (d > 0 and 1 or -1), 1, #arp_rates)
      params:set("arp_rate", arp_rate_idx)
      restart_active_arps()
    end
    screen_dirty = true
  end
end

function key(n, z)
  if n == 2 and z == 1 then
    all_notes_off()
    for row = 1, GRID_H do
      held[row] = {}
      stop_arp(row)
      sustain_notes[row] = nil
    end
    last_chord_name = ""
    grid_dirty = true
    screen_dirty = true

  elseif n == 3 and z == 1 then
    all_notes_off()
    for row = 1, GRID_H do
      sustain_notes[row] = nil
      arp_indices[row] = 1
    end
    generate_grid()
    for row = 1, GRID_H do held[row] = {} end
    last_chord_name = "Grid Regenerated"
    grid_dirty = true
    screen_dirty = true
  end
end

function cleanup()
  all_notes_off()
  for row = 1, GRID_H do
    stop_arp(row)
    sustain_notes[row] = nil
  end
end
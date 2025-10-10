-- Scooby.cc
-- Clean, stable, practical rewrite based on pastesis REcode
-- No custom window; uses native AA groups only

local ffi = require('ffi')
local c_entity = require('gamesense/entity')
local pui = require('gamesense/pui')
local base64 = require('gamesense/base64')
local clipboard = require('gamesense/clipboard')
local json = require('json')

-- ========= Utilities =========
local function clamp(x, a, b) if a > x then return a elseif b < x then return b else return x end end
local function lerp(a, b, t) return a + (b - a) * t end
local function toticks(seconds) return math.floor(0.5 + (seconds / globals.tickinterval())) end
local function rgba_to_hex(r, g, b, a) return string.format('%02x%02x%02x%02x', r, g, b, a) end
math.lerp = function(value, target, speed) return value + (target - value) * globals.absoluteframetime() * speed end

local function safe_callback(name, fn)
  client.set_event_callback(name, function(...)
    local ok, err = pcall(fn, ...)
    if not ok then print(string.format('[scooby.cc] %s error: %s', tostring(name), tostring(err))) end
  end)
end

-- ========= Engine refs =========
local screen_w, screen_h = client.screen_size()
local cx, cy = screen_w/2, screen_h/2

local function ref1(a,b,c) local ok,v = pcall(ui.reference, a,b,c) if ok then return v end return nil end
local function refN(a,b,c) local ok,v1,v2 = pcall(ui.reference, a,b,c) if ok then return {v1,v2} end return {nil,nil} end

local ref = {
  enabled = ref1('AA','Anti-aimbot angles','Enabled'),
  yawbase = ref1('AA','Anti-aimbot angles','Yaw base'),
  fsbodyyaw = ref1('AA','Anti-aimbot angles','Freestanding body yaw'),
  edgeyaw = ref1('AA','Anti-aimbot angles','Edge yaw'),
  fakeduck = ref1('RAGE','Other','Duck peek assist'),
  forcebaim = ref1('RAGE','Aimbot','Force body aim'),
  safepoint = ref1('RAGE','Aimbot','Force safe point'),
  roll = refN('AA','Anti-aimbot angles','Roll'),
  clantag = ref1('Misc','Miscellaneous','Clan tag spammer'),
  pitch = refN('AA','Anti-aimbot angles','Pitch'),
  rage = refN('RAGE','Aimbot','Enabled'),
  yaw = refN('AA','Anti-aimbot angles','Yaw'),
  yawjitter = refN('AA','Anti-aimbot angles','Yaw jitter'),
  bodyyaw = refN('AA','Anti-aimbot angles','Body yaw'),
  freestand = refN('AA','Anti-aimbot angles','Freestanding'),
  slow = refN('AA','Other','Slow motion'),
  os = refN('AA','Other','On shot anti-aim'),
  dt = refN('RAGE','Aimbot','Double tap'),
  min_dmg_override = refN('RAGE','Aimbot','Minimum damage override'),
}

-- ========= UI (no custom window) =========
pui.accent = '9FCA2BFF'
local cond_full = { 'Global','Stand','Walking','Running','Air','Air+','Duck','Duck+Move' }
local cond_short = { 'G','S','W','R','A','A+','D','D+' }

local group_main = pui.group('aa','anti-aimbot angles')
local group_config = pui.group('aa','Fake lag')
local group_visuals = pui.group('aa','other')
local group_misc = pui.group('aa','other')

local menu = {
  main = {
    header = group_main:label('Scooby.cc'),
    tab = group_main:combobox('Tab', {'Anti-Aim','Visuals','Misc','Config'}),
  },
  aa = {
    subtab = group_main:combobox('Anti-Aim Tab', {'Main','Builder'}),
    helpers = group_main:multiselect('Utilities', {'Warmup AA','Anti-Knife','Safe Head'}),
    safe_head_opts = group_main:multiselect('Safe Head Triggers', {'Air+C Knife','Air+C Zeus','High Distance'}),
    yaw_direction_modes = group_main:multiselect('Yaw Direction Mode', {'Freestanding','Manual'}),
    hotkey_fs = group_main:hotkey('Freestanding Hotkey'),
    hotkey_left = group_main:hotkey('Manual Left'),
    hotkey_right = group_main:hotkey('Manual Right'),
    hotkey_forward = group_main:hotkey('Manual Forward'),
    yaw_base = group_main:combobox('Yaw Base', {'Local view','At targets'}),
    condition = group_main:combobox('Condition', cond_full),
  },
  visuals = {
    cross_ind = group_visuals:checkbox('Crosshair Indicators', {255,255,255}),
    cross_style = group_visuals:combobox('Indicator Style', {'Newest','Default','Modern','Alternative'}),
    cross_color = group_visuals:checkbox('Indicator Color', {120,120,255}),
    key_color = group_visuals:checkbox('Keybind Color', {255,255,255}),
    manual_arrows = group_visuals:checkbox('Manual Direction Arrows', {255,255,255}),
    manual_arrow_size = group_visuals:slider('Arrow Size', 6, 24, 12, true, 'px', 1),
    manual_arrow_offset = group_visuals:slider('Arrow Offset', 20, 100, 40, true, 'px', 1),
    info_panel = group_visuals:checkbox('Info Panel'),
    defensive_window = group_visuals:checkbox('Defense Meter', {255,255,255}),
    defensive_style = group_visuals:combobox('Defensive Style', {'Default','Modern'}),
    velocity_window = group_visuals:checkbox('Speed Meter', {255,255,255}),
    velocity_style = group_visuals:combobox('Velocity Style', {'Default','Modern'}),
  },
  misc = {
    fast_ladder = group_misc:checkbox('Fast Ladder'),
    logs = group_misc:checkbox('Ragebot Logs'),
    logs_type = group_misc:multiselect('Log Types', {'Console','Screen'}),
    logs_screen_style = group_misc:combobox('Log Style', {'Default','Modern'}),
    animation = group_misc:checkbox('Animation Breakers'),
    animation_ground = group_misc:combobox('Ground Animation', {'Static','Jitter','Randomize'}),
    animation_amount = group_misc:slider('Animation Value', 0, 10, 5),
    animation_air = group_misc:combobox('Air Animation', {'Off','Static','Randomize'}),
    third_person = group_misc:checkbox('Third Person Distance'),
    third_person_value = group_misc:slider('Third Person Distance Value', 30, 200, 50),
    aspectratio = group_misc:checkbox('Aspect Ratio'),
    aspectratio_value = group_misc:slider('Aspect Ratio Value (x100)', 0, 200, 133),
    teleport = group_misc:checkbox('Break LC Teleport'),
    teleport_key = group_misc:hotkey('Break LC Teleport Hotkey', true),
    resolver = group_misc:checkbox('Custom Resolver'),
    resolver_type = group_misc:combobox('Resolver Type', {'Stable','Adaptive'}),
    resolver_adaptive_strength = group_misc:slider('Adaptive Strength', 0, 100, 70, true, '%', 1),
    spammers = group_misc:multiselect('Spammers', {'Clantag','TrashTalk'}),
    clantag_enable = group_misc:checkbox('Custom Clantag'),
    clantag_style = group_misc:combobox('Clantag Style', {'Off','Classic','Wave','Typewriter','Crown'}),
    clantag_speed = group_misc:slider('Clantag Speed (ms)', 100, 1000, 300, true, 'ms', 10),
    clantag_preset = group_misc:combobox('Clantag Preset', {'scooby.cc ♛','pastesis','gamesense','crowned'}),
    revolver_helper = group_misc:checkbox('Revolver Helper'),
    revolver_delay = group_misc:slider('R8 Early Fire %', 0, 100, 60, true, '%', 1),
    revolver_hold_ticks = group_misc:slider('R8 Hold Ticks', 5, 20, 12, true, 't', 1),
    console_filter = group_misc:checkbox('Console Filter (Hits/Misses only)'),
  },
  config = {
    title = group_config:label('Config'),
  }
}

-- Per-condition builder
local builder = {}
for i = 1, #cond_full do
  local s = cond_short[i]
  builder[i] = {
    label = group_main:label('· Builder: ' .. cond_full[i]),
    enable = group_main:checkbox(s .. ' · Enable'),
    yaw_mode = group_main:combobox(s .. ' · Yaw Mode', {'Default','Delay','Spin','Freestand','Manual'}),
    yaw_delay = group_main:slider(s .. ' · Delay Ticks', 1, 10, 4, true, 't', 1),
    yaw_left = group_main:slider(s .. ' · Yaw Left', -180, 180, 0, true, '°', 1),
    yaw_right = group_main:slider(s .. ' · Yaw Right', -180, 180, 0, true, '°', 1),
    yaw_random = group_main:slider(s .. ' · Randomization', 0, 100, 0, true, '%', 1),
    jitter_type = group_main:combobox(s .. ' · Jitter Type', {'Off','Offset','Center','Random','Skitter','3-way','5-way','7-way','9-way'}),
    jitter_amount = group_main:slider(s .. ' · Jitter Amount', -180, 180, 0, true, '°', 1),
    jitter_seq_mode = group_main:combobox(s .. ' · Jitter Sequence', {'Automatic','Custom'}),
    j3_1 = group_main:slider(s .. ' · 3-way A1', -180, 180, -45, true, '°', 1),
    j3_2 = group_main:slider(s .. ' · 3-way A2', -180, 180, 1, true, '°', 1),
    j3_3 = group_main:slider(s .. ' · 3-way A3', -180, 180, 45, true, '°', 1),
    j5_1 = group_main:slider(s .. ' · 5-way A1', -180, 180, -80, true, '°', 1),
    j5_2 = group_main:slider(s .. ' · 5-way A2', -180, 180, -45, true, '°', 1),
    j5_3 = group_main:slider(s .. ' · 5-way A3', -180, 180, -1, true, '°', 1),
    j5_4 = group_main:slider(s .. ' · 5-way A4', -180, 180, 45, true, '°', 1),
    j5_5 = group_main:slider(s .. ' · 5-way A5', -180, 180, 80, true, '°', 1),
    j7_1 = group_main:slider(s .. ' · 7-way A1', -180, 180, -90, true, '°', 1),
    j7_2 = group_main:slider(s .. ' · 7-way A2', -180, 180, -60, true, '°', 1),
    j7_3 = group_main:slider(s .. ' · 7-way A3', -180, 180, -30, true, '°', 1),
    j7_4 = group_main:slider(s .. ' · 7-way A4', -180, 180, 0, true, '°', 1),
    j7_5 = group_main:slider(s .. ' · 7-way A5', -180, 180, 30, true, '°', 1),
    j7_6 = group_main:slider(s .. ' · 7-way A6', -180, 180, 60, true, '°', 1),
    j7_7 = group_main:slider(s .. ' · 7-way A7', -180, 180, 90, true, '°', 1),
    j9_1 = group_main:slider(s .. ' · 9-way A1', -180, 180, -120, true, '°', 1),
    j9_2 = group_main:slider(s .. ' · 9-way A2', -180, 180, -90, true, '°', 1),
    j9_3 = group_main:slider(s .. ' · 9-way A3', -180, 180, -60, true, '°', 1),
    j9_4 = group_main:slider(s .. ' · 9-way A4', -180, 180, -30, true, '°', 1),
    j9_5 = group_main:slider(s .. ' · 9-way A5', -180, 180, 0, true, '°', 1),
    j9_6 = group_main:slider(s .. ' · 9-way A6', -180, 180, 30, true, '°', 1),
    j9_7 = group_main:slider(s .. ' · 9-way A7', -180, 180, 60, true, '°', 1),
    j9_8 = group_main:slider(s .. ' · 9-way A8', -180, 180, 90, true, '°', 1),
    j9_9 = group_main:slider(s .. ' · 9-way A9', -180, 180, 120, true, '°', 1),
    body_type = group_main:combobox(s .. ' · Body Yaw', {'Off','Opposite','Jitter','Static'}),
    body_amount = group_main:slider(s .. ' · Body Yaw Amount', -180, 180, 0, true, '°', 1),
    -- Defensive
    def_enable = group_main:checkbox(s .. ' · Defensive'),
    def_activation = group_main:multiselect(s .. ' · Defensive When', {'Vulnerable (scoped enemy)','Charged DT','On Peek','Threat Shot'}),
    def_type = group_main:combobox(s .. ' · Defensive Type', {'Default','Builder','ExpDefensive'}),
    def_yaw_mode = group_main:combobox(s .. ' · Defensive Yaw', {'Off','Spin','Meta','Random'}),
    yaw_value = group_main:slider(s .. ' · Yaw Value', -180, 180, 0, true, '°', 1),
    def_yaw_value = group_main:slider(s .. ' · [DEF] Yaw Value', -180, 180, 0, true, '°', 1),
    def_jitter_type = group_main:combobox(s .. ' · [DEF] Jitter Type', {'Off','Offset','Center','Random','Skitter','3-way','5-way','7-way','9-way'}),
    def_jitter_amount = group_main:slider(s .. ' · [DEF] Jitter Amount', -180, 180, 0, true, '°', 1),
    def_jitter_seq_mode = group_main:combobox(s .. ' · [DEF] Sequence', {'Automatic','Custom'}),
    def_j3_1 = group_main:slider(s .. ' · [DEF] 3-way A1', -180, 180, -45, true, '°', 1),
    def_j3_2 = group_main:slider(s .. ' · [DEF] 3-way A2', -180, 180, 1, true, '°', 1),
    def_j3_3 = group_main:slider(s .. ' · [DEF] 3-way A3', -180, 180, 45, true, '°', 1),
    def_j5_1 = group_main:slider(s .. ' · [DEF] 5-way A1', -180, 180, -80, true, '°', 1),
    def_j5_2 = group_main:slider(s .. ' · [DEF] 5-way A2', -180, 180, -45, true, '°', 1),
    def_j5_3 = group_main:slider(s .. ' · [DEF] 5-way A3', -180, 180, -1, true, '°', 1),
    def_j5_4 = group_main:slider(s .. ' · [DEF] 5-way A4', -180, 180, 45, true, '°', 1),
    def_j5_5 = group_main:slider(s .. ' · [DEF] 5-way A5', -180, 180, 80, true, '°', 1),
    def_j7_1 = group_main:slider(s .. ' · [DEF] 7-way A1', -180, 180, -90, true, '°', 1),
    def_j7_2 = group_main:slider(s .. ' · [DEF] 7-way A2', -180, 180, -60, true, '°', 1),
    def_j7_3 = group_main:slider(s .. ' · [DEF] 7-way A3', -180, 180, -30, true, '°', 1),
    def_j7_4 = group_main:slider(s .. ' · [DEF] 7-way A4', -180, 180, 0, true, '°', 1),
    def_j7_5 = group_main:slider(s .. ' · [DEF] 7-way A5', -180, 180, 30, true, '°', 1),
    def_j7_6 = group_main:slider(s .. ' · [DEF] 7-way A6', -180, 180, 60, true, '°', 1),
    def_j7_7 = group_main:slider(s .. ' · [DEF] 7-way A7', -180, 180, 90, true, '°', 1),
    def_j9_1 = group_main:slider(s .. ' · [DEF] 9-way A1', -180, 180, -120, true, '°', 1),
    def_j9_2 = group_main:slider(s .. ' · [DEF] 9-way A2', -180, 180, -90, true, '°', 1),
    def_j9_3 = group_main:slider(s .. ' · [DEF] 9-way A3', -180, 180, -60, true, '°', 1),
    def_j9_4 = group_main:slider(s .. ' · [DEF] 9-way A4', -180, 180, -30, true, '°', 1),
    def_j9_5 = group_main:slider(s .. ' · [DEF] 9-way A5', -180, 180, 0, true, '°', 1),
    def_j9_6 = group_main:slider(s .. ' · [DEF] 9-way A6', -180, 180, 30, true, '°', 1),
    def_j9_7 = group_main:slider(s .. ' · [DEF] 9-way A7', -180, 180, 60, true, '°', 1),
    def_j9_8 = group_main:slider(s .. ' · [DEF] 9-way A8', -180, 180, 90, true, '°', 1),
    def_j9_9 = group_main:slider(s .. ' · [DEF] 9-way A9', -180, 180, 120, true, '°', 1),
    def_body_type = group_main:combobox(s .. ' · [DEF] Body Yaw', {'Off','Opposite','Jitter','Static'}),
    def_body_amount = group_main:slider(s .. ' · [DEF] Body Yaw Amount', -180, 180, 0, true, '°', 1),
    -- Pitch
    pitch_mode = group_main:combobox(s .. ' · Pitch', {'Off','Custom','Meta','Random'}),
    pitch_value = group_main:slider(s .. ' · Pitch Value', -89, 89, 0, true, '°', 1),
    pitch_seq_mode = group_main:combobox(s .. ' · Pitch Sequence', {'Off','3-way','5-way','Custom'}),
    p3_1 = group_main:slider(s .. ' · Pitch 3-way A1', -89, 89, -45, true, '°', 1),
    p3_2 = group_main:slider(s .. ' · Pitch 3-way A2', -89, 89, 0, true, '°', 1),
    p3_3 = group_main:slider(s .. ' · Pitch 3-way A3', -89, 89, 45, true, '°', 1),
    p5_1 = group_main:slider(s .. ' · Pitch 5-way A1', -89, 89, -89, true, '°', 1),
    p5_2 = group_main:slider(s .. ' · Pitch 5-way A2', -89, 89, -45, true, '°', 1),
    p5_3 = group_main:slider(s .. ' · Pitch 5-way A3', -89, 89, 0, true, '°', 1),
    p5_4 = group_main:slider(s .. ' · Pitch 5-way A4', -89, 89, 45, true, '°', 1),
    p5_5 = group_main:slider(s .. ' · Pitch 5-way A5', -89, 89, 89, true, '°', 1),
    def_pitch_mode = group_main:combobox(s .. ' · Defensive Pitch', {'Off','Custom','Meta','Random'}),
    def_pitch_value = group_main:slider(s .. ' · Defensive Pitch Value', -89, 89, 0, true, '°', 1),
    def_pitch_seq_mode = group_main:combobox(s .. ' · [DEF] Pitch Sequence', {'Off','3-way','5-way','Custom'}),
    def_p3_1 = group_main:slider(s .. ' · [DEF] Pitch 3-way A1', -89, 89, -45, true, '°', 1),
    def_p3_2 = group_main:slider(s .. ' · [DEF] Pitch 3-way A2', -89, 89, 0, true, '°', 1),
    def_p3_3 = group_main:slider(s .. ' · [DEF] Pitch 3-way A3', -89, 89, 45, true, '°', 1),
    def_p5_1 = group_main:slider(s .. ' · [DEF] Pitch 5-way A1', -89, 89, -89, true, '°', 1),
    def_p5_2 = group_main:slider(s .. ' · [DEF] Pitch 5-way A2', -89, 89, -45, true, '°', 1),
    def_p5_3 = group_main:slider(s .. ' · [DEF] Pitch 5-way A3', -89, 89, 0, true, '°', 1),
    def_p5_4 = group_main:slider(s .. ' · [DEF] Pitch 5-way A4', -89, 89, 45, true, '°', 1),
    def_p5_5 = group_main:slider(s .. ' · [DEF] Pitch 5-way A5', -89, 89, 89, true, '°', 1),
    force_def = group_main:checkbox(s .. ' · Force Defensive'),
    peek_def = group_main:checkbox(s .. ' · Defensive Peek'),
  }
end

-- Visibility deps
local tabs = {
  aa = {menu.main.tab,'Anti-Aim'}, visuals = {menu.main.tab,'Visuals'}, misc = {menu.main.tab,'Misc'}, config = {menu.main.tab,'Config'}
}
menu.aa.subtab:depend(tabs.aa)
menu.aa.helpers:depend(tabs.aa)
menu.aa.safe_head_opts:depend(tabs.aa, {menu.aa.helpers,'Safe Head'})
menu.aa.yaw_direction_modes:depend(tabs.aa)
menu.aa.hotkey_fs:depend(tabs.aa, {menu.aa.yaw_direction_modes,'Freestanding'})
menu.aa.hotkey_left:depend(tabs.aa, {menu.aa.yaw_direction_modes,'Manual'})
menu.aa.hotkey_right:depend(tabs.aa, {menu.aa.yaw_direction_modes,'Manual'})
menu.aa.hotkey_forward:depend(tabs.aa, {menu.aa.yaw_direction_modes,'Manual'})
menu.aa.yaw_base:depend(tabs.aa)
menu.aa.condition:depend(tabs.aa, {menu.aa.subtab,'Builder'})

menu.visuals.cross_ind:depend(tabs.visuals)
menu.visuals.cross_style:depend(tabs.visuals, {menu.visuals.cross_ind, true})
menu.visuals.cross_color:depend(tabs.visuals, {menu.visuals.cross_ind, true})
menu.visuals.key_color:depend(tabs.visuals, {menu.visuals.cross_ind, true})
menu.visuals.manual_arrows:depend(tabs.visuals, {menu.visuals.cross_ind, true})
menu.visuals.manual_arrow_size:depend(tabs.visuals, {menu.visuals.manual_arrows, true})
menu.visuals.manual_arrow_offset:depend(tabs.visuals, {menu.visuals.manual_arrows, true})
menu.visuals.info_panel:depend(tabs.visuals)
menu.visuals.defensive_window:depend(tabs.visuals)
menu.visuals.defensive_style:depend(tabs.visuals, {menu.visuals.defensive_window, true})
menu.visuals.velocity_window:depend(tabs.visuals)
menu.visuals.velocity_style:depend(tabs.visuals, {menu.visuals.velocity_window, true})

menu.misc.fast_ladder:depend(tabs.misc)
menu.misc.logs:depend(tabs.misc)
menu.misc.logs_type:depend(tabs.misc, {menu.misc.logs, true})
menu.misc.logs_screen_style:depend(tabs.misc, {menu.misc.logs, true}, {menu.misc.logs_type, 'Screen'})
menu.misc.animation:depend(tabs.misc)
menu.misc.animation_ground:depend(tabs.misc, {menu.misc.animation, true})
menu.misc.animation_amount:depend(tabs.misc, {menu.misc.animation, true})
menu.misc.animation_air:depend(tabs.misc, {menu.misc.animation, true})
menu.misc.third_person:depend(tabs.misc)
menu.misc.third_person_value:depend(tabs.misc, {menu.misc.third_person, true})
menu.misc.aspectratio:depend(tabs.misc)
menu.misc.aspectratio_value:depend(tabs.misc, {menu.misc.aspectratio, true})
menu.misc.teleport:depend(tabs.misc)
menu.misc.teleport_key:depend(tabs.misc)
menu.misc.resolver:depend(tabs.misc)
menu.misc.resolver_type:depend(tabs.misc, {menu.misc.resolver, true})
menu.misc.resolver_adaptive_strength:depend(tabs.misc, {menu.misc.resolver, true}, {menu.misc.resolver_type, 'Adaptive'})
menu.misc.spammers:depend(tabs.misc)
menu.misc.clantag_enable:depend(tabs.misc, {menu.misc.spammers, 'Clantag'})
menu.misc.clantag_style:depend(tabs.misc, {menu.misc.clantag_enable, true})
menu.misc.clantag_speed:depend(tabs.misc, {menu.misc.clantag_enable, true})
menu.misc.clantag_preset:depend(tabs.misc, {menu.misc.clantag_enable, true})
menu.misc.revolver_helper:depend(tabs.misc)
menu.misc.revolver_delay:depend(tabs.misc, {menu.misc.revolver_helper, true})
menu.misc.revolver_hold_ticks:depend(tabs.misc, {menu.misc.revolver_helper, true})

for i = 1, #cond_full do
  local cond_only = {menu.aa.condition, cond_full[i]}
  local in_builder = {menu.aa.subtab, 'Builder'}
  local enabled_or_global = {builder[i].enable, function() return (i == 1) or builder[i].enable:get() end}

  builder[i].label:depend(tabs.aa, in_builder, cond_only)
  builder[i].enable:depend(tabs.aa, in_builder, cond_only)
  builder[i].yaw_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_delay:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].yaw_mode, 'Delay'})
  builder[i].yaw_left:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_right:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_random:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].jitter_type:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].jitter_amount:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].jitter_type, function()
    local t = builder[i].jitter_type:get(); return t ~= 'Off' end})
  builder[i].jitter_seq_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].jitter_type, function()
    local t = builder[i].jitter_type:get(); return t == '3-way' or t == '5-way' or t == '7-way' or t == '9-way' end})
  -- custom seqs
  builder[i].j3_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'3-way'})
  builder[i].j3_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'3-way'})
  builder[i].j3_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'3-way'})
  builder[i].j5_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'5-way'})
  builder[i].j5_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'5-way'})
  builder[i].j5_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'5-way'})
  builder[i].j5_4:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'5-way'})
  builder[i].j5_5:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'5-way'})
  builder[i].j7_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_4:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_5:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_6:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j7_7:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'7-way'})
  builder[i].j9_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_4:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_5:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_6:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_7:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_8:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})
  builder[i].j9_9:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_seq_mode,'Custom'}, {builder[i].jitter_type,'9-way'})

  builder[i].body_type:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].body_amount:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].body_type, function() return builder[i].body_type:get() ~= 'Off' end})

  builder[i].def_enable:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].def_activation:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_type:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_yaw_mode:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Default'})
  builder[i].yaw_value:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].def_yaw_value:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'})
  builder[i].def_jitter_type:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'})
  builder[i].def_jitter_amount:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'}, {builder[i].def_jitter_type, function()
    local t = builder[i].def_jitter_type:get(); return t ~= 'Off' end})
  builder[i].def_jitter_seq_mode:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'}, {builder[i].def_jitter_type, function()
    local t = builder[i].def_jitter_type:get(); return t == '3-way' or t == '5-way' or t == '7-way' or t == '9-way' end})
  builder[i].def_j3_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'3-way'})
  builder[i].def_j3_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'3-way'})
  builder[i].def_j3_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'3-way'})
  builder[i].def_j5_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'5-way'})
  builder[i].def_j5_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'5-way'})
  builder[i].def_j5_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'5-way'})
  builder[i].def_j5_4:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'5-way'})
  builder[i].def_j5_5:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'5-way'})
  builder[i].def_j7_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_4:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_5:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_6:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j7_7:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'7-way'})
  builder[i].def_j9_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_4:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_5:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_6:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_7:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_8:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})
  builder[i].def_j9_9:depend(tabs.aa, in_builder, cond_only, {builder[i].def_jitter_seq_mode,'Custom'}, {builder[i].def_jitter_type,'9-way'})

  builder[i].def_body_type:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'})
  builder[i].def_body_amount:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_type,'Builder'}, {builder[i].def_body_type, function() return builder[i].def_body_type:get() ~= 'Off' end})

  builder[i].pitch_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].pitch_value:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].pitch_mode,'Custom'})
  builder[i].pitch_seq_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].p3_1:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'3-way'})
  builder[i].p3_2:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'3-way'})
  builder[i].p3_3:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'3-way'})
  builder[i].p5_1:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'5-way'})
  builder[i].p5_2:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'5-way'})
  builder[i].p5_3:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'5-way'})
  builder[i].p5_4:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'5-way'})
  builder[i].p5_5:depend(tabs.aa, in_builder, cond_only, {builder[i].pitch_seq_mode,'5-way'})

  builder[i].def_pitch_mode:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_pitch_value:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true}, {builder[i].def_pitch_mode,'Custom'})
  builder[i].def_pitch_seq_mode:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_p3_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'3-way'})
  builder[i].def_p3_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'3-way'})
  builder[i].def_p3_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'3-way'})
  builder[i].def_p5_1:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'5-way'})
  builder[i].def_p5_2:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'5-way'})
  builder[i].def_p5_3:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'5-way'})
  builder[i].def_p5_4:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'5-way'})
  builder[i].def_p5_5:depend(tabs.aa, in_builder, cond_only, {builder[i].def_pitch_seq_mode,'5-way'})
  builder[i].force_def:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].peek_def:depend(tabs.aa, in_builder, cond_only, {builder[i].force_def,false})
end

-- ========= Config (pui) =========
local package = pui.setup({menu, builder})
local Config = {}
function Config.export()
  local data = package:save()
  local encoded = base64.encode(json.stringify(data))
  clipboard.set(encoded)
  print('[scooby.cc] Exported')
end
function Config.import(input)
  local decoded = json.parse(base64.decode(input ~= nil and input or clipboard.get()))
  package:load(decoded)
  print('[scooby.cc] Imported')
end
function Config.load_defaults()
  for i = 1, #cond_full do
    builder[i].enable:set(i == 1)
    builder[i].yaw_mode:set('Default')
    builder[i].yaw_delay:set(4)
    builder[i].yaw_left:set(9)
    builder[i].yaw_right:set(9)
    builder[i].yaw_random:set(0)
    builder[i].jitter_type:set('Center')
    builder[i].jitter_amount:set(0)
    builder[i].body_type:set('Jitter')
    builder[i].body_amount:set(i == 4 and 1 or -1)
    builder[i].def_enable:set(true)
    builder[i].def_activation:set({'Vulnerable (scoped enemy)','On Peek'})
    builder[i].def_type:set('Builder')
    builder[i].def_yaw_mode:set('Spin')
    builder[i].yaw_value:set(0)
    builder[i].def_yaw_value:set(9)
    builder[i].def_jitter_type:set('Center')
    builder[i].def_jitter_amount:set(70)
    builder[i].def_body_type:set('Jitter')
    builder[i].def_body_amount:set(1)
    builder[i].pitch_mode:set('Off')
    builder[i].pitch_value:set(0)
    builder[i].def_pitch_mode:set('Off')
    builder[i].def_pitch_value:set(0)
    builder[i].force_def:set(true)
    builder[i].peek_def:set(false)
  end
end
menu.config.export_btn = group_config:button('Export Config', function() Config.export() end)
menu.config.import_btn = group_config:button('Import Config', function() Config.import() end)
menu.config.default_btn = group_config:button('Load Defaults', function() Config.load_defaults() end)

-- ========= Helpers/State =========
local function hide_original_menu(state)
  ui.set_visible(ref.enabled, state)
  ui.set_visible(ref.pitch[1], state)
  if ref.pitch[2] then ui.set_visible(ref.pitch[2], state) end
  ui.set_visible(ref.yawbase, state)
  ui.set_visible(ref.yaw[1], state)
  if ref.yaw[2] then ui.set_visible(ref.yaw[2], state) end
  ui.set_visible(ref.yawjitter[1], state)
  if ref.roll[1] then ui.set_visible(ref.roll[1], state) end
  if ref.yawjitter[2] then ui.set_visible(ref.yawjitter[2], state) end
  ui.set_visible(ref.bodyyaw[1], state)
  if ref.bodyyaw[2] then ui.set_visible(ref.bodyyaw[2], state) end
  ui.set_visible(ref.fsbodyyaw, state)
  ui.set_visible(ref.edgeyaw, state)
  ui.set_visible(ref.freestand[1], state)
  ui.set_visible(ref.freestand[2], state)
end

local function players_vulnerable()
  for _, v in ipairs(entity.get_players(true)) do
    local flags = (entity.get_esp_data(v) or {}).flags
    if flags and bit.band(flags, bit.lshift(1, 11)) ~= 0 then return true end
  end
  return false
end

local yaw_direction, last_press_t_dir = 0, 0
local function run_direction()
  ui.set(ref.freestand[1], menu.aa.yaw_direction_modes:get('Freestanding'))
  ui.set(ref.freestand[2], menu.aa.hotkey_fs:get() and 'Always on' or 'On hotkey')
  if yaw_direction ~= 0 then ui.set(ref.freestand[1], false) end
  local now = globals.curtime()
  if menu.aa.yaw_direction_modes:get('Manual') and menu.aa.hotkey_right:get() and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == 90 and 0 or 90; last_press_t_dir = now
  elseif menu.aa.yaw_direction_modes:get('Manual') and menu.aa.hotkey_left:get() and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == -90 and 0 or -90; last_press_t_dir = now
  elseif menu.aa.yaw_direction_modes:get('Manual') and menu.aa.hotkey_forward:get() and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == 180 and 0 or 180; last_press_t_dir = now
  elseif last_press_t_dir > now then last_press_t_dir = now end
end

local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')
local last_sim_time = 0
local function is_defensive_active(ent)
  if globals.chokedcommands() > 1 then return false end
  if not ent or not entity.is_alive(ent) then return false end
  local ptr = native_GetClientEntity(ent); if ptr == nil then return false end
  local old = ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0]
  local sim = entity.get_prop(ent, 'm_flSimulationTime')
  local delta = toticks(old - sim)
  if delta > 0 then last_sim_time = globals.tickcount() + delta - toticks(client.real_latency()) end
  return last_sim_time > globals.tickcount()
end

local function is_defensive_resolver(ent)
  if not ent or not entity.is_alive(ent) then return false end
  local ptr = native_GetClientEntity(ent); if ptr == nil then return false end
  local old = ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0]
  local sim = entity.get_prop(ent, 'm_flSimulationTime')
  local delta = toticks(old - sim)
  if delta > 0 then last_sim_time = globals.tickcount() + delta - toticks(client.real_latency()) end
  return last_sim_time > globals.tickcount()
end

local function player_state(cmd)
  local lp = entity.get_local_player(); if not lp then return 'Global' end
  local vx, vy = entity.get_prop(lp, 'm_vecVelocity'); vx, vy = vx or 0, vy or 0
  local velocity = math.sqrt(vx*vx + vy*vy)
  local flags = entity.get_prop(lp, 'm_fFlags') or 0
  local on_ground = bit.band(flags, 1) == 1
  local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
  local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7
  local duckcheck = ducked or ui.get(ref.fakeduck)
  local slowwalk_key = ui.get(ref.slow[1]) and ui.get(ref.slow[2])
  if jumping and duckcheck then return 'Air+'
  elseif jumping then return 'Air'
  elseif duckcheck and velocity > 10 then return 'Duck+Move'
  elseif duckcheck and velocity <= 10 then return 'Duck'
  elseif on_ground and slowwalk_key and velocity > 10 then return 'Walking'
  elseif on_ground and velocity > 5 then return 'Running'
  elseif on_ground and velocity <= 5 then return 'Stand'
  else return 'Global' end
end

-- ========= AA Runtime =========
local cond_idx, tick_gate, toggle_jitter = 1, 0, false
local toggle_def_gate, first_vuln = true, true
local yaw_amount = 0

local function set_safe_head_defaults()
  ui.set(ref.yawjitter[1], 'Off'); ui.set(ref.yaw[1], '180')
  ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], 1)
  ui.set(ref.yaw[2], 14); ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], 89)
end

local function doubletap_charged()
  if not ui.get(ref.dt[1]) or not ui.get(ref.dt[2]) or ui.get(ref.fakeduck) then return false end
  if not entity.is_alive(entity.get_local_player()) then return false end
  local weapon = entity.get_prop(entity.get_local_player(), 'm_hActiveWeapon')
  if weapon == nil then return false end
  local next_attack = (entity.get_prop(entity.get_local_player(), 'm_flNextAttack') or 0) + 0.01
  local next_primary_attack = (entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0) + 0.01
  return (next_attack - globals.curtime() < 0) and (next_primary_attack - globals.curtime() < 0)
end

local function sequence_from_menu(conf, def)
  local mode = def and conf.def_jitter_seq_mode:get() or conf.jitter_seq_mode:get()
  local jt = def and conf.def_jitter_type:get() or conf.jitter_type:get()
  if jt == '3-way' then
    if mode == 'Custom' then
      return { def and conf.def_j3_1:get() or conf.j3_1:get(), def and conf.def_j3_2:get() or conf.j3_2:get(), def and conf.def_j3_3:get() or conf.j3_3:get() }
    else return { -45, 1, 45 } end
  elseif jt == '5-way' then
    if mode == 'Custom' then
      return { def and conf.def_j5_1:get() or conf.j5_1:get(), def and conf.def_j5_2:get() or conf.j5_2:get(), def and conf.def_j5_3:get() or conf.j5_3:get(), def and conf.def_j5_4:get() or conf.j5_4:get(), def and conf.def_j5_5:get() or conf.j5_5:get() }
    else return { -80, -45, -1, 45, 80 } end
  elseif jt == '7-way' then
    if mode == 'Custom' then
      return { def and conf.def_j7_1:get() or conf.j7_1:get(), def and conf.def_j7_2:get() or conf.j7_2:get(), def and conf.def_j7_3:get() or conf.j7_3:get(), def and conf.def_j7_4:get() or conf.j7_4:get(), def and conf.def_j7_5:get() or conf.j7_5:get(), def and conf.def_j7_6:get() or conf.j7_6:get(), def and conf.def_j7_7:get() or conf.j7_7:get() }
    else return { -90, -60, -30, 0, 30, 60, 90 } end
  elseif jt == '9-way' then
    if mode == 'Custom' then
      return { def and conf.def_j9_1:get() or conf.j9_1:get(), def and conf.def_j9_2:get() or conf.j9_2:get(), def and conf.def_j9_3:get() or conf.j9_3:get(), def and conf.def_j9_4:get() or conf.j9_4:get(), def and conf.def_j9_5:get() or conf.j9_5:get(), def and conf.def_j9_6:get() or conf.j9_6:get(), def and conf.def_j9_7:get() or conf.j9_7:get(), def and conf.def_j9_8:get() or conf.j9_8:get(), def and conf.def_j9_9:get() or conf.j9_9:get() }
    else return { -120, -90, -60, -30, 0, 30, 60, 90, 120 } end
  end
  return nil
end

local function is_multiway(jt) return jt == '3-way' or jt == '5-way' or jt == '7-way' or jt == '9-way' end
local function map_jitter_type(jt) return is_multiway(jt) and 'Offset' or jt end
local function apply_multiway(conf, def)
  local seq = sequence_from_menu(conf, def)
  if seq then local idx = (globals.tickcount() % #seq) + 1; return seq[idx] end
  local amount = def and conf.def_jitter_amount:get() or conf.jitter_amount:get()
  return amount
end

local function apply_pitch(mode, value, desync_side, seq_mode, seq_values)
  ui.set(ref.pitch[1], 'Custom')
  if seq_mode and seq_mode ~= 'Off' then
    local seq = nil
    if seq_mode == '3-way' then seq = seq_values and {seq_values[1],seq_values[2],seq_values[3]} or {-45,0,45}
    elseif seq_mode == '5-way' then seq = seq_values and {seq_values[1],seq_values[2],seq_values[3],seq_values[4],seq_values[5]} or {-89,-45,0,45,89}
    elseif seq_mode == 'Custom' then seq = seq_values end
    if seq then local idx = (globals.tickcount() % #seq) + 1; ui.set(ref.pitch[2], clamp(seq[idx], -89, 89)); return end
  end
  if mode == 'Off' then ui.set(ref.pitch[2], 89)
  elseif mode == 'Custom' then ui.set(ref.pitch[2], value)
  elseif mode == 'Meta' then ui.set(ref.pitch[2], desync_side and 49 or -49)
  elseif mode == 'Random' then ui.set(ref.pitch[2], math.random(-89, 89)) end
end

-- threat-shot window flag
_G.__scooby_threat_window = _G.__scooby_threat_window or 0

local function aa_apply(cmd)
  local lp = entity.get_local_player(); if not lp then return end
  -- condition
  local st = player_state(cmd)
  if st == 'Duck+Move' and builder[8].enable:get() then cond_idx = 8
  elseif st == 'Duck' and builder[7].enable:get() then cond_idx = 7
  elseif st == 'Air+' and builder[6].enable:get() then cond_idx = 6
  elseif st == 'Air' and builder[5].enable:get() then cond_idx = 5
  elseif st == 'Running' and builder[4].enable:get() then cond_idx = 4
  elseif st == 'Walking' and builder[3].enable:get() then cond_idx = 3
  elseif st == 'Stand' and builder[2].enable:get() then cond_idx = 2
  else cond_idx = 1 end
  local conf = builder[cond_idx]

  -- reset roll
  if ref.roll[1] then ui.set(ref.roll[1], 0) end

  run_direction()

  if globals.tickcount() > tick_gate + conf.yaw_delay:get() then
    if cmd.chokedcommands == 0 then toggle_jitter = not toggle_jitter; tick_gate = globals.tickcount() end
  elseif globals.tickcount() < tick_gate then tick_gate = globals.tickcount() end

  if players_vulnerable() then
    if first_vuln then first_vuln = false; toggle_def_gate = true end
    if globals.tickcount() % 10 == 9 then toggle_def_gate = false end
  else first_vuln = true; toggle_def_gate = false end

  ui.set(ref.fsbodyyaw, false)
  ui.set(ref.pitch[1], 'Custom')
  ui.set(ref.yawbase, menu.aa.yaw_base:get())

  local selected_builder_def = conf.def_enable:get() and conf.def_type:get() == 'Builder' and is_defensive_active(lp)
  if selected_builder_def then
    ui.set(ref.yawjitter[1], map_jitter_type(conf.def_jitter_type:get()))
    ui.set(ref.yawjitter[2], apply_multiway(conf, true))
    ui.set(ref.bodyyaw[1], conf.def_body_type:get())
    ui.set(ref.bodyyaw[2], conf.def_body_amount:get())
    yaw_amount = (yaw_direction == 0) and conf.def_yaw_value:get() or yaw_direction
  else
    ui.set(ref.yawjitter[1], map_jitter_type(conf.jitter_type:get()))
    ui.set(ref.yawjitter[2], apply_multiway(conf, false))
    if conf.yaw_mode:get() == 'Delay' then
      ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], toggle_jitter and 1 or -1)
    else
      ui.set(ref.bodyyaw[1], conf.body_type:get()); ui.set(ref.bodyyaw[2], conf.body_amount:get())
    end
  end

  if is_defensive_active(lp) and conf.def_enable:get() and conf.def_type:get() == 'Default' and conf.def_yaw_mode:get() == 'Spin' then
    ui.set(ref.yaw[1], 'Spin')
  elseif conf.yaw_mode:get() == 'Spin' then
    ui.set(ref.yaw[1], 'Spin')
  else
    ui.set(ref.yaw[1], '180')
  end

  local act_vulnerable = conf.def_activation:get('Vulnerable (scoped enemy)') and players_vulnerable()
  local act_charged = conf.def_activation:get('Charged DT') and doubletap_charged()
  local act_peek = conf.def_activation:get('On Peek') and toggle_def_gate
  local act_threat_shot = (_G.__scooby_threat_window > globals.curtime()) and conf.def_activation:get('Threat Shot')
  local defensive_now = conf.def_enable:get() and (act_vulnerable or act_charged or act_peek or act_threat_shot or conf.force_def:get() or (conf.peek_def:get() and toggle_def_gate))
  cmd.force_defensive = defensive_now

  local desync_type = (entity.get_prop(lp, 'm_flPoseParameter', 11) or 0) * 120 - 60
  local desync_side = desync_type > 0

  if is_defensive_active(lp) and conf.def_enable:get() and conf.def_type:get() == 'Default' then
    local mode = conf.def_yaw_mode:get()
    if mode == 'Spin' then yaw_amount = conf.yaw_value:get()
    elseif mode == 'Meta' then yaw_amount = desync_side and 90 or -90
    elseif mode == 'Random' then yaw_amount = math.random(-180, 180)
    else yaw_amount = desync_side and (conf.yaw_left:get() + (conf.yaw_left:get() * conf.yaw_random:get()/100) * (math.random() - 0.5) * 2)
                  or (conf.yaw_right:get() + (conf.yaw_right:get() * conf.yaw_random:get()/100) * (math.random() - 0.5) * 2) end
  elseif not selected_builder_def then
    local mode = conf.yaw_mode:get()
    if mode == 'Freestand' then ui.set(ref.freestand[1], true); yaw_amount = 0
    elseif mode == 'Manual' and yaw_direction ~= 0 then yaw_amount = yaw_direction
    else yaw_amount = desync_side and (conf.yaw_left:get() + (conf.yaw_left:get() * conf.yaw_random:get()/100) * (math.random() - 0.5) * 2)
                or (conf.yaw_right:get() + (conf.yaw_right:get() * conf.yaw_random:get()/100) * (math.random() - 0.5) * 2) end
    ui.set(ref.pitch[2], 89)
  end

  if defensive_now then
    local def_seq_mode = conf.def_pitch_seq_mode:get()
    local def_seq_vals = nil
    if def_seq_mode == '3-way' then def_seq_vals = {conf.def_p3_1:get(), conf.def_p3_2:get(), conf.def_p3_3:get()} end
    if def_seq_mode == '5-way' then def_seq_vals = {conf.def_p5_1:get(), conf.def_p5_2:get(), conf.def_p5_3:get(), conf.def_p5_4:get(), conf.def_p5_5:get()} end
    apply_pitch(conf.def_pitch_mode:get(), conf.def_pitch_value:get(), desync_side, def_seq_mode, def_seq_vals)
  else
    local seq_mode = conf.pitch_seq_mode:get()
    local seq_vals = nil
    if seq_mode == '3-way' then seq_vals = {conf.p3_1:get(), conf.p3_2:get(), conf.p3_3:get()} end
    if seq_mode == '5-way' then seq_vals = {conf.p5_1:get(), conf.p5_2:get(), conf.p5_3:get(), conf.p5_4:get(), conf.p5_5:get()} end
    apply_pitch(conf.pitch_mode:get(), conf.pitch_value:get(), desync_side, seq_mode, seq_vals)
  end

  ui.set(ref.yaw[2], yaw_direction == 0 and yaw_amount or yaw_direction)

  -- Warmup AA
  if menu.aa.helpers:get('Warmup AA') and entity.get_prop(entity.get_game_rules(), 'm_bWarmupPeriod') == 1 then
    ui.set(ref.yaw[2], math.random(-180, 180))
    ui.set(ref.yawjitter[2], math.random(-180, 180))
    ui.set(ref.bodyyaw[2], math.random(-180, 180))
    ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], math.random(-89, 89))
  end

  -- Safe Head
  if menu.aa.helpers:get('Safe Head') then
    local lp_weapon = entity.get_player_weapon(lp)
    if lp_weapon then
      local flags = entity.get_prop(lp, 'm_fFlags') or 0
      local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
      local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7
      if menu.aa.safe_head_opts:get('Air+C Knife') and jumping and ducked and entity.get_classname(lp_weapon) == 'CKnife' then set_safe_head_defaults() end
      if menu.aa.safe_head_opts:get('Air+C Zeus') and jumping and ducked and entity.get_classname(lp_weapon) == 'CWeaponTaser' then set_safe_head_defaults() end
      if menu.aa.safe_head_opts:get('High Distance') then
        local t = client.current_threat(); if t then
          local lx,ly,lz = entity.get_prop(lp,'m_vecOrigin'); local tx,ty,tz = entity.get_prop(t,'m_vecOrigin')
          if lx and tx then local d = math.sqrt((tx-lx)^2 + (ty-ly)^2 + (tz-lz)^2); if d > 900 then set_safe_head_defaults() end end
        end
      end
    end
  end

  -- Anti-Knife
  if menu.aa.helpers:get('Anti-Knife') then
    local lx,ly,lz = entity.get_prop(lp,'m_vecOrigin')
    for _, enemy in ipairs(entity.get_players(true)) do
      local w = entity.get_player_weapon(enemy)
      if w then
        local ex,ey,ez = entity.get_prop(enemy,'m_vecOrigin')
        if ex then
          local dist = math.sqrt((ex-lx)^2 + (ey-ly)^2 + (ez-lz)^2)
          if entity.get_classname(w) == 'CKnife' and dist <= 250 then
            ui.set(ref.yaw[2], 180); ui.set(ref.yawbase, 'At targets')
          end
        end
      end
    end
  end
end

-- ========= Visuals & Logs =========
local logs = {}
local function push_log(text, kind)
  table.insert(logs, { text, 0, ((globals.curtime() / 2) * 2.0), kind })
  while #logs > 50 do table.remove(logs, 1) end
end

local function ragebot_logs()
  if not menu.misc.logs:get() then return end
  local x, y = cx, screen_h / 1.4
  local offset = 0
  for idx, data in ipairs(logs) do
    if (((globals.curtime()/2) * 2.0) - data[3]) < 4.0 and not (#logs > 5 and idx < #logs - 5) then data[2] = math.lerp(data[2], 255, 10) else data[2] = math.lerp(data[2], 0, 10) end
    offset = offset - 40 * (data[2] / 255)
    local tsx = renderer.measure_text('', data[1])
    if menu.misc.logs_screen_style:get() == 'Default' then
      renderer.rectangle(x - 7 - tsx/2, y - offset - 8, tsx + 13, 26, 0, 0, 0, (data[2] / 255) * 150)
      renderer.rectangle(x - 6 - tsx/2, y - offset - 7, tsx + 11, 24, 50, 50, 50, (data[2] / 255) * 255)
      renderer.rectangle(x - 4 - tsx/2, y - offset - 4, tsx + 7, 18, 80, 80, 80, (data[2] / 255) * 255)
      renderer.rectangle(x - 3 - tsx/2, y - offset - 3, tsx + 5, 16, 20, 20, 20, (data[2] / 255) * 200)
    else
      renderer.rectangle(x - 7 - tsx/2, y - offset - 5, tsx + 13, 2, 145, 90, 150, data[2])
      renderer.rectangle(x - 7 - tsx/2, y - offset - 5, tsx + 13, 20, 0, 0, 0, (data[2] / 255) * 50)
    end
    local cr,cg,cb = 255,255,255; if data[4] == 'miss' then cr,cg,cb = 255,64,64 end; if data[4] == 'hit' then cr,cg,cb = 180,255,180 end
    renderer.text(x - 1 - tsx/2, y - offset, cr, cg, cb, data[2], '', 0, data[1])
  end
  for i = #logs, 1, -1 do local d = logs[i]; if d[2] < 0.1 or not entity.get_local_player() then table.remove(logs, i) end end
end

local scoped_space, main_font, key_font = 0, 'c-b', 'c'
local function text_fade_animation(x, y, speed, color1, color2, text, flag)
  local final_text = ''
  local ct = globals.curtime()
  for i = 0, #text do
    local ix = i * 10
    local wave = math.cos(8 * speed * ct + ix / 30)
    local color = rgba_to_hex( lerp(color1.r, color2.r, clamp(wave, 0, 1)), lerp(color1.g, color2.g, clamp(wave, 0, 1)), lerp(color1.b, color2.b, clamp(wave, 0, 1)), color1.a )
    final_text = final_text .. '\a' .. color .. text:sub(i, i)
  end
  renderer.text(x, y, color1.r, color1.g, color1.b, color1.a, flag, nil, final_text)
end

local function doubletap_ready() return doubletap_charged() end

local function screen_indicator()
  if not menu.visuals.cross_ind:get() then return end
  local lp = entity.get_local_player(); if not lp then return end
  local scpd = entity.get_prop(lp, 'm_bIsScoped') == 1
  scoped_space = math.lerp(scoped_space, scpd and 50 or 0, 20)
  local cond = (function(idx)
    if idx == 1 then return 'global' elseif idx == 2 then return 'stand' elseif idx == 3 then return 'walk' elseif idx == 4 then return 'run' elseif idx == 5 or idx == 6 then return 'air' elseif idx == 7 or idx == 8 then return 'crouch' end return 'global' end)(cond_idx)
  if menu.visuals.cross_style:get() == 'Default' then main_font = 'c-b'; key_font = 'c'
  elseif menu.visuals.cross_style:get() == 'Modern' then main_font = 'c-b'; key_font = 'c-b'
  elseif menu.visuals.cross_style:get() == 'Alternative' then main_font = 'c'; key_font = 'c'
  else main_font = 'c-d'; key_font = 'c-d' end
  local newest = menu.visuals.cross_style:get() == 'Newest'
  menu.visuals.cross_color:override(true); menu.visuals.key_color:override(true)
  local r1,g1,b1 = menu.visuals.cross_ind:get_color(); local r2,g2,b2 = menu.visuals.cross_color:get_color(); local r3,g3,b3 = menu.visuals.key_color:get_color()
  text_fade_animation(cx + scoped_space, cy + 30, -1, {r=r1,g=g1,b=b1,a=255}, {r=r2,g=g2,b=b2,a=255}, newest and string.upper('scooby.cc') or 'scooby.cc', main_font)
  renderer.text(cx + scoped_space, cy + 40, r2, g2, b2, 255, main_font, 0, cond)

  local offset = 10
  if ui.get(ref.forcebaim) then renderer.text(cx + scoped_space, cy + 40 + offset, 255, 102, 117, 255, key_font, 0, newest and 'BODY' or 'body'); offset = offset + 10 end
  if ui.get(ref.os[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, newest and 'OnShot' or 'onshot'); offset = offset + 10 end
  if ui.get(ref.min_dmg_override[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, newest and 'DMG' or 'dmg'); offset = offset + 10 end
  if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) then
    if doubletap_ready() then renderer.text(cx + scoped_space, cy + 40 + offset, r3,g3,b3,255, key_font, 0, newest and 'DT' or 'dt')
    else renderer.text(cx + scoped_space, cy + 40 + offset, 255,0,0,255, key_font, 0, newest and 'DT' or 'dt') end
    offset = offset + 10
  end
  if ui.get(ref.freestand[1]) and ui.get(ref.freestand[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3,g3,b3,255, key_font, 0, newest and 'FS' or 'fs'); offset = offset + 10 end

  -- manual arrows
  if menu.visuals.manual_arrows:get() and menu.aa.yaw_direction_modes:get('Manual') then
    local ar_r,ar_g,ar_b = menu.visuals.manual_arrows:get_color(); local size = menu.visuals.manual_arrow_size:get(); local dist = menu.visuals.manual_arrow_offset:get()
    if yaw_direction == -90 then renderer.triangle(cx - dist, cy, cx - dist + size, cy - size/2, cx - dist + size, cy + size/2, ar_r, ar_g, ar_b, 200) end
    if yaw_direction == 90 then renderer.triangle(cx + dist, cy, cx + dist - size, cy - size/2, cx + dist - size, cy + size/2, ar_r, ar_g, ar_b, 200) end
    if yaw_direction == 180 then renderer.triangle(cx, cy - dist, cx - size/2, cy - dist + size, cx + size/2, cy - dist + size, ar_r, ar_g, ar_b, 200) end
  end
end

local defensive_alpha, defensive_amount, velocity_alpha, velocity_amount = 0,0,0,0
local function velocity_ind()
  if not menu.visuals.velocity_window:get() then return end
  local lp = entity.get_local_player(); if not lp then return end
  local r,g,b = menu.visuals.velocity_window:get_color()
  local vel_mod = entity.get_prop(lp, 'm_flVelocityModifier') or 1
  if not ui.is_menu_open() then velocity_alpha = math.lerp(velocity_alpha, vel_mod < 1 and 255 or 0, 10); velocity_amount = math.lerp(velocity_amount, vel_mod, 10)
  else velocity_alpha = math.lerp(velocity_alpha, 255, 10); velocity_amount = globals.tickcount() % 50 / 100 * 2 end
  renderer.text(cx, screen_h/3 - 10, 255,255,255, velocity_alpha, 'c', 0, '- speed -')
  if menu.visuals.velocity_style:get() == 'Default' then
    renderer.rectangle(cx-50, screen_h/3, 100, 5, 0,0,0, velocity_alpha)
    renderer.rectangle(cx-49, screen_h/3+1, (100*velocity_amount)-1, 3, r,g,b, velocity_alpha)
  else
    renderer.gradient(cx - (50 * velocity_amount), screen_h/3, 1 + 50*velocity_amount, 2, r,g,b, velocity_alpha/3, r,g,b, velocity_alpha, true)
    renderer.gradient(cx, screen_h/3, 50*velocity_amount, 2, r,g,b, velocity_alpha, r,g,b, velocity_alpha/3, true)
  end
end

local function defensive_ind()
  if not menu.visuals.defensive_window:get() then return end
  local lp = entity.get_local_player(); if not lp then return end
  local charged = doubletap_charged(); local active = is_defensive_active(lp)
  local r,g,b = menu.visuals.defensive_window:get_color()
  if not ui.is_menu_open() then
    if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) and not ui.get(ref.fakeduck) then
      if charged and active then defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = math.lerp(defensive_amount, 1, 10)
      elseif charged and not active then defensive_alpha = math.lerp(defensive_alpha, 0, 10); defensive_amount = math.lerp(defensive_amount, 0.5, 10)
      else defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = math.lerp(defensive_amount, 0, 10) end
    else defensive_alpha = math.lerp(defensive_alpha, 0, 10); defensive_amount = math.lerp(defensive_amount, 0, 10) end
  else defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = globals.tickcount() % 50 / 100 * 2 end
  renderer.text(cx, screen_h/4 - 10, 255,255,255, defensive_alpha, 'c', 0, '- defense -')
  if menu.visuals.defensive_style:get() == 'Default' then
    renderer.rectangle(cx-50, screen_h/4, 100, 5, 0,0,0, defensive_alpha)
    renderer.rectangle(cx-49, screen_h/4+1, (100*defensive_amount)-1, 3, r,g,b, defensive_alpha)
  else
    renderer.gradient(cx - (50 * defensive_amount), screen_h/4, 1 + 50*defensive_amount, 2, r,g,b, defensive_alpha/3, r,g,b, defensive_alpha, true)
    renderer.gradient(cx, screen_h/4, 50*defensive_amount, 2, r,g,b, defensive_alpha, r,g,b, defensive_alpha/3, true)
  end
end

local function info_panel()
  if not menu.visuals.info_panel:get() then return end
  local lp = entity.get_local_player(); if not lp then return end
  local function condstr(idx) if idx==1 then return 'global' elseif idx==2 then return 'stand' elseif idx==3 then return 'walk' elseif idx==4 then return 'run' elseif idx==5 or idx==6 then return 'air' elseif idx==7 or idx==8 then return 'crouch' end return 'global' end
  local threat = client.current_threat(); local name='nil'; local tdes=0
  if threat then name = entity.get_player_name(threat); tdes = math.floor((entity.get_prop(threat, 'm_flPoseParameter', 11) or 0) * 120 - 60) end
  name = name:sub(1,12)
  local des = math.floor((entity.get_prop(lp, 'm_flPoseParameter', 11) or 0) * 120 - 60)
  text_fade_animation(20, cy, -1, {r=200,g=200,b=200,a=255}, {r=150,g=150,b=150,a=255}, 'Scooby.cc', 'd')
  local ts = renderer.measure_text('d', 'Scooby.cc')
  renderer.gradient(20, cy+15, ts/2, 2, 255,255,255,50, 255,255,255,255, true)
  renderer.gradient(20+ts/2, cy+15, ts/2, 2, 255,255,255,255, 255,255,255,50, true)
  renderer.text(20, cy+20, 255,255,255,255, 'd', 0, 'state: ' .. condstr(cond_idx) .. ' ' .. math.abs(des) .. '°')
  renderer.text(20, cy+30, 255,255,255,255, 'd', 0, 'target: ' .. string.lower(name) .. ' ' .. math.abs(tdes) .. '°')
  if menu.misc.resolver:get() then renderer.text(20, cy+40, 255,255,255,255, 'd', 0, 'resolver: ' .. string.lower(menu.misc.resolver_type:get())) end
end

-- ========= Animation Breakers =========
local function animation_breakers()
  local lp = entity.get_local_player(); if not lp or not entity.is_alive(lp) then return end
  local idx = c_entity.new(lp); local anim_state = idx:get_anim_state(); if not anim_state then return end
  local overlay = idx:get_anim_overlay(12); if not overlay then return end
  local xvel = entity.get_prop(lp, 'm_vecVelocity[0]') or 0; if math.abs(xvel) >= 3 then overlay.weight = 1 end
  if menu.misc.animation_ground:get() == 'Static' then entity.set_prop(lp, 'm_flPoseParameter', menu.misc.animation_amount:get()/10, 0)
  elseif menu.misc.animation_ground:get() == 'Jitter' then entity.set_prop(lp, 'm_flPoseParameter', globals.tickcount() % 4 > 1 and menu.misc.animation_amount:get()/10 or 0, 0)
  else entity.set_prop(lp, 'm_flPoseParameter', math.random(menu.misc.animation_amount:get(), 10)/10, 0) end
  if menu.misc.animation_air:get() == 'Static' then entity.set_prop(lp, 'm_flPoseParameter', 1, 6)
  elseif menu.misc.animation_air:get() == 'Randomize' then entity.set_prop(lp, 'm_flPoseParameter', math.random(0,10)/10, 6) end
end

-- ========= Movement/Misc =========
local function fast_ladder(e)
  local lp = entity.get_local_player(); if entity.get_prop(lp, 'm_MoveType') ~= 9 then return end
  local pitch = select(1, client.camera_angles())
  e.yaw = math.floor(e.yaw + 0.5); e.roll = 0
  if e.forwardmove == 0 then if e.sidemove ~= 0 then e.pitch = 89; e.yaw = e.yaw + 180; if e.sidemove < 0 then e.in_moveleft = 0; e.in_moveright = 1 end; if e.sidemove > 0 then e.in_moveleft = 1; e.in_moveright = 0 end end end
  if e.forwardmove > 0 then if pitch < 45 then e.pitch = 89; e.in_moveright = 1; e.in_moveleft = 0; e.in_forward = 0; e.in_back = 1; if e.sidemove == 0 then e.yaw = e.yaw + 90 end; if e.sidemove < 0 then e.yaw = e.yaw + 150 end; if e.sidemove > 0 then e.yaw = e.yaw + 30 end end end
  if e.forwardmove < 0 then e.pitch = 89; e.in_moveleft = 1; e.in_moveright = 0; e.in_forward = 1; e.in_back = 0; if e.sidemove == 0 then e.yaw = e.yaw + 90 end; if e.sidemove > 0 then e.yaw = e.yaw + 150 end; if e.sidemove < 0 then e.yaw = e.yaw + 30 end end
end

local function thirdperson(value) if value ~= nil then cvar.cam_idealdist:set_int(value) end end
local function aspectratio(value) if value then cvar.r_aspectratio:set_float(value) end end

local function auto_tp(cmd)
  local lp = entity.get_local_player(); if not lp then return end
  local flags = entity.get_prop(lp, 'm_fFlags') or 0; local jumping = bit.band(flags, 1) == 0
  if players_vulnerable() and jumping then cmd.force_defensive = true; cmd.discharge_pending = true end
end

-- ========= Resolver =========
local expres = { body_yaw = {}, eye_angles = {} }
local function get_prev_simtime(ent)
  local ptr = native_GetClientEntity(ent); if ptr ~= nil then return ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0] end
end
local function resolver_restore() for i = 1, 64 do plist.set(i, 'Force body yaw', false) end end
local function get_max_desync(animstate)
  local speedfactor = clamp(animstate.feet_speed_forwards_or_sideways, 0, 1)
  local avg_speedfactor = (animstate.stop_to_full_running_fraction * -0.3 - 0.2) * speedfactor + 1
  local duck_amount = animstate.duck_amount; if duck_amount > 0 then avg_speedfactor = avg_speedfactor + (duck_amount * speedfactor * (0.5 - avg_speedfactor)) end
  return clamp(avg_speedfactor, .5, 1)
end
local function resolver_handle(threat)
  if not threat or not entity.is_alive(threat) or entity.is_dormant(threat) then resolver_restore(); return end
  expres.body_yaw[threat] = expres.body_yaw[threat] or {}; expres.eye_angles[threat] = expres.eye_angles[threat] or {}
  local simtime = toticks(entity.get_prop(threat, 'm_flSimulationTime'))
  local prev_simtime = toticks(get_prev_simtime(threat))
  expres.body_yaw[threat][simtime] = (entity.get_prop(threat, 'm_flPoseParameter', 11) or 0) * 120 - 60
  expres.eye_angles[threat][simtime] = select(2, entity.get_prop(threat, 'm_angEyeAngles'))
  if expres.body_yaw[threat][prev_simtime] ~= nil then
    local ent = c_entity.new(threat); local animstate = ent:get_anim_state(); if not animstate then return end
    local max_desync = get_max_desync(animstate)
    local Pitch = entity.get_prop(threat, 'm_angEyeAngles[0]') or 0
    local pitch_e = Pitch > -30 and Pitch < 49
    local resolver_kind = menu.misc.resolver_type:get()
    if resolver_kind == 'Stable' then
      local prev = expres.body_yaw[threat][prev_simtime] or 0
      local curr = expres.body_yaw[threat][simtime] or 0
      local delta = curr - prev
      local correction = clamp(delta, -35, 35)
      if pitch_e then correction = 0 end
      plist.set(threat, 'Force body yaw', true); plist.set(threat, 'Force body yaw value', correction)
    else -- Adaptive
      local strength = menu.misc.resolver_adaptive_strength:get() / 100
      local side = globals.tickcount() % 4 > 1 and 1 or -1
      local base = side * (max_desync * 58 * strength)
      if pitch_e or not is_defensive_resolver(threat) then base = base * 0.25 end
      plist.set(threat, 'Force body yaw', true); plist.set(threat, 'Force body yaw value', base)
    end
  end
  plist.set(threat, 'Correction active', true)
end
local function resolver_update() local ents = entity.get_players(true); if not ents then return end; for i=1,#ents do resolver_handle(ents[i]) end end

-- ========= Spammers/Clantag =========
local phrases = {
  '♛ scooby.cc – refined pastesis', 'crafted by scooby ♛', 'builder flows, scooby shows', 'resolving despair since forever', 'peak clean, peak stable',
}
local function on_player_death(e)
  if not menu.misc.spammers:get('TrashTalk') then return end
  if not menu.main.header:get() then return end
  local v = e.userid; local a = e.attacker; if not v or not a then return end
  local victim = client.userid_to_entindex(v); local attacker = client.userid_to_entindex(a)
  if attacker == entity.get_local_player() and entity.is_enemy(victim) then client.delay_call(2, function() client.exec('say ', phrases[math.random(1, #phrases)]) end) end
end

local clantag_last_ms, clantag_phase = 0, 1
local function update_clantag()
  local enabled = menu.misc.spammers:get('Clantag') and menu.misc.clantag_enable:get()
  local style = menu.misc.clantag_style:get()
  local speed_ms = menu.misc.clantag_speed:get()
  local tag_text = menu.misc.clantag_preset:get()
  if tag_text == 'scooby.cc ♛' then tag_text = 'scooby.cc ♛' end
  if tag_text == 'pastesis' then tag_text = 'pastesis' end
  if tag_text == 'gamesense' then tag_text = 'gamesense' end
  if tag_text == 'crowned' then tag_text = '♛ crowned ♛' end
  if not enabled or style == 'Off' then ui.set(ref.clantag, false); client.set_clan_tag(''); return end
  ui.set(ref.clantag, false)
  local now = globals.realtime() * 1000; if now - clantag_last_ms < speed_ms then return end; clantag_last_ms = now
  local out = tag_text
  if style == 'Classic' then
    local frames = {}; for i=1,#tag_text do frames[i] = tag_text:sub(1,i) end; for i=#tag_text-1,1,-1 do frames[#frames+1] = tag_text:sub(1,i) end
    clantag_phase = (clantag_phase % #frames) + 1; out = frames[clantag_phase]
  elseif style == 'Wave' then
    local crown = '♛'; clantag_phase = (clantag_phase % (#tag_text+2)) + 1; local idx = clantag_phase
    local before = tag_text:sub(1, math.max(0, idx-1)); local after = tag_text:sub(idx+1); out = before .. crown .. tag_text:sub(idx, idx) .. crown .. after
  elseif style == 'Typewriter' then clantag_phase = (clantag_phase % (#tag_text+1)) + 1; out = tag_text:sub(1, clantag_phase)
  elseif style == 'Crown' then local crowns = {'♛','♚','♔','♕'}; clantag_phase = (clantag_phase % #crowns) + 1; out = crowns[clantag_phase] .. ' ' .. tag_text .. ' ' .. crowns[clantag_phase] end
  client.set_clan_tag(out)
end

-- ========= Events =========
safe_callback('bullet_impact', function(e)
  if not entity.is_alive(entity.get_local_player()) then return end
  local ent = client.userid_to_entindex(e.userid)
  if ent ~= client.current_threat() then return end
  if entity.is_dormant(ent) or not entity.is_enemy(ent) then return end
  local A = { entity.get_prop(ent, 'm_vecOrigin') }; A[3] = A[3] + (entity.get_prop(ent, 'm_vecViewOffset[2]') or 0)
  local B = { e.x, e.y, e.z }
  local P = { entity.hitbox_position(entity.get_local_player(), 0) }
  local a_to_p = { P[1]-A[1], P[2]-A[2] }; local a_to_b = { B[1]-A[1], B[2]-A[2] }
  local atb2 = a_to_b[1]^2 + a_to_b[2]^2; if atb2 == 0 then return end
  local t = (a_to_p[1]*a_to_b[1] + a_to_p[2]*a_to_b[2]) / atb2
  local closest = { A[1] + a_to_b[1]*t, A[2] + a_to_b[2]*t }
  local dx,dy = P[1]-closest[1], P[2]-closest[2]
  local delta_2d = math.sqrt(dx*dx + dy*dy)
  if math.abs(delta_2d) <= 60 then _G.__scooby_threat_window = globals.curtime() + 0.35; if menu.misc.logs:get() and menu.misc.logs_type:get('Screen') then push_log(entity.get_player_name(ent) .. ' Shot At You') end end
end)

safe_callback('aim_hit', function(e)
  if not menu.misc.logs:get() then return end
  local names = {'generic','head','chest','stomach','left arm','right arm','left leg','right leg','neck','?','gear'}
  local group = names[(e.hitgroup or 0) + 1] or '?'
  if menu.misc.logs_type:get('Screen') then push_log(string.format('Hit %s in the %s for %d', entity.get_player_name(e.target), group, e.damage), 'hit') end
  if menu.misc.logs_type:get('Console') then if not menu.misc.console_filter:get() then print(string.format('Hit %s in the %s for %d damage', entity.get_player_name(e.target), group, e.damage)) end end
end)

safe_callback('aim_miss', function(e)
  if not menu.misc.logs:get() then return end
  local names = {'generic','head','chest','stomach','left arm','right arm','left leg','right leg','neck','?','gear'}
  local group = names[(e.hitgroup or 0) + 1] or '?'
  if menu.misc.logs_type:get('Screen') then push_log(string.format('Missed %s in the %s (%s)', entity.get_player_name(e.target), group, e.reason), 'miss') end
  if menu.misc.logs_type:get('Console') then if not menu.misc.console_filter:get() then print(string.format('Missed %s in the %s due to %s', entity.get_player_name(e.target), group, e.reason)) end end
end)

menu.misc.resolver:set_callback(function(self) if not self:get() then resolver_restore() end end, true)
safe_callback('player_death', on_player_death)

safe_callback('setup_command', function(cmd)
  if not menu.main.header:get() then return end
  aa_apply(cmd)
  if menu.misc.revolver_helper:get() then
    local lp = entity.get_local_player(); if lp and entity.is_alive(lp) then
      local w = entity.get_player_weapon(lp)
      if w and entity.get_classname(w) == 'CWeaponRevolver' then
        local next_primary_attack = entity.get_prop(w, 'm_flNextPrimaryAttack') or 0
        local ready = (next_primary_attack - globals.curtime()) <= 0
        local hold_ticks = menu.misc.revolver_hold_ticks:get()
        local early_pct = menu.misc.revolver_delay:get() / 100
        if not ready then cmd.in_attack = 1 else local ticks_left = toticks(next_primary_attack - globals.curtime()); if ticks_left <= math.max(1, math.floor(hold_ticks * (1 - early_pct))) then cmd.in_attack = 1 end end
      end
    end
  end
  if menu.misc.fast_ladder:get() then fast_ladder(cmd) end
  if menu.misc.teleport:get() and menu.misc.teleport_key:get() then auto_tp(cmd) end
  if menu.misc.resolver:get() then resolver_update() end
end)

safe_callback('pre_render', function()
  if not menu.main.header:get() then return end
  if menu.misc.animation:get() then animation_breakers() end
end)

safe_callback('paint_ui', function() hide_original_menu(false) end)

safe_callback('paint', function()
  if not menu.main.header:get() then return end
  update_clantag()
  if not entity.is_alive(entity.get_local_player()) then return end
  screen_indicator()
  thirdperson(menu.misc.third_person:get() and menu.misc.third_person_value:get() or nil)
  aspectratio(menu.misc.aspectratio:get() and (menu.misc.aspectratio_value:get()/100) or nil)
  velocity_ind(); defensive_ind(); ragebot_logs(); info_panel()
  text_fade_animation(screen_w/2, screen_h-20, -1, {r=200,g=200,b=200,a=255}, {r=150,g=150,b=150,a=255}, 'SCOOBY.CC', 'cdb')
end)

safe_callback('round_prestart', function()
  logs = {}
  if menu.misc.logs:get() and menu.misc.logs_type:get('Screen') then push_log('Anti-Aim Data Resetted') end
end)

safe_callback('shutdown', function()
  hide_original_menu(true)
  thirdperson(150)
  aspectratio(0)
  resolver_restore()
end)

-- KY-yaw
-- Modern, readable, and fast anti-aim builder for gamesense
-- Focused on clarity, responsiveness, and a clean UI

local ok_json, json = pcall(require, 'json')
local ok_ffi, ffi = pcall(require, 'ffi')
local ok_ent, c_entity = pcall(require, 'gamesense/entity')
local ok_pui, pui = pcall(require, 'gamesense/pui')
local ok_b64, base64 = pcall(require, 'gamesense/base64')
local ok_clip, clipboard = pcall(require, 'gamesense/clipboard')

-- ========= Utilities =========
local function clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function toticks(seconds)
  return math.floor(0.5 + (seconds / globals.tickinterval()))
end

local function rgba_hex(r, g, b, a)
  return string.format('%02x%02x%02x%02x', r, g, b, a)
end

local function safe_callback(event_name, fn)
  client.set_event_callback(event_name, function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      print(string.format('[KY-yaw] %s error: %s', tostring(event_name), tostring(err)))
    end
  end)
end

-- ========= Engine/UI refs =========
local function ref1(a, b, c)
  local ok, v = pcall(ui.reference, a, b, c)
  if ok then return v end
  return nil
end

local function refN(a, b, c)
  local ok, v1, v2 = pcall(ui.reference, a, b, c)
  if ok then return { v1, v2 } end
  return { nil, nil }
end

local ref = {
  enabled = ref1('AA', 'Anti-aimbot angles', 'Enabled'),
  yawbase = ref1('AA', 'Anti-aimbot angles', 'Yaw base'),
  fsbodyyaw = ref1('AA', 'Anti-aimbot angles', 'Freestanding body yaw'),
  edgeyaw = ref1('AA', 'Anti-aimbot angles', 'Edge yaw'),
  roll = ref1('AA', 'Anti-aimbot angles', 'Roll'),
  pitch = refN('AA', 'Anti-aimbot angles', 'Pitch'),
  yaw = refN('AA', 'Anti-aimbot angles', 'Yaw'),
  yawjitter = refN('AA', 'Anti-aimbot angles', 'Yaw jitter'),
  bodyyaw = refN('AA', 'Anti-aimbot angles', 'Body yaw'),
  freestand = refN('AA', 'Anti-aimbot angles', 'Freestanding'),
  slow = refN('AA', 'Other', 'Slow motion'),
  os = refN('AA', 'Other', 'On shot anti-aim'),
  fakeduck = ref1('RAGE', 'Other', 'Duck peek assist'),
  dt = refN('RAGE', 'Aimbot', 'Double tap'),
  forcebaim = ref1('RAGE', 'Aimbot', 'Force body aim'),
  safepoint = ref1('RAGE', 'Aimbot', 'Force safe point'),
  min_dmg_override = refN('RAGE', 'Aimbot', 'Minimum damage override'),
  clantag = ref1('Misc', 'Miscellaneous', 'Clan tag spammer'),
}

-- ========= UI =========
local use_pui = ok_pui and type(pui) == 'table'
if use_pui then pui.accent = 'C3F33CFF' end

local cond_full = { 'Global','Stand','Walking','Running','Air','Air+','Duck','Duck+Move' }
local cond_short = { 'G','S','W','R','A','A+','D','D+' }

local menu = {}
local builder = {}

if use_pui then
  -- PUI groups
  local group_main = pui.group('aa', 'anti-aimbot angles')
  local group_visuals = pui.group('aa', 'other')
  local group_misc = pui.group('aa', 'other')
  local group_cfg = pui.group('aa', 'fake lag')

  menu.header = group_main:label('KY-yaw')
  menu.tab = group_main:combobox('Tab', { 'Anti-Aim', 'Visuals', 'Misc', 'Config' })
  menu.subtab = group_main:combobox('AA Subtab', { 'Main', 'Builder' })

  -- Main
  menu.helpers = group_main:multiselect('Helpers', { 'Warmup AA', 'Anti-Knife', 'Safe Head' })
  menu.safe_head_opts = group_main:multiselect('Safe Head When', { 'Air+C Knife','Air+C Zeus','Long Distance' })
  menu.dir_modes = group_main:multiselect('Yaw Direction', { 'Freestanding', 'Manual' })
  menu.hotkey_fs = group_main:hotkey('Freestanding Hotkey')
  menu.hotkey_left = group_main:hotkey('Manual Left')
  menu.hotkey_right = group_main:hotkey('Manual Right')
  menu.hotkey_forward = group_main:hotkey('Manual Forward')
  menu.yaw_base = group_main:combobox('Yaw Base', { 'Local view', 'At targets' })

  -- Visuals
  menu.cross_ind = group_visuals:checkbox('Crosshair Indicators', { 230, 230, 230 })
  menu.cross_style = group_visuals:combobox('Indicator Style', { 'Newest','Default','Modern','Alternative' })
  menu.cross_color = group_visuals:checkbox('Main Color', { 140, 140, 255 })
  menu.key_color = group_visuals:checkbox('Key Color', { 230, 230, 230 })
  menu.manual_arrows = group_visuals:checkbox('Manual Arrows', { 255, 255, 255 })
  menu.arrow_size = group_visuals:slider('Arrow Size', 6, 24, 12, true, 'px', 1)
  menu.arrow_offset = group_visuals:slider('Arrow Offset', 20, 100, 40, true, 'px', 1)
  menu.velocity_win = group_visuals:checkbox('Speed Meter', { 255, 255, 255 })
  menu.velocity_style = group_visuals:combobox('Speed Style', { 'Default', 'Modern' })
  menu.defensive_win = group_visuals:checkbox('Defense Meter', { 255, 255, 255 })
  menu.defensive_style = group_visuals:combobox('Defense Style', { 'Default', 'Modern' })
  menu.info_panel = group_visuals:checkbox('Info Panel')

  -- Misc
  menu.logs = group_misc:checkbox('Ragebot Logs')
  menu.logs_type = group_misc:multiselect('Log Types', { 'Console','Screen' })
  menu.logs_style = group_misc:combobox('Screen Log Style', { 'Default','Modern' })
  menu.animation = group_misc:checkbox('Animation Breakers')
  menu.anim_ground = group_misc:combobox('Ground Animation', { 'Static','Jitter','Randomize' })
  menu.anim_amount = group_misc:slider('Animation Value', 0, 10, 5)
  menu.anim_air = group_misc:combobox('Air Animation', { 'Off','Static','Randomize' })
  menu.third_person = group_misc:checkbox('Third Person Distance')
  menu.third_person_value = group_misc:slider('Third Person Distance (px)', 30, 200, 50)
  menu.aspectratio = group_misc:checkbox('Aspect Ratio')
  menu.aspectratio_value = group_misc:slider('Aspect Ratio (x100)', 0, 200, 133)
  menu.teleport = group_misc:checkbox('Break LC Teleport')
  menu.teleport_key = group_misc:hotkey('Teleport Hotkey', true)
  menu.resolver = group_misc:checkbox('Custom Resolver')
  menu.resolver_type = group_misc:combobox('Resolver Type', { 'Stable','Adaptive' })
  menu.resolver_strength = group_misc:slider('Adaptive Strength', 0, 100, 70, true, '%', 1)

  -- Config
  menu.cfg_title = group_cfg:label('Config')

  -- Builder per-condition
  for i = 1, #cond_full do
    local s = cond_short[i]
    builder[i] = {
      label = group_main:label('· ' .. cond_full[i]),
      enable = group_main:checkbox(s .. ' · Enable'),
      yaw_mode = group_main:combobox(s .. ' · Yaw Mode', { 'Default','Delay','Spin','Freestand','Manual' }),
      yaw_delay = group_main:slider(s .. ' · Delay Ticks', 1, 15, 4, true, 't', 1),
      yaw_left = group_main:slider(s .. ' · Yaw Left', -180, 180, 0, true, '°', 1),
      yaw_right = group_main:slider(s .. ' · Yaw Right', -180, 180, 0, true, '°', 1),
      yaw_random = group_main:slider(s .. ' · Randomization', 0, 100, 0, true, '%', 1),
      jitter_type = group_main:combobox(s .. ' · Jitter Type', { 'Off','Offset','Center','Random','3-way','5-way','7-way','9-way' }),
      jitter_amount = group_main:slider(s .. ' · Jitter Amount', -180, 180, 0, true, '°', 1),
      jitter_seq_mode = group_main:combobox(s .. ' · Jitter Sequence', { 'Automatic','Custom' }),
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
      body_type = group_main:combobox(s .. ' · Body Yaw', { 'Off','Opposite','Jitter','Static' }),
      body_amount = group_main:slider(s .. ' · Body Amount', -180, 180, 0, true, '°', 1),

      -- Pitch
      pitch_mode = group_main:combobox(s .. ' · Pitch', { 'Off','Custom','Meta','Random' }),
      pitch_value = group_main:slider(s .. ' · Pitch Value', -89, 89, 0, true, '°', 1),
      pitch_seq = group_main:combobox(s .. ' · Pitch Seq', { 'Off','3-way','5-way','Custom' }),
      p3_1 = group_main:slider(s .. ' · P 3-way A1', -89, 89, -45, true, '°', 1),
      p3_2 = group_main:slider(s .. ' · P 3-way A2', -89, 89, 0, true, '°', 1),
      p3_3 = group_main:slider(s .. ' · P 3-way A3', -89, 89, 45, true, '°', 1),
      p5_1 = group_main:slider(s .. ' · P 5-way A1', -89, 89, -89, true, '°', 1),
      p5_2 = group_main:slider(s .. ' · P 5-way A2', -89, 89, -45, true, '°', 1),
      p5_3 = group_main:slider(s .. ' · P 5-way A3', -89, 89, 0, true, '°', 1),
      p5_4 = group_main:slider(s .. ' · P 5-way A4', -89, 89, 45, true, '°', 1),
      p5_5 = group_main:slider(s .. ' · P 5-way A5', -89, 89, 89, true, '°', 1),

      -- Defensive
      def_enable = group_main:checkbox(s .. ' · Defensive'),
      def_when = group_main:multiselect(s .. ' · Defensive When', { 'Vulnerable','Charged DT','On Peek','Threat Shot' }),
      def_type = group_main:combobox(s .. ' · Defensive Type', { 'Default','Builder' }),
      def_yaw_mode = group_main:combobox(s .. ' · DEF Yaw', { 'Spin','Meta','Random' }),
      yaw_value = group_main:slider(s .. ' · Yaw Value', -180, 180, 0, true, '°', 1),
      def_yaw_value = group_main:slider(s .. ' · DEF Yaw Value', -180, 180, 9, true, '°', 1),
      def_jitter_type = group_main:combobox(s .. ' · DEF Jitter', { 'Off','Offset','Center','Random','3-way','5-way','7-way','9-way' }),
      def_jitter_amount = group_main:slider(s .. ' · DEF Jitter Amount', -180, 180, 50, true, '°', 1),
      def_pitch_mode = group_main:combobox(s .. ' · DEF Pitch', { 'Off','Custom','Meta','Random' }),
      def_pitch_value = group_main:slider(s .. ' · DEF Pitch Value', -89, 89, 0, true, '°', 1),
      def_pitch_seq = group_main:combobox(s .. ' · DEF Pitch Seq', { 'Off','3-way','5-way' }),
      def_body_type = group_main:combobox(s .. ' · DEF Body', { 'Off','Opposite','Jitter','Static' }),
      def_body_amount = group_main:slider(s .. ' · DEF Body Amount', -180, 180, 1, true, '°', 1),

      force_def = group_main:checkbox(s .. ' · Force Defensive'),
      peek_def = group_main:checkbox(s .. ' · Defensive Peek'),
    }
  end

  -- Visibility dependencies
  local tabs = {
    aa = { menu.tab, 'Anti-Aim' }, visuals = { menu.tab, 'Visuals' }, misc = { menu.tab, 'Misc' }, config = { menu.tab, 'Config' }
  }
  menu.subtab:depend(tabs.aa)
  menu.helpers:depend(tabs.aa)
  menu.safe_head_opts:depend(tabs.aa, { menu.helpers, 'Safe Head' })
  menu.dir_modes:depend(tabs.aa)
  menu.hotkey_fs:depend(tabs.aa, { menu.dir_modes, 'Freestanding' })
  menu.hotkey_left:depend(tabs.aa, { menu.dir_modes, 'Manual' })
  menu.hotkey_right:depend(tabs.aa, { menu.dir_modes, 'Manual' })
  menu.hotkey_forward:depend(tabs.aa, { menu.dir_modes, 'Manual' })
  menu.yaw_base:depend(tabs.aa)

  menu.cross_ind:depend(tabs.visuals)
  menu.cross_style:depend(tabs.visuals, { menu.cross_ind, true })
  menu.cross_color:depend(tabs.visuals, { menu.cross_ind, true })
  menu.key_color:depend(tabs.visuals, { menu.cross_ind, true })
  menu.manual_arrows:depend(tabs.visuals, { menu.cross_ind, true })
  menu.arrow_size:depend(tabs.visuals, { menu.manual_arrows, true })
  menu.arrow_offset:depend(tabs.visuals, { menu.manual_arrows, true })
  menu.velocity_win:depend(tabs.visuals)
  menu.velocity_style:depend(tabs.visuals, { menu.velocity_win, true })
  menu.defensive_win:depend(tabs.visuals)
  menu.defensive_style:depend(tabs.visuals, { menu.defensive_win, true })
  menu.info_panel:depend(tabs.visuals)

  menu.logs:depend(tabs.misc)
  menu.logs_type:depend(tabs.misc, { menu.logs, true })
  menu.logs_style:depend(tabs.misc, { menu.logs, true }, { menu.logs_type, 'Screen' })
  menu.animation:depend(tabs.misc)
  menu.anim_ground:depend(tabs.misc, { menu.animation, true })
  menu.anim_amount:depend(tabs.misc, { menu.animation, true })
  menu.anim_air:depend(tabs.misc, { menu.animation, true })
  menu.third_person:depend(tabs.misc)
  menu.third_person_value:depend(tabs.misc, { menu.third_person, true })
  menu.aspectratio:depend(tabs.misc)
  menu.aspectratio_value:depend(tabs.misc, { menu.aspectratio, true })
  menu.teleport:depend(tabs.misc)
  menu.teleport_key:depend(tabs.misc)
  menu.resolver:depend(tabs.misc)
  menu.resolver_type:depend(tabs.misc, { menu.resolver, true })
  menu.resolver_strength:depend(tabs.misc, { menu.resolver, true }, { menu.resolver_type, 'Adaptive' })

  for i = 1, #cond_full do
    local in_builder = { menu.subtab, 'Builder' }
    local cond_only = { menu.subtab, function() return menu.subtab:get() == 'Builder' end, function() return true end } -- placeholder
    local enabled_or_global = { builder[i].enable, function() return (i == 1) or builder[i].enable:get() end }

    builder[i].label:depend(tabs.aa, in_builder)
    builder[i].enable:depend(tabs.aa, in_builder)
    builder[i].yaw_mode:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].yaw_delay:depend(tabs.aa, in_builder, enabled_or_global, { builder[i].yaw_mode, 'Delay' })
    builder[i].yaw_left:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].yaw_right:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].yaw_random:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].jitter_type:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].jitter_amount:depend(tabs.aa, in_builder, enabled_or_global, { builder[i].jitter_type, function()
      local t = builder[i].jitter_type:get(); return t ~= 'Off' and t ~= 'Center' end })
    builder[i].jitter_seq_mode:depend(tabs.aa, in_builder, enabled_or_global, { builder[i].jitter_type, function()
      local t = builder[i].jitter_type:get(); return t == '3-way' or t == '5-way' or t == '7-way' or t == '9-way' end })

    builder[i].j3_1:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '3-way' })
    builder[i].j3_2:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '3-way' })
    builder[i].j3_3:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '3-way' })
    builder[i].j5_1:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '5-way' })
    builder[i].j5_2:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '5-way' })
    builder[i].j5_3:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '5-way' })
    builder[i].j5_4:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '5-way' })
    builder[i].j5_5:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '5-way' })
    builder[i].j7_1:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_2:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_3:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_4:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_5:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_6:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j7_7:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '7-way' })
    builder[i].j9_1:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_2:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_3:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_4:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_5:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_6:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_7:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_8:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })
    builder[i].j9_9:depend(tabs.aa, in_builder, { builder[i].jitter_seq_mode, 'Custom' }, { builder[i].jitter_type, '9-way' })

    builder[i].body_type:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].body_amount:depend(tabs.aa, in_builder, enabled_or_global, { builder[i].body_type, function() return builder[i].body_type:get() ~= 'Off' end })

    builder[i].pitch_mode:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].pitch_value:depend(tabs.aa, in_builder, enabled_or_global, { builder[i].pitch_mode, 'Custom' })
    builder[i].pitch_seq:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].p3_1:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '3-way' })
    builder[i].p3_2:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '3-way' })
    builder[i].p3_3:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '3-way' })
    builder[i].p5_1:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '5-way' })
    builder[i].p5_2:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '5-way' })
    builder[i].p5_3:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '5-way' })
    builder[i].p5_4:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '5-way' })
    builder[i].p5_5:depend(tabs.aa, in_builder, { builder[i].pitch_seq, '5-way' })

    builder[i].def_enable:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].def_when:depend(tabs.aa, in_builder, { builder[i].def_enable, true })
    builder[i].def_type:depend(tabs.aa, in_builder, { builder[i].def_enable, true })
    builder[i].def_yaw_mode:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Default' })
    builder[i].yaw_value:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].def_yaw_value:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Builder' })
    builder[i].def_jitter_type:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Builder' })
    builder[i].def_jitter_amount:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Builder' }, { builder[i].def_jitter_type, function()
      local t = builder[i].def_jitter_type:get(); return t ~= 'Off' and t ~= 'Center' end })
    builder[i].def_pitch_mode:depend(tabs.aa, in_builder, { builder[i].def_enable, true })
    builder[i].def_pitch_value:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_pitch_mode, 'Custom' })
    builder[i].def_pitch_seq:depend(tabs.aa, in_builder, { builder[i].def_enable, true })
    builder[i].def_body_type:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Builder' })
    builder[i].def_body_amount:depend(tabs.aa, in_builder, { builder[i].def_enable, true }, { builder[i].def_type, 'Builder' }, { builder[i].def_body_type, function() return builder[i].def_body_type:get() ~= 'Off' end })

    builder[i].force_def:depend(tabs.aa, in_builder, enabled_or_global)
    builder[i].peek_def:depend(tabs.aa, in_builder, { builder[i].force_def, false })
  end
else
  -- Fallback simple UI (native ui.*); compact and robust
  -- We keep one toggler to enable KY-yaw and minimal knobs when PUI is unavailable.
  menu.header = ui.new_checkbox('aa', 'anti-aimbot angles', 'KY-yaw')
  menu.yaw_base = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — Yaw base', 'Local view', 'At targets')
  menu.dir_modes = ui.new_multiselect('aa', 'anti-aimbot angles', 'KY-yaw — Yaw Direction', 'Freestanding', 'Manual')
  menu.hotkey_fs = ui.new_hotkey('aa', 'anti-aimbot angles', 'KY-yaw — Freestanding')
  menu.hotkey_left = ui.new_hotkey('aa', 'anti-aimbot angles', 'KY-yaw — Left')
  menu.hotkey_right = ui.new_hotkey('aa', 'anti-aimbot angles', 'KY-yaw — Right')
  menu.hotkey_forward = ui.new_hotkey('aa', 'anti-aimbot angles', 'KY-yaw — Forward')

  -- Minimal builder for Global
  builder[1] = {
    enable = ui.new_checkbox('aa', 'anti-aimbot angles', 'KY-yaw — Global enable'),
    yaw_mode = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — Global yaw', 'Default','Delay','Spin','Freestand','Manual'),
    yaw_delay = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Delay ticks', 1, 15, 4),
    yaw_left = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Left', -180, 180, 0),
    yaw_right = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Right', -180, 180, 0),
    yaw_random = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Random %', 0, 100, 0),
    jitter_type = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — Jitter', 'Off','Offset','Center','Random'),
    jitter_amount = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Jitter amount', -180, 180, 0),
    body_type = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — Body', 'Off','Opposite','Jitter','Static'),
    body_amount = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Body amount', -180, 180, 0),
    pitch_mode = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — Pitch', 'Off','Custom','Meta','Random'),
    pitch_value = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — Pitch value', -89, 89, 0),
    def_enable = ui.new_checkbox('aa', 'anti-aimbot angles', 'KY-yaw — Defensive'),
    def_yaw_mode = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — DEF yaw', 'Spin','Meta','Random'),
    def_body_type = ui.new_combobox('aa', 'anti-aimbot angles', 'KY-yaw — DEF Body', 'Off','Opposite','Jitter','Static'),
    def_body_amount = ui.new_slider('aa', 'anti-aimbot angles', 'KY-yaw — DEF Body amount', -180, 180, 1),
  }
end

-- ========= Config (PUI only) =========
local Package = nil
if use_pui then
  Package = pui.setup({ menu, builder })
  menu.export_btn = pui.group('aa', 'fake lag'):button('Export Config', function()
    if not (ok_b64 and ok_clip and ok_json) then print('[KY-yaw] Missing json/base64/clipboard libs') return end
    local data = Package:save()
    clipboard.set(base64.encode(json.stringify(data)))
    print('[KY-yaw] Exported')
  end)
  menu.import_btn = pui.group('aa', 'fake lag'):button('Import Config', function()
    if not (ok_b64 and ok_clip and ok_json) then print('[KY-yaw] Missing json/base64/clipboard libs') return end
    local txt = clipboard.get()
    local parsed = json.parse(base64.decode(txt))
    Package:load(parsed)
    print('[KY-yaw] Imported')
  end)
  menu.defaults_btn = pui.group('aa', 'fake lag'):button('Load Defaults', function()
    for i = 1, #cond_full do
      if builder[i].enable then builder[i].enable:set(i == 1) end
      if builder[i].yaw_mode then builder[i].yaw_mode:set('Default') end
      if builder[i].yaw_delay then builder[i].yaw_delay:set(4) end
      if builder[i].yaw_left then builder[i].yaw_left:set(9) end
      if builder[i].yaw_right then builder[i].yaw_right:set(9) end
      if builder[i].jitter_type then builder[i].jitter_type:set('Center') end
      if builder[i].body_type then builder[i].body_type:set('Jitter') end
      if builder[i].body_amount then builder[i].body_amount:set(1) end
      if builder[i].def_enable then builder[i].def_enable:set(true) end
      if builder[i].def_type then builder[i].def_type:set('Builder') end
      if builder[i].def_yaw_mode then builder[i].def_yaw_mode:set('Spin') end
      if builder[i].def_jitter_type then builder[i].def_jitter_type:set('Center') end
      if builder[i].def_jitter_amount then builder[i].def_jitter_amount:set(50) end
    end
  end)
end

-- ========= State/Helpers =========
local function hide_original_menu(visible)
  if ref.enabled then ui.set_visible(ref.enabled, visible) end
  if ref.pitch[1] then ui.set_visible(ref.pitch[1], visible) end
  if ref.pitch[2] then ui.set_visible(ref.pitch[2], visible) end
  if ref.yawbase then ui.set_visible(ref.yawbase, visible) end
  if ref.yaw[1] then ui.set_visible(ref.yaw[1], visible) end
  if ref.yaw[2] then ui.set_visible(ref.yaw[2], visible) end
  if ref.yawjitter[1] then ui.set_visible(ref.yawjitter[1], visible) end
  if ref.yawjitter[2] then ui.set_visible(ref.yawjitter[2], visible) end
  if ref.bodyyaw[1] then ui.set_visible(ref.bodyyaw[1], visible) end
  if ref.bodyyaw[2] then ui.set_visible(ref.bodyyaw[2], visible) end
  if ref.fsbodyyaw then ui.set_visible(ref.fsbodyyaw, visible) end
  if ref.edgeyaw then ui.set_visible(ref.edgeyaw, visible) end
  if ref.freestand[1] then ui.set_visible(ref.freestand[1], visible) end
  if ref.freestand[2] then ui.set_visible(ref.freestand[2], visible) end
end

local function players_vulnerable()
  local enemies = entity.get_players(true)
  for i = 1, #enemies do
    local v = enemies[i]
    local flags = (entity.get_esp_data(v) or {}).flags
    if flags and bit.band(flags, bit.lshift(1, 11)) ~= 0 then -- scoped flag
      return true
    end
  end
  return false
end

local yaw_direction, last_press_t_dir = 0, 0
local function run_direction()
  if use_pui then
    ui.set(ref.freestand[1], menu.dir_modes:get('Freestanding'))
    ui.set(ref.freestand[2], menu.hotkey_fs:get() and 'Always on' or 'On hotkey')
  else
    local fs = ui.get(menu.dir_modes)
    local want_fs = false
    for _, name in ipairs(fs) do if name == 'Freestanding' then want_fs = true end end
    ui.set(ref.freestand[1], want_fs)
    ui.set(ref.freestand[2], ui.get(menu.hotkey_fs) and 'Always on' or 'On hotkey')
  end
  if yaw_direction ~= 0 then ui.set(ref.freestand[1], false) end
  local now = globals.curtime()
  local manual_enabled = use_pui and menu.dir_modes:get('Manual') or (function()
    local arr = ui.get(menu.dir_modes) or {}
    for _, n in ipairs(arr) do if n == 'Manual' then return true end end
    return false
  end)()
  local key_right = use_pui and menu.hotkey_right:get() or ui.get(menu.hotkey_right)
  local key_left = use_pui and menu.hotkey_left:get() or ui.get(menu.hotkey_left)
  local key_forward = use_pui and menu.hotkey_forward:get() or ui.get(menu.hotkey_forward)
  if manual_enabled and key_right and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == 90 and 0 or 90; last_press_t_dir = now
  elseif manual_enabled and key_left and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == -90 and 0 or -90; last_press_t_dir = now
  elseif manual_enabled and key_forward and last_press_t_dir + 0.2 < now then
    yaw_direction = yaw_direction == 180 and 0 or 180; last_press_t_dir = now
  elseif last_press_t_dir > now then last_press_t_dir = now end
end

-- native client entity for defensive timing
local native_GetClientEntity = nil
if ok_ffi and vtable_bind then
  native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')
end

local last_sim_time = 0
local function is_defensive_active(ent)
  if globals.chokedcommands() > 1 then return false end
  if not ent or not entity.is_alive(ent) then return false end
  if not native_GetClientEntity or not ok_ffi then return false end
  local ptr = native_GetClientEntity(ent); if ptr == nil then return false end
  local old = ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0]
  local sim = entity.get_prop(ent, 'm_flSimulationTime')
  local delta = toticks(old - sim)
  if delta > 0 then last_sim_time = globals.tickcount() + delta - toticks(client.real_latency()) end
  return last_sim_time > globals.tickcount()
end

local function doubletap_charged()
  if not ui.get(ref.dt[1]) or not ui.get(ref.dt[2]) or ui.get(ref.fakeduck) then return false end
  if not entity.is_alive(entity.get_local_player()) then return false end
  local weapon = entity.get_prop(entity.get_local_player(), 'm_hActiveWeapon')
  if not weapon then return false end
  local next_attack = (entity.get_prop(entity.get_local_player(), 'm_flNextAttack') or 0) + 0.01
  local next_primary_attack = (entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0) + 0.01
  return (next_attack - globals.curtime() < 0) and (next_primary_attack - globals.curtime() < 0)
end

local function player_state(cmd)
  local lp = entity.get_local_player(); if not lp then return 'Global' end
  local vx, vy = entity.get_prop(lp, 'm_vecVelocity'); vx, vy = vx or 0, vy or 0
  local velocity = math.sqrt(vx * vx + vy * vy)
  local flags = entity.get_prop(lp, 'm_fFlags') or 0
  local on_ground = bit.band(flags, 1) == 1
  local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
  local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7
  local slowwalk_key = ui.get(ref.slow[1]) and ui.get(ref.slow[2])
  if jumping and ducked then return 'Air+'
  elseif jumping then return 'Air'
  elseif ducked and velocity > 10 then return 'Duck+Move'
  elseif ducked and velocity <= 10 then return 'Duck'
  elseif on_ground and slowwalk_key and velocity > 10 then return 'Walking'
  elseif on_ground and velocity > 5 then return 'Running'
  elseif on_ground and velocity <= 5 then return 'Stand'
  else return 'Global' end
end

-- ========= AA Runtime =========
local cond_idx, tick_gate, toggle_jitter = 1, 0, false
local yaw_amount = 0

local function sequence_from_menu(conf, def)
  local jt = def and (conf.def_jitter_type and conf.def_jitter_type:get()) or (conf.jitter_type and conf.jitter_type:get())
  local mode = def and (conf.def_jitter_type and conf.def_jitter_type:get()) or (conf.jitter_type and conf.jitter_type:get())
  if jt == '3-way' then
    return { conf.j3_1 and conf.j3_1:get() or -45, conf.j3_2 and conf.j3_2:get() or 1, conf.j3_3 and conf.j3_3:get() or 45 }
  elseif jt == '5-way' then
    return {
      conf.j5_1 and conf.j5_1:get() or -80, conf.j5_2 and conf.j5_2:get() or -45,
      conf.j5_3 and conf.j5_3:get() or -1, conf.j5_4 and conf.j5_4:get() or 45,
      conf.j5_5 and conf.j5_5:get() or 80
    }
  elseif jt == '7-way' then
    return {
      conf.j7_1 and conf.j7_1:get() or -90, conf.j7_2 and conf.j7_2:get() or -60,
      conf.j7_3 and conf.j7_3:get() or -30, conf.j7_4 and conf.j7_4:get() or 0,
      conf.j7_5 and conf.j7_5:get() or 30, conf.j7_6 and conf.j7_6:get() or 60,
      conf.j7_7 and conf.j7_7:get() or 90
    }
  elseif jt == '9-way' then
    return {
      conf.j9_1 and conf.j9_1:get() or -120, conf.j9_2 and conf.j9_2:get() or -90,
      conf.j9_3 and conf.j9_3:get() or -60, conf.j9_4 and conf.j9_4:get() or -30,
      conf.j9_5 and conf.j9_5:get() or 0, conf.j9_6 and conf.j9_6:get() or 30,
      conf.j9_7 and conf.j9_7:get() or 60, conf.j9_8 and conf.j9_8:get() or 90,
      conf.j9_9 and conf.j9_9:get() or 120
    }
  end
  return nil
end

local function map_jitter_type(jt)
  if jt == '3-way' or jt == '5-way' or jt == '7-way' or jt == '9-way' then return 'Offset' end
  return jt
end

local function apply_multiway(conf, def)
  local seq = sequence_from_menu(conf, def)
  if seq then local idx = (globals.tickcount() % #seq) + 1; return seq[idx] end
  local amount = def and (conf.def_jitter_amount and conf.def_jitter_amount:get() or 0) or (conf.jitter_amount and conf.jitter_amount:get() or 0)
  return amount
end

local function apply_pitch(conf_mode, conf_value, desync_side, seq_mode, seq_vals)
  if not ref.pitch[1] or not ref.pitch[2] then return end
  ui.set(ref.pitch[1], 'Custom')
  if seq_mode and seq_mode ~= 'Off' and seq_vals then
    local idx = (globals.tickcount() % #seq_vals) + 1
    ui.set(ref.pitch[2], clamp(seq_vals[idx], -89, 89))
    return
  end
  if conf_mode == 'Off' then ui.set(ref.pitch[2], 89)
  elseif conf_mode == 'Custom' then ui.set(ref.pitch[2], conf_value)
  elseif conf_mode == 'Meta' then ui.set(ref.pitch[2], desync_side and 49 or -49)
  elseif conf_mode == 'Random' then ui.set(ref.pitch[2], client.random_int(-89, 89)) end
end

_G.__ky_threat_window = _G.__ky_threat_window or 0

local function select_condition(cmd)
  local st = player_state(cmd)
  if st == 'Duck+Move' and builder[8] and (builder[8].enable and builder[8].enable.get and builder[8].enable:get()) then cond_idx = 8
  elseif st == 'Duck' and builder[7] and (builder[7].enable and builder[7].enable.get and builder[7].enable:get()) then cond_idx = 7
  elseif st == 'Air+' and builder[6] and (builder[6].enable and builder[6].enable.get and builder[6].enable:get()) then cond_idx = 6
  elseif st == 'Air' and builder[5] and (builder[5].enable and builder[5].enable.get and builder[5].enable:get()) then cond_idx = 5
  elseif st == 'Running' and builder[4] and (builder[4].enable and builder[4].enable.get and builder[4].enable:get()) then cond_idx = 4
  elseif st == 'Walking' and builder[3] and (builder[3].enable and builder[3].enable.get and builder[3].enable:get()) then cond_idx = 3
  elseif st == 'Stand' and builder[2] and (builder[2].enable and builder[2].enable.get and builder[2].enable:get()) then cond_idx = 2
  else cond_idx = 1 end
end

local function get_value(obj, def)
  if not obj then return def end
  if obj.get then return obj:get() end
  return def
end

local toggle_def_gate, first_vuln = true, true

local function aa_apply(cmd)
  local lp = entity.get_local_player(); if not lp then return end

  -- reset roll
  if ref.roll then ui.set(ref.roll, 0) end

  -- direction
  run_direction()

  -- tick gating
  local conf = builder[cond_idx]
  if conf and conf.yaw_delay and globals.tickcount() > tick_gate + get_value(conf.yaw_delay, 4) then
    if cmd.chokedcommands == 0 then toggle_jitter = not toggle_jitter; tick_gate = globals.tickcount() end
  elseif globals.tickcount() < tick_gate then tick_gate = globals.tickcount() end

  -- vulnerable peeking gate
  if players_vulnerable() then
    if first_vuln then first_vuln = false; toggle_def_gate = true end
    if globals.tickcount() % 10 == 9 then toggle_def_gate = false end
  else
    first_vuln = true; toggle_def_gate = false
  end

  -- defaults
  ui.set(ref.enabled, true)
  ui.set(ref.fsbodyyaw, false)
  ui.set(ref.pitch[1], 'Custom')
  if use_pui then ui.set(ref.yawbase, menu.yaw_base:get()) else ui.set(ref.yawbase, ui.get(menu.yaw_base) or 'At targets') end

  -- select condition
  select_condition(cmd)
  conf = builder[cond_idx] or {}

  -- yaw jitter/body
  local selected_builder_def = (conf.def_enable and get_value(conf.def_enable, false)) and (conf.def_type and get_value(conf.def_type, 'Default') == 'Builder') and is_defensive_active(lp)

  if selected_builder_def then
    local jt = get_value(conf.def_jitter_type, 'Off')
    ui.set(ref.yawjitter[1], map_jitter_type(jt))
    ui.set(ref.yawjitter[2], apply_multiway(conf, true))
    ui.set(ref.bodyyaw[1], get_value(conf.def_body_type, 'Static'))
    ui.set(ref.bodyyaw[2], get_value(conf.def_body_amount, 1))
    yaw_amount = (yaw_direction == 0) and get_value(conf.def_yaw_value, 9) or yaw_direction
  else
    local jt = get_value(conf.jitter_type, 'Off')
    ui.set(ref.yawjitter[1], map_jitter_type(jt))
    ui.set(ref.yawjitter[2], apply_multiway(conf, false))
    if get_value(conf.yaw_mode, 'Default') == 'Delay' then
      ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], toggle_jitter and 1 or -1)
    else
      ui.set(ref.bodyyaw[1], get_value(conf.body_type, 'Jitter'))
      ui.set(ref.bodyyaw[2], get_value(conf.body_amount, 1))
    end
  end

  -- spin/default yaw mode mapping
  local yaw_mode = get_value(conf.yaw_mode, 'Default')
  local def_yaw_mode = get_value(conf.def_yaw_mode, 'Spin')
  if is_defensive_active(lp) and get_value(conf.def_enable, false) and get_value(conf.def_type, 'Default') == 'Default' and def_yaw_mode == 'Spin' then
    ui.set(ref.yaw[1], 'Spin')
  elseif yaw_mode == 'Spin' then
    ui.set(ref.yaw[1], 'Spin')
  else
    ui.set(ref.yaw[1], '180')
  end

  -- defensive triggers
  local act_vulnerable = (conf.def_when and conf.def_when.get and conf.def_when:get('Vulnerable')) and players_vulnerable()
  local act_charged = (conf.def_when and conf.def_when.get and conf.def_when:get('Charged DT')) and doubletap_charged()
  local act_peek = (conf.def_when and conf.def_when.get and conf.def_when:get('On Peek')) and toggle_def_gate
  local act_threat = (_G.__ky_threat_window > globals.curtime()) and (conf.def_when and conf.def_when.get and conf.def_when:get('Threat Shot'))
  local defensive_now = (conf.def_enable and get_value(conf.def_enable, false)) and (act_vulnerable or act_charged or act_peek or act_threat or (conf.force_def and get_value(conf.force_def, false)) or (conf.peek_def and get_value(conf.peek_def, false) and toggle_def_gate))
  cmd.force_defensive = defensive_now

  -- desync side
  local desync_type = (entity.get_prop(lp, 'm_flPoseParameter', 11) or 0) * 120 - 60
  local desync_side = desync_type > 0

  -- actual yaw amount
  if is_defensive_active(lp) and get_value(conf.def_enable, false) and get_value(conf.def_type, 'Default') == 'Default' then
    local mode = get_value(conf.def_yaw_mode, 'Spin')
    if mode == 'Spin' then yaw_amount = get_value(conf.yaw_value, 0)
    elseif mode == 'Meta' then yaw_amount = desync_side and 90 or -90
    elseif mode == 'Random' then yaw_amount = client.random_int(-180, 180)
    else yaw_amount = desync_side and (get_value(conf.yaw_left, 0) + (get_value(conf.yaw_left, 0) * get_value(conf.yaw_random, 0) / 100) * (math.random() - 0.5) * 2)
                or (get_value(conf.yaw_right, 0) + (get_value(conf.yaw_right, 0) * get_value(conf.yaw_random, 0) / 100) * (math.random() - 0.5) * 2) end
  elseif not selected_builder_def then
    local mode = get_value(conf.yaw_mode, 'Default')
    if mode == 'Freestand' then ui.set(ref.freestand[1], true); yaw_amount = 0
    elseif mode == 'Manual' and yaw_direction ~= 0 then yaw_amount = yaw_direction
    else yaw_amount = desync_side and (get_value(conf.yaw_left, 0) + (get_value(conf.yaw_left, 0) * get_value(conf.yaw_random, 0) / 100) * (math.random() - 0.5) * 2)
              or (get_value(conf.yaw_right, 0) + (get_value(conf.yaw_right, 0) * get_value(conf.yaw_random, 0) / 100) * (math.random() - 0.5) * 2) end
    if ref.pitch[2] then ui.set(ref.pitch[2], 89) end
  end

  -- pitch application
  local seq_mode = conf.pitch_seq and get_value(conf.pitch_seq, 'Off') or 'Off'
  local seq_vals = nil
  if seq_mode == '3-way' then seq_vals = { get_value(conf.p3_1, -45), get_value(conf.p3_2, 0), get_value(conf.p3_3, 45) } end
  if seq_mode == '5-way' then seq_vals = { get_value(conf.p5_1, -89), get_value(conf.p5_2, -45), get_value(conf.p5_3, 0), get_value(conf.p5_4, 45), get_value(conf.p5_5, 89) } end

  local def_seq_mode = conf.def_pitch_seq and get_value(conf.def_pitch_seq, 'Off') or 'Off'
  local def_seq_vals = nil
  -- use 3/5 only for DEF
  -- apply defensive pitch if active
  if defensive_now then
    if def_seq_mode == '3-way' then def_seq_vals = { get_value(conf.p3_1, -45), get_value(conf.p3_2, 0), get_value(conf.p3_3, 45) } end
    if def_seq_mode == '5-way' then def_seq_vals = { get_value(conf.p5_1, -89), get_value(conf.p5_2, -45), get_value(conf.p5_3, 0), get_value(conf.p5_4, 45), get_value(conf.p5_5, 89) } end
    apply_pitch(get_value(conf.def_pitch_mode, 'Off'), get_value(conf.def_pitch_value, 0), desync_side, def_seq_mode, def_seq_vals)
  else
    apply_pitch(get_value(conf.pitch_mode, 'Off'), get_value(conf.pitch_value, 0), desync_side, seq_mode, seq_vals)
  end

  ui.set(ref.yaw[2], yaw_direction == 0 and yaw_amount or yaw_direction)

  -- Warmup AA
  local want_warmup = use_pui and (menu.helpers:get('Warmup AA')) or false
  if want_warmup and entity.get_prop(entity.get_game_rules(), 'm_bWarmupPeriod') == 1 then
    ui.set(ref.yaw[2], client.random_int(-180, 180))
    ui.set(ref.yawjitter[2], client.random_int(-180, 180))
    ui.set(ref.bodyyaw[2], client.random_int(-180, 180))
    if ref.pitch[1] and ref.pitch[2] then ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], client.random_int(-89, 89)) end
  end

  -- Safe Head (knife/zeus/long distance)
  local want_safe_head = use_pui and menu.helpers:get('Safe Head')
  if want_safe_head then
    local lp_weapon = entity.get_player_weapon(lp)
    if lp_weapon then
      local flags = entity.get_prop(lp, 'm_fFlags') or 0
      local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
      local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7
      if menu.safe_head_opts:get('Air+C Knife') and jumping and ducked and entity.get_classname(lp_weapon) == 'CKnife' then
        ui.set(ref.yawjitter[1], 'Off'); ui.set(ref.yaw[1], '180'); ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], 1); ui.set(ref.yaw[2], 14); ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], 89)
      end
      if menu.safe_head_opts:get('Air+C Zeus') and jumping and ducked and entity.get_classname(lp_weapon) == 'CWeaponTaser' then
        ui.set(ref.yawjitter[1], 'Off'); ui.set(ref.yaw[1], '180'); ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], 1); ui.set(ref.yaw[2], 14); ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], 89)
      end
      if menu.safe_head_opts:get('Long Distance') then
        local t = client.current_threat(); if t then
          local lx, ly, lz = entity.get_prop(lp, 'm_vecOrigin'); local tx, ty, tz = entity.get_prop(t, 'm_vecOrigin')
          if lx and tx then
            local dx, dy, dz = tx - lx, ty - ly, tz - lz
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist > 900 then ui.set(ref.yawjitter[1], 'Off'); ui.set(ref.yaw[1], '180'); ui.set(ref.bodyyaw[1], 'Static'); ui.set(ref.bodyyaw[2], 1); ui.set(ref.yaw[2], 14); ui.set(ref.pitch[1], 'Custom'); ui.set(ref.pitch[2], 89) end
          end
        end
      end
    end
  end

  -- Anti-Knife helper
  local want_anti_knife = use_pui and menu.helpers:get('Anti-Knife')
  if want_anti_knife then
    local lx, ly, lz = entity.get_prop(lp, 'm_vecOrigin')
    for _, enemy in ipairs(entity.get_players(true)) do
      local w = entity.get_player_weapon(enemy)
      if w then
        local ex, ey, ez = entity.get_prop(enemy, 'm_vecOrigin')
        if ex then
          local dist = math.sqrt((ex - lx) ^ 2 + (ey - ly) ^ 2 + (ez - lz) ^ 2)
          if entity.get_classname(w) == 'CKnife' and dist <= 250 then ui.set(ref.yaw[2], 180); ui.set(ref.yawbase, 'At targets') end
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
  if not (use_pui and menu.logs:get()) then return end
  local sw, sh = client.screen_size(); local cx, cy = sw / 2, sh / 1.4
  local offset = 0
  for idx, data in ipairs(logs) do
    if (((globals.curtime()/2) * 2.0) - data[3]) < 4.0 and not (#logs > 5 and idx < #logs - 5) then data[2] = math.lerp(data[2], 255, 10) else data[2] = math.lerp(data[2], 0, 10) end
    offset = offset - 40 * (data[2] / 255)
    local tsx = renderer.measure_text('', data[1])
    if menu.logs_style:get() == 'Default' then
      renderer.rectangle(cx - 7 - tsx/2, cy - offset - 8, tsx + 13, 26, 0, 0, 0, (data[2] / 255) * 150)
      renderer.rectangle(cx - 6 - tsx/2, cy - offset - 7, tsx + 11, 24, 50, 50, 50, (data[2] / 255) * 255)
      renderer.rectangle(cx - 4 - tsx/2, cy - offset - 4, tsx + 7, 18, 80, 80, 80, (data[2] / 255) * 255)
      renderer.rectangle(cx - 3 - tsx/2, cy - offset - 3, tsx + 5, 16, 20, 20, 20, (data[2] / 255) * 200)
    else
      renderer.rectangle(cx - 7 - tsx/2, cy - offset - 5, tsx + 13, 2, 195, 240, 70, data[2])
      renderer.rectangle(cx - 7 - tsx/2, cy - offset - 5, tsx + 13, 20, 0, 0, 0, (data[2] / 255) * 50)
    end
    local cr, cg, cb = 255,255,255; if data[4] == 'miss' then cr,cg,cb = 255,64,64 end; if data[4] == 'hit' then cr,cg,cb = 180,255,180 end
    renderer.text(cx - 1 - tsx/2, cy - offset, cr, cg, cb, data[2], '', 0, data[1])
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
    local c = rgba_hex(
      lerp(color1.r, color2.r, clamp(wave, 0, 1)),
      lerp(color1.g, color2.g, clamp(wave, 0, 1)),
      lerp(color1.b, color2.b, clamp(wave, 0, 1)),
      color1.a
    )
    final_text = final_text .. '\a' .. c .. text:sub(i, i)
  end
  renderer.text(x, y, color1.r, color1.g, color1.b, color1.a, flag, nil, final_text)
end

local function doubletap_ready() return doubletap_charged() end

local function screen_indicator()
  if not (use_pui and menu.cross_ind:get()) then return end
  local lp = entity.get_local_player(); if not lp then return end
  local sw, sh = client.screen_size(); local cx, cy = sw / 2, sh / 2
  local scpd = entity.get_prop(lp, 'm_bIsScoped') == 1
  scoped_space = math.lerp(scoped_space, scpd and 50 or 0, 20)
  local cond = (function(idx)
    if idx == 1 then return 'global' elseif idx == 2 then return 'stand' elseif idx == 3 then return 'walk' elseif idx == 4 then return 'run' elseif idx == 5 or idx == 6 then return 'air' elseif idx == 7 or idx == 8 then return 'crouch' end return 'global' end)(cond_idx)
  if menu.cross_style:get() == 'Default' then main_font = 'c-b'; key_font = 'c'
  elseif menu.cross_style:get() == 'Modern' then main_font = 'c-b'; key_font = 'c-b'
  elseif menu.cross_style:get() == 'Alternative' then main_font = 'c'; key_font = 'c'
  else main_font = 'c-d'; key_font = 'c-d' end
  menu.cross_color:override(true); menu.key_color:override(true)
  local r1, g1, b1 = menu.cross_ind:get_color(); local r2, g2, b2 = menu.cross_color:get_color(); local r3, g3, b3 = menu.key_color:get_color()
  text_fade_animation(cx + scoped_space, cy + 30, -1, { r = r1, g = g1, b = b1, a = 255 }, { r = r2, g = g2, b = b2, a = 255 }, 'KY-yaw', main_font)
  renderer.text(cx + scoped_space, cy + 40, r2, g2, b2, 255, main_font, 0, cond)

  local offset = 10
  if ui.get(ref.forcebaim) then renderer.text(cx + scoped_space, cy + 40 + offset, 255, 102, 117, 255, key_font, 0, 'body'); offset = offset + 10 end
  if ui.get(ref.os[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, 'onshot'); offset = offset + 10 end
  if ui.get(ref.min_dmg_override[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, 'dmg'); offset = offset + 10 end
  if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) then
    if doubletap_ready() then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, 'dt')
    else renderer.text(cx + scoped_space, cy + 40 + offset, 255, 0, 0, 255, key_font, 0, 'dt') end
    offset = offset + 10
  end
  if ui.get(ref.freestand[1]) and ui.get(ref.freestand[2]) then renderer.text(cx + scoped_space, cy + 40 + offset, r3, g3, b3, 255, key_font, 0, 'fs'); offset = offset + 10 end

  -- manual arrows
  if menu.manual_arrows:get() and menu.dir_modes:get('Manual') then
    local ar_r, ar_g, ar_b = menu.manual_arrows:get_color(); local size = menu.arrow_size:get(); local dist = menu.arrow_offset:get()
    if yaw_direction == -90 then renderer.triangle(cx - dist, cy, cx - dist + size, cy - size/2, cx - dist + size, cy + size/2, ar_r, ar_g, ar_b, 200) end
    if yaw_direction == 90 then renderer.triangle(cx + dist, cy, cx + dist - size, cy - size/2, cx + dist - size, cy + size/2, ar_r, ar_g, ar_b, 200) end
    if yaw_direction == 180 then renderer.triangle(cx, cy - dist, cx - size/2, cy - dist + size, cx + size/2, cy - dist + size, ar_r, ar_g, ar_b, 200) end
  end
end

local defensive_alpha, defensive_amount, velocity_alpha, velocity_amount = 0, 0, 0, 0
local function velocity_ind()
  if not (use_pui and menu.velocity_win:get()) then return end
  local lp = entity.get_local_player(); if not lp then return end
  local sw, sh = client.screen_size(); local cx, cy = sw / 2, sh / 3
  local r, g, b = menu.velocity_win:get_color()
  local vel_mod = entity.get_prop(lp, 'm_flVelocityModifier') or 1
  if not ui.is_menu_open() then velocity_alpha = math.lerp(velocity_alpha, vel_mod < 1 and 255 or 0, 10); velocity_amount = math.lerp(velocity_amount, vel_mod, 10)
  else velocity_alpha = math.lerp(velocity_alpha, 255, 10); velocity_amount = globals.tickcount() % 50 / 100 * 2 end
  renderer.text(cx, cy - 10, 255, 255, 255, velocity_alpha, 'c', 0, '- speed -')
  if menu.velocity_style:get() == 'Default' then
    renderer.rectangle(cx - 50, cy, 100, 5, 0, 0, 0, velocity_alpha)
    renderer.rectangle(cx - 49, cy + 1, (100 * velocity_amount) - 1, 3, r, g, b, velocity_alpha)
  else
    renderer.gradient(cx - (50 * velocity_amount), cy, 1 + 50 * velocity_amount, 2, r, g, b, velocity_alpha / 3, r, g, b, velocity_alpha, true)
    renderer.gradient(cx, cy, 50 * velocity_amount, 2, r, g, b, velocity_alpha, r, g, b, velocity_alpha / 3, true)
  end
end

local function defensive_ind()
  if not (use_pui and menu.defensive_win:get()) then return end
  local lp = entity.get_local_player(); if not lp then return end
  local sw, sh = client.screen_size(); local cx, cy = sw / 2, sh / 4
  local charged = doubletap_charged(); local active = is_defensive_active(lp)
  local r, g, b = menu.defensive_win:get_color()
  if not ui.is_menu_open() then
    if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) and not ui.get(ref.fakeduck) then
      if charged and active then defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = math.lerp(defensive_amount, 1, 10)
      elseif charged and not active then defensive_alpha = math.lerp(defensive_alpha, 0, 10); defensive_amount = math.lerp(defensive_amount, 0.5, 10)
      else defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = math.lerp(defensive_amount, 0, 10) end
    else defensive_alpha = math.lerp(defensive_alpha, 0, 10); defensive_amount = math.lerp(defensive_amount, 0, 10) end
  else defensive_alpha = math.lerp(defensive_alpha, 255, 10); defensive_amount = globals.tickcount() % 50 / 100 * 2 end
  renderer.text(cx, cy - 10, 255, 255, 255, defensive_alpha, 'c', 0, '- defense -')
  if menu.defensive_style:get() == 'Default' then
    renderer.rectangle(cx - 50, cy, 100, 5, 0, 0, 0, defensive_alpha)
    renderer.rectangle(cx - 49, cy + 1, (100 * defensive_amount) - 1, 3, r, g, b, defensive_alpha)
  else
    renderer.gradient(cx - (50 * defensive_amount), cy, 1 + 50 * defensive_amount, 2, r, g, b, defensive_alpha / 3, r, g, b, defensive_alpha, true)
    renderer.gradient(cx, cy, 50 * defensive_amount, 2, r, g, b, defensive_alpha, r, g, b, defensive_alpha / 3, true)
  end
end

local function info_panel()
  if not (use_pui and menu.info_panel:get()) then return end
  local lp = entity.get_local_player(); if not lp then return end
  local sw, sh = client.screen_size(); local cx, cy = sw / 2, sh / 2
  local function condstr(idx) if idx == 1 then return 'global' elseif idx == 2 then return 'stand' elseif idx == 3 then return 'walk' elseif idx == 4 then return 'run' elseif idx == 5 or idx == 6 then return 'air' elseif idx == 7 or idx == 8 then return 'crouch' end return 'global' end
  local threat = client.current_threat(); local name = 'nil'; local tdes = 0
  if threat then name = entity.get_player_name(threat); tdes = math.floor((entity.get_prop(threat, 'm_flPoseParameter', 11) or 0) * 120 - 60) end
  name = name:sub(1, 12)
  local des = math.floor((entity.get_prop(lp, 'm_flPoseParameter', 11) or 0) * 120 - 60)
  text_fade_animation(20, cy, -1, { r = 220, g = 220, b = 220, a = 255 }, { r = 160, g = 160, b = 160, a = 255 }, 'KY-yaw', 'd')
  local ts = renderer.measure_text('d', 'KY-yaw')
  renderer.gradient(20, cy + 15, ts / 2, 2, 255, 255, 255, 50, 255, 255, 255, 255, true)
  renderer.gradient(20 + ts / 2, cy + 15, ts / 2, 2, 255, 255, 255, 255, 255, 255, 255, 50, true)
  renderer.text(20, cy + 20, 255, 255, 255, 255, 'd', 0, 'state: ' .. condstr(cond_idx) .. ' ' .. math.abs(des) .. '°')
  renderer.text(20, cy + 30, 255, 255, 255, 255, 'd', 0, 'target: ' .. string.lower(name) .. ' ' .. math.abs(tdes) .. '°')
end

-- ========= Animation Breakers =========
local function animation_breakers()
  if not (use_pui and menu.animation:get()) then return end
  if not ok_ent then return end
  local lp = entity.get_local_player(); if not lp or not entity.is_alive(lp) then return end
  local idx = c_entity.new(lp); local anim_state = idx:get_anim_state(); if not anim_state then return end
  local overlay = idx:get_anim_overlay(12); if not overlay then return end
  local xvel = entity.get_prop(lp, 'm_vecVelocity[0]') or 0; if math.abs(xvel) >= 3 then overlay.weight = 1 end
  local ground_mode = menu.anim_ground:get()
  if ground_mode == 'Static' then entity.set_prop(lp, 'm_flPoseParameter', menu.anim_amount:get() / 10, 0)
  elseif ground_mode == 'Jitter' then entity.set_prop(lp, 'm_flPoseParameter', globals.tickcount() % 4 > 1 and menu.anim_amount:get() / 10 or 0, 0)
  else entity.set_prop(lp, 'm_flPoseParameter', math.random(menu.anim_amount:get(), 10) / 10, 0) end
  local air_mode = menu.anim_air:get()
  if air_mode == 'Static' then entity.set_prop(lp, 'm_flPoseParameter', 1, 6)
  elseif air_mode == 'Randomize' then entity.set_prop(lp, 'm_flPoseParameter', math.random(0, 10) / 10, 6) end
end

-- ========= Movement/Misc =========
local function fast_ladder(cmd)
  local lp = entity.get_local_player(); if entity.get_prop(lp, 'm_MoveType') ~= 9 then return end
  local pitch = select(1, client.camera_angles())
  cmd.yaw = math.floor(cmd.yaw + 0.5); cmd.roll = 0
  if cmd.forwardmove == 0 then if cmd.sidemove ~= 0 then cmd.pitch = 89; cmd.yaw = cmd.yaw + 180; if cmd.sidemove < 0 then cmd.in_moveleft = 0; cmd.in_moveright = 1 end; if cmd.sidemove > 0 then cmd.in_moveleft = 1; cmd.in_moveright = 0 end end end
  if cmd.forwardmove > 0 then if pitch < 45 then cmd.pitch = 89; cmd.in_moveright = 1; cmd.in_moveleft = 0; cmd.in_forward = 0; cmd.in_back = 1; if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end; if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 150 end; if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 30 end end end
  if cmd.forwardmove < 0 then cmd.pitch = 89; cmd.in_moveleft = 1; cmd.in_moveright = 0; cmd.in_forward = 1; cmd.in_back = 0; if cmd.sidemove == 0 then cmd.yaw = cmd.yaw + 90 end; if cmd.sidemove > 0 then cmd.yaw = cmd.yaw + 150 end; if cmd.sidemove < 0 then cmd.yaw = cmd.yaw + 30 end end
end

local function thirdperson(value) if value ~= nil and cvar and cvar.cam_idealdist then cvar.cam_idealdist:set_int(value) end end
local function aspectratio(value) if value and cvar and cvar.r_aspectratio then cvar.r_aspectratio:set_float(value) end end

local function auto_tp(cmd)
  local lp = entity.get_local_player(); if not lp then return end
  local flags = entity.get_prop(lp, 'm_fFlags') or 0; local jumping = bit.band(flags, 1) == 0
  if players_vulnerable() and jumping then cmd.force_defensive = true; cmd.discharge_pending = true end
end

-- ========= Resolver =========
local expres = { body_yaw = {}, eye_angles = {} }
local function get_prev_simtime(ent)
  if not native_GetClientEntity or not ok_ffi then return nil end
  local ptr = native_GetClientEntity(ent); if ptr ~= nil then return ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0] end
end

local function resolver_restore() if plist and plist.set then for i = 1, 64 do plist.set(i, 'Force body yaw', false) end end end
local function get_max_desync(animstate)
  local function cl(x, a, b) if x < a then return a elseif x > b then return b else return x end end
  local speedfactor = cl(animstate.feet_speed_forwards_or_sideways, 0, 1)
  local avg_speedfactor = (animstate.stop_to_full_running_fraction * -0.3 - 0.2) * speedfactor + 1
  local duck_amount = animstate.duck_amount; if duck_amount > 0 then avg_speedfactor = avg_speedfactor + (duck_amount * speedfactor * (0.5 - avg_speedfactor)) end
  return cl(avg_speedfactor, .5, 1)
end

local function is_defensive_resolver(ent)
  if not native_GetClientEntity or not ok_ffi then return false end
  if not ent or not entity.is_alive(ent) then return false end
  local ptr = native_GetClientEntity(ent); if ptr == nil then return false end
  local old = ffi.cast('float*', ffi.cast('uintptr_t', ptr) + 0x26C)[0]
  local sim = entity.get_prop(ent, 'm_flSimulationTime')
  local delta = toticks(old - sim)
  if delta > 0 then last_sim_time = globals.tickcount() + delta - toticks(client.real_latency()) end
  return last_sim_time > globals.tickcount()
end

local function resolver_handle(threat)
  if not (plist and plist.set) then return end
  if not threat or not entity.is_alive(threat) or entity.is_dormant(threat) then resolver_restore(); return end
  expres.body_yaw[threat] = expres.body_yaw[threat] or {}; expres.eye_angles[threat] = expres.eye_angles[threat] or {}
  local simtime = toticks(entity.get_prop(threat, 'm_flSimulationTime'))
  local prev_simtime = toticks(get_prev_simtime(threat) or 0)
  expres.body_yaw[threat][simtime] = (entity.get_prop(threat, 'm_flPoseParameter', 11) or 0) * 120 - 60
  expres.eye_angles[threat][simtime] = select(2, entity.get_prop(threat, 'm_angEyeAngles'))
  if expres.body_yaw[threat][prev_simtime] ~= nil and ok_ent then
    local ent = c_entity.new(threat); local animstate = ent:get_anim_state(); if not animstate then return end
    local max_desync = get_max_desync(animstate)
    local Pitch = entity.get_prop(threat, 'm_angEyeAngles[0]') or 0
    local pitch_e = Pitch > -30 and Pitch < 49
    local resolver_kind = use_pui and menu.resolver_type:get() or 'Stable'
    if resolver_kind == 'Stable' then
      local prev = expres.body_yaw[threat][prev_simtime] or 0
      local curr = expres.body_yaw[threat][simtime] or 0
      local delta = curr - prev
      local correction = clamp(delta, -35, 35)
      if pitch_e then correction = 0 end
      plist.set(threat, 'Force body yaw', true); plist.set(threat, 'Force body yaw value', correction)
    else -- Adaptive
      local strength = (use_pui and menu.resolver_strength:get() or 70) / 100
      local side = globals.tickcount() % 4 > 1 and 1 or -1
      local base = side * (max_desync * 58 * strength)
      if pitch_e or not is_defensive_resolver(threat) then base = base * 0.25 end
      plist.set(threat, 'Force body yaw', true); plist.set(threat, 'Force body yaw value', base)
    end
  end
  plist.set(threat, 'Correction active', true)
end

local function resolver_update()
  if not (use_pui and menu.resolver:get()) then return end
  local ents = entity.get_players(true); if not ents then return end
  for i = 1, #ents do resolver_handle(ents[i]) end
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
  local a_to_p = { P[1] - A[1], P[2] - A[2] }; local a_to_b = { B[1] - A[1], B[2] - A[2] }
  local atb2 = a_to_b[1] ^ 2 + a_to_b[2] ^ 2; if atb2 == 0 then return end
  local t = (a_to_p[1] * a_to_b[1] + a_to_p[2] * a_to_b[2]) / atb2
  local closest = { A[1] + a_to_b[1] * t, A[2] + a_to_b[2] * t }
  local dx, dy = P[1] - closest[1], P[2] - closest[2]
  local delta_2d = math.sqrt(dx * dx + dy * dy)
  if math.abs(delta_2d) <= 60 then _G.__ky_threat_window = globals.curtime() + 0.35; if use_pui and menu.logs:get() and menu.logs_type:get('Screen') then push_log(entity.get_player_name(ent) .. ' Shot At You') end end
end)

safe_callback('aim_hit', function(e)
  if not (use_pui and menu.logs:get()) then return end
  local names = { 'generic','head','chest','stomach','left arm','right arm','left leg','right leg','neck','?','gear' }
  local group = names[(e.hitgroup or 0) + 1] or '?'
  if menu.logs_type:get('Screen') then push_log(string.format('Hit %s in the %s for %d', entity.get_player_name(e.target), group, e.damage), 'hit') end
  if menu.logs_type:get('Console') then print(string.format('Hit %s in the %s for %d damage', entity.get_player_name(e.target), group, e.damage)) end
end)

safe_callback('aim_miss', function(e)
  if not (use_pui and menu.logs:get()) then return end
  local names = { 'generic','head','chest','stomach','left arm','right arm','left leg','right leg','neck','?','gear' }
  local group = names[(e.hitgroup or 0) + 1] or '?'
  if menu.logs_type:get('Screen') then push_log(string.format('Missed %s in the %s (%s)', entity.get_player_name(e.target), group, e.reason), 'miss') end
  if menu.logs_type:get('Console') then print(string.format('Missed %s in the %s due to %s', entity.get_player_name(e.target), group, e.reason)) end
end)

safe_callback('setup_command', function(cmd)
  -- Hide original when our UI is open (PUI only)
  if use_pui then hide_original_menu(false) end
  -- Run AA
  aa_apply(cmd)
  -- Extras
  if use_pui and menu.third_person:get() then thirdperson(menu.third_person_value:get()) end
  if use_pui and menu.aspectratio:get() then aspectratio(menu.aspectratio_value:get() / 100) end
  if use_pui and menu.teleport:get() and menu.teleport_key:get() then auto_tp(cmd) end
  if use_pui and menu.resolver:get() then resolver_update() end
end)

safe_callback('pre_render', function()
  if not entity.is_alive(entity.get_local_player()) then return end
  if use_pui and menu.animation:get() then animation_breakers() end
end)

safe_callback('paint', function()
  if not entity.is_alive(entity.get_local_player()) then return end
  screen_indicator(); velocity_ind(); defensive_ind(); ragebot_logs(); info_panel()
  local sw, sh = client.screen_size()
  text_fade_animation(sw / 2, sh - 20, -1, { r = 210, g = 210, b = 210, a = 255 }, { r = 160, g = 160, b = 160, a = 255 }, 'KY-yaw', 'cdb')
end)

safe_callback('round_prestart', function()
  logs = {}
  if use_pui and menu.logs:get() and menu.logs_type:get('Screen') then push_log('Anti-Aim Data Reset') end
end)

safe_callback('shutdown', function()
  hide_original_menu(true)
  thirdperson(150)
  aspectratio(0)
  resolver_restore()
end)

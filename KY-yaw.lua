-- KY-yaw.lua
-- Clean, robust Anti-Aim builder focused on clarity, stability and practicality
-- Built from scratch, inspired by strengths across existing scripts while avoiding bloat

local ffi = require('ffi')
local pui = require('gamesense/pui')
local json = require('json')

-- ========= Utilities =========
local function clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function lerp(current, target, speed)
  return current + (target - current) * globals.absoluteframetime() * speed
end

local function to_ticks(seconds)
  return math.floor(0.5 + (seconds / globals.tickinterval()))
end

local function rgba_to_hex(r, g, b, a)
  return string.format('%02x%02x%02x%02x', r, g, b, a)
end

local function safe_callback(name, fn)
  client.set_event_callback(name, function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      print(string.format('[KY-yaw] %s error: %s', tostring(name), tostring(err)))
    end
  end)
end

-- ========= Engine refs =========
local function ref1(a,b,c)
  local ok, v = pcall(ui.reference, a,b,c)
  if ok then return v end
  return nil
end

local function refN(a,b,c)
  local ok, v1, v2 = pcall(ui.reference, a,b,c)
  if ok then return {v1, v2} end
  return {nil, nil}
end

local ref = {
  enabled = ref1('AA','Anti-aimbot angles','Enabled'),
  yaw_base = ref1('AA','Anti-aimbot angles','Yaw base'),
  pitch = refN('AA','Anti-aimbot angles','Pitch'),
  yaw = refN('AA','Anti-aimbot angles','Yaw'),
  yaw_jitter = refN('AA','Anti-aimbot angles','Yaw jitter'),
  body_yaw = refN('AA','Anti-aimbot angles','Body yaw'),
  fs = refN('AA','Anti-aimbot angles','Freestanding'),
  fs_body = ref1('AA','Anti-aimbot angles','Freestanding body yaw'),
  edge_yaw = ref1('AA','Anti-aimbot angles','Edge yaw'),
  roll = refN('AA','Anti-aimbot angles','Roll'),
  slow = refN('AA','Other','Slow motion'),
  os = refN('AA','Other','On shot anti-aim'),
  dt = refN('RAGE','Aimbot','Double tap'),
  fd = ref1('RAGE','Other','Duck peek assist'),
  force_baim = ref1('RAGE','Aimbot','Force body aim'),
  force_sp = ref1('RAGE','Aimbot','Force safe point'),
  dmg_override = refN('RAGE','Aimbot','Minimum damage override')
}

-- ========= UI =========
pui.accent = '89F596FF'
local cond_full = { 'Global','Stand','Walking','Running','Air','Air+','Duck','Duck+Move' }
local cond_short = { 'G','S','W','R','A','A+','D','D+' }

local group_main = pui.group('aa','anti-aimbot angles')
local group_vis = pui.group('aa','other')

local menu = {
  header = group_main:label('KY-yaw'),
  tab = group_main:combobox('Tab', {'Anti-Aim','Visuals'}),
  aa = {
    subtab = group_main:combobox('Anti-Aim Tab', {'Main','Builder'}),
    yaw_dir_modes = group_main:multiselect('Yaw Direction', {'Freestanding','Manual'}),
    hotkey_fs = group_main:hotkey('Freestanding Hotkey'),
    hotkey_left = group_main:hotkey('Manual Left'),
    hotkey_right = group_main:hotkey('Manual Right'),
    hotkey_forward = group_main:hotkey('Manual Forward'),
    yaw_base = group_main:combobox('Yaw Base', {'Local view','At targets'}),
    condition = group_main:combobox('Condition', cond_full),
    helpers = group_main:multiselect('Helpers', {'Safe Head','Anti-Knife'}),
  },
  visuals = {
    cross = group_vis:checkbox('Crosshair Indicators', {170,255,170}),
    cross_style = group_vis:combobox('Indicator Style', {'Default','Modern'}),
    manual_arrows = group_vis:checkbox('Manual Arrows', {170,255,170}),
    arrow_size = group_vis:slider('Arrow Size', 6, 24, 12, true, 'px', 1),
    arrow_offset = group_vis:slider('Arrow Offset', 20, 100, 40, true, 'px', 1),
  }
}

-- Per-condition builder
local builder = {}
for i = 1, #cond_full do
  local s = cond_short[i]
  builder[i] = {
    label = group_main:label('· ' .. cond_full[i]),
    enable = group_main:checkbox(s .. ' · Enable'),
    -- yaw
    yaw_mode = group_main:combobox(s .. ' · Yaw Mode', {'Default','Spin','Freestand','Manual'}),
    yaw_left = group_main:slider(s .. ' · Yaw Left', -180, 180, -9, true, '°', 1),
    yaw_right = group_main:slider(s .. ' · Yaw Right', -180, 180, 9, true, '°', 1),
    yaw_random = group_main:slider(s .. ' · Yaw Random %', 0, 100, 0, true, '%', 1),
    yaw_delay = group_main:slider(s .. ' · Delay Ticks', 1, 10, 4, true, 't', 1),
    -- jitter
    jitter_type = group_main:combobox(s .. ' · Jitter Type', {'Off','Offset','Center','Random','3-way','5-way','7-way'}),
    jitter_amount = group_main:slider(s .. ' · Jitter Amount', -180, 180, 0, true, '°', 1),
    j3_1 = group_main:slider(s .. ' · 3-way A1', -180, 180, -45, true, '°', 1),
    j3_2 = group_main:slider(s .. ' · 3-way A2', -180, 180, 0, true, '°', 1),
    j3_3 = group_main:slider(s .. ' · 3-way A3', -180, 180, 45, true, '°', 1),
    j5_1 = group_main:slider(s .. ' · 5-way A1', -180, 180, -80, true, '°', 1),
    j5_2 = group_main:slider(s .. ' · 5-way A2', -180, 180, -40, true, '°', 1),
    j5_3 = group_main:slider(s .. ' · 5-way A3', -180, 180, 0, true, '°', 1),
    j5_4 = group_main:slider(s .. ' · 5-way A4', -180, 180, 40, true, '°', 1),
    j5_5 = group_main:slider(s .. ' · 5-way A5', -180, 180, 80, true, '°', 1),
    j7_1 = group_main:slider(s .. ' · 7-way A1', -180, 180, -90, true, '°', 1),
    j7_2 = group_main:slider(s .. ' · 7-way A2', -180, 180, -60, true, '°', 1),
    j7_3 = group_main:slider(s .. ' · 7-way A3', -180, 180, -30, true, '°', 1),
    j7_4 = group_main:slider(s .. ' · 7-way A4', -180, 180, 0, true, '°', 1),
    j7_5 = group_main:slider(s .. ' · 7-way A5', -180, 180, 30, true, '°', 1),
    j7_6 = group_main:slider(s .. ' · 7-way A6', -180, 180, 60, true, '°', 1),
    j7_7 = group_main:slider(s .. ' · 7-way A7', -180, 180, 90, true, '°', 1),
    -- body
    body_type = group_main:combobox(s .. ' · Body Yaw', {'Off','Opposite','Jitter','Static'}),
    body_amount = group_main:slider(s .. ' · Body Amount', -180, 180, 1, true, '°', 1),
    -- pitch
    pitch_mode = group_main:combobox(s .. ' · Pitch', {'Off','Custom','Meta','Random'}),
    pitch_value = group_main:slider(s .. ' · Pitch Value', -89, 89, 0, true, '°', 1),
    -- defensive
    def_enable = group_main:checkbox(s .. ' · Defensive'),
    def_when = group_main:multiselect(s .. ' · Defensive When', {'Scoped Enemy','Charged DT','On Peek','Threat Shot'}),
    def_type = group_main:combobox(s .. ' · Defensive Yaw', {'Default','Spin','Meta','Random'}),
    def_value = group_main:slider(s .. ' · Defensive Amount', -180, 180, 9, true, '°', 1),
  }
end

-- Visibility deps
local tabs = {
  aa = {menu.tab, 'Anti-Aim'},
  vis = {menu.tab, 'Visuals'}
}

menu.aa.subtab:depend(tabs.aa)
menu.aa.yaw_dir_modes:depend(tabs.aa)
menu.aa.hotkey_fs:depend(tabs.aa, {menu.aa.yaw_dir_modes,'Freestanding'})
menu.aa.hotkey_left:depend(tabs.aa, {menu.aa.yaw_dir_modes,'Manual'})
menu.aa.hotkey_right:depend(tabs.aa, {menu.aa.yaw_dir_modes,'Manual'})
menu.aa.hotkey_forward:depend(tabs.aa, {menu.aa.yaw_dir_modes,'Manual'})
menu.aa.yaw_base:depend(tabs.aa)
menu.aa.condition:depend(tabs.aa, {menu.aa.subtab,'Builder'})
menu.aa.helpers:depend(tabs.aa)

menu.visuals.cross:depend(tabs.vis)
menu.visuals.cross_style:depend(tabs.vis, {menu.visuals.cross, true})
menu.visuals.manual_arrows:depend(tabs.vis, {menu.visuals.cross, true})
menu.visuals.arrow_size:depend(tabs.vis, {menu.visuals.manual_arrows, true})
menu.visuals.arrow_offset:depend(tabs.vis, {menu.visuals.manual_arrows, true})

for i = 1, #cond_full do
  local cond_only = {menu.aa.condition, cond_full[i]}
  local in_builder = {menu.aa.subtab, 'Builder'}
  local enabled_or_global = {builder[i].enable, function() return (i == 1) or builder[i].enable:get() end}

  builder[i].label:depend(tabs.aa, in_builder, cond_only)
  builder[i].enable:depend(tabs.aa, in_builder, cond_only)

  builder[i].yaw_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_left:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_right:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_random:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].yaw_delay:depend(tabs.aa, in_builder, cond_only, enabled_or_global)

  builder[i].jitter_type:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].jitter_amount:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].jitter_type, function()
    local t = builder[i].jitter_type:get(); return t ~= 'Off' and t ~= 'Center' and t ~= '3-way' and t ~= '5-way' and t ~= '7-way' end})

  builder[i].j3_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'3-way'})
  builder[i].j3_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'3-way'})
  builder[i].j3_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'3-way'})

  builder[i].j5_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'5-way'})
  builder[i].j5_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'5-way'})
  builder[i].j5_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'5-way'})
  builder[i].j5_4:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'5-way'})
  builder[i].j5_5:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'5-way'})

  builder[i].j7_1:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_2:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_3:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_4:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_5:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_6:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})
  builder[i].j7_7:depend(tabs.aa, in_builder, cond_only, {builder[i].jitter_type,'7-way'})

  builder[i].body_type:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].body_amount:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].body_type, function()
    return builder[i].body_type:get() ~= 'Off' and builder[i].body_type:get() ~= 'Opposite'
  end})

  builder[i].pitch_mode:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].pitch_value:depend(tabs.aa, in_builder, cond_only, enabled_or_global, {builder[i].pitch_mode,'Custom'})

  builder[i].def_enable:depend(tabs.aa, in_builder, cond_only, enabled_or_global)
  builder[i].def_when:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_type:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
  builder[i].def_value:depend(tabs.aa, in_builder, cond_only, {builder[i].def_enable, true})
end

-- ========= Helpers/State =========
local screen_w, screen_h = client.screen_size()
local cx, cy = screen_w / 2, screen_h / 2

local function hide_original_menu(state)
  ui.set_visible(ref.enabled, state)
  ui.set_visible(ref.yaw_base, state)
  ui.set_visible(ref.pitch[1], state)
  if ref.pitch[2] then ui.set_visible(ref.pitch[2], state) end
  ui.set_visible(ref.yaw[1], state)
  if ref.yaw[2] then ui.set_visible(ref.yaw[2], state) end
  ui.set_visible(ref.yaw_jitter[1], state)
  if ref.yaw_jitter[2] then ui.set_visible(ref.yaw_jitter[2], state) end
  ui.set_visible(ref.body_yaw[1], state)
  if ref.body_yaw[2] then ui.set_visible(ref.body_yaw[2], state) end
  ui.set_visible(ref.fs_body, state)
  ui.set_visible(ref.edge_yaw, state)
  if ref.roll[1] then ui.set_visible(ref.roll[1], state) end
end

local function players_vulnerable()
  for _, enemy in ipairs(entity.get_players(true)) do
    local esp = entity.get_esp_data(enemy)
    if esp and esp.flags and bit.band(esp.flags, bit.lshift(1, 11)) ~= 0 then
      return true
    end
  end
  return false
end

local function doubletap_charged()
  if not ui.get(ref.dt[1]) or not ui.get(ref.dt[2]) then return false end
  if ui.get(ref.fd) then return false end
  local lp = entity.get_local_player()
  if not lp or not entity.is_alive(lp) then return false end
  local weapon = entity.get_prop(lp, 'm_hActiveWeapon')
  if weapon == nil then return false end
  local next_attack = (entity.get_prop(lp, 'm_flNextAttack') or 0) + 0.01
  local next_primary_attack = (entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0) + 0.01
  return (next_attack - globals.curtime() < 0) and (next_primary_attack - globals.curtime() < 0)
end

-- threat shot window
_G.__ky_threat_until = _G.__ky_threat_until or 0

local function player_state(cmd)
  local lp = entity.get_local_player(); if not lp then return 'Global' end
  local vx = entity.get_prop(lp, 'm_vecVelocity[0]') or 0
  local vy = entity.get_prop(lp, 'm_vecVelocity[1]') or 0
  local speed = math.sqrt(vx*vx + vy*vy)
  local flags = entity.get_prop(lp, 'm_fFlags') or 0
  local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
  local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7 or (ref.fd and ui.get(ref.fd))
  local slowwalk_key = ui.get(ref.slow[1]) and ui.get(ref.slow[2])

  if jumping and ducked then return 'Air+'
  elseif jumping then return 'Air'
  elseif ducked and speed > 10 then return 'Duck+Move'
  elseif ducked and speed <= 10 then return 'Duck'
  elseif slowwalk_key and speed > 10 then return 'Walking'
  elseif speed > 80 then return 'Running'
  elseif speed <= 80 then return 'Stand'
  else return 'Global' end
end

local yaw_direction, last_press_time = 0, 0
local function apply_direction()
  ui.set(ref.fs[1], menu.aa.yaw_dir_modes:get('Freestanding'))
  ui.set(ref.fs[2], menu.aa.hotkey_fs:get() and 'Always on' or 'On hotkey')
  if yaw_direction ~= 0 then ui.set(ref.fs[1], false) end
end

local function handle_manual_direction()
  local now = globals.curtime()
  if menu.aa.yaw_dir_modes:get('Manual') and menu.aa.hotkey_right:get() and last_press_time + 0.2 < now then
    yaw_direction = (yaw_direction == 90) and 0 or 90; last_press_time = now
  elseif menu.aa.yaw_dir_modes:get('Manual') and menu.aa.hotkey_left:get() and last_press_time + 0.2 < now then
    yaw_direction = (yaw_direction == -90) and 0 or -90; last_press_time = now
  elseif menu.aa.yaw_dir_modes:get('Manual') and menu.aa.hotkey_forward:get() and last_press_time + 0.2 < now then
    yaw_direction = (yaw_direction == 180) and 0 or 180; last_press_time = now
  elseif last_press_time > now then last_press_time = now end
end

local tick_gate, toggle_jitter = 0, false
local function multiway_from_menu(conf)
  local jt = conf.jitter_type:get()
  if jt == '3-way' then return { conf.j3_1:get(), conf.j3_2:get(), conf.j3_3:get() } end
  if jt == '5-way' then return { conf.j5_1:get(), conf.j5_2:get(), conf.j5_3:get(), conf.j5_4:get(), conf.j5_5:get() } end
  if jt == '7-way' then return { conf.j7_1:get(), conf.j7_2:get(), conf.j7_3:get(), conf.j7_4:get(), conf.j7_5:get(), conf.j7_6:get(), conf.j7_7:get() } end
  return nil
end

local function map_jitter_type(jt)
  if jt == '3-way' or jt == '5-way' or jt == '7-way' then return 'Offset' end
  return jt
end

local function apply_pitch(mode, value, desync_side)
  ui.set(ref.pitch[1], 'Custom')
  if mode == 'Off' then ui.set(ref.pitch[2], 89)
  elseif mode == 'Custom' then ui.set(ref.pitch[2], value)
  elseif mode == 'Meta' then ui.set(ref.pitch[2], desync_side and 49 or -49)
  elseif mode == 'Random' then ui.set(ref.pitch[2], math.random(-89, 89)) end
end

local function set_safe_head_defaults()
  ui.set(ref.yaw_jitter[1], 'Off')
  ui.set(ref.yaw[1], '180')
  ui.set(ref.body_yaw[1], 'Static')
  ui.set(ref.body_yaw[2], 1)
  ui.set(ref.yaw[2], 14)
  ui.set(ref.pitch[1], 'Custom')
  ui.set(ref.pitch[2], 89)
end

-- ========= Core AA =========
local cond_idx = 1
local function aa_apply(cmd)
  local lp = entity.get_local_player(); if not lp or not entity.is_alive(lp) then return end

  -- condition selection
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

  -- base resets
  if ref.roll[1] then ui.set(ref.roll[1], 0) end
  ui.set(ref.enabled, true)
  ui.set(ref.fs_body, false)
  ui.set(ref.edge_yaw, false)
  ui.set(ref.yaw_base, menu.aa.yaw_base:get())
  ui.set(ref.pitch[1], 'Custom')

  -- direction controls
  handle_manual_direction()
  apply_direction()

  -- robust jitter tick gating
  if globals.tickcount() > tick_gate + conf.yaw_delay:get() then
    if cmd.chokedcommands == 0 then toggle_jitter = not toggle_jitter; tick_gate = globals.tickcount() end
  elseif globals.tickcount() < tick_gate then
    tick_gate = globals.tickcount()
  end

  -- compute desync side from body yaw pose param
  local desync_pose = (entity.get_prop(lp, 'm_flPoseParameter', 11) or 0) * 120 - 60
  local desync_on_right = desync_pose > 0

  -- jitter
  local jt = conf.jitter_type:get()
  ui.set(ref.yaw_jitter[1], map_jitter_type(jt))
  if jt == 'Random' then
    ui.set(ref.yaw_jitter[2], math.random(-180, 180))
  elseif jt == 'Center' or jt == 'Offset' then
    ui.set(ref.yaw_jitter[2], conf.jitter_amount:get())
  else
    local seq = multiway_from_menu(conf)
    if seq then
      local idx = (globals.tickcount() % #seq) + 1
      ui.set(ref.yaw_jitter[2], seq[idx])
    else
      ui.set(ref.yaw_jitter[2], 0)
    end
  end

  -- body yaw
  ui.set(ref.body_yaw[1], conf.body_type:get())
  if conf.body_type:get() == 'Static' then
    ui.set(ref.body_yaw[2], conf.body_amount:get())
  elseif conf.body_type:get() == 'Jitter' then
    ui.set(ref.body_yaw[2], (globals.tickcount() % 2 == 0) and conf.body_amount:get() or -conf.body_amount:get())
  else
    ui.set(ref.body_yaw[2], 0)
  end

  -- yaw mode
  local yaw_amount = 0
  if conf.yaw_mode:get() == 'Spin' then
    ui.set(ref.yaw[1], 'Spin')
  else
    ui.set(ref.yaw[1], '180')
  end

  -- compute yaw amount based on manual/freestand/randomized offsets
  if conf.yaw_mode:get() == 'Freestand' then
    ui.set(ref.fs[1], true)
    yaw_amount = 0
  elseif conf.yaw_mode:get() == 'Manual' and yaw_direction ~= 0 then
    yaw_amount = yaw_direction
  else
    local base = desync_on_right and conf.yaw_left:get() or conf.yaw_right:get()
    local rand = conf.yaw_random:get() / 100
    if rand > 0 then
      base = base + (base * rand) * (math.random() - 0.5) * 2
    end
    yaw_amount = base
  end

  -- defensive conditions
  local act_scoped = conf.def_when:get('Scoped Enemy') and players_vulnerable()
  local act_charged = conf.def_when:get('Charged DT') and doubletap_charged()
  local act_peek = conf.def_when:get('On Peek') and (globals.tickcount() % 10 == 0)
  local act_threat = conf.def_when:get('Threat Shot') and (_G.__ky_threat_until > globals.curtime())
  local defensive_now = conf.def_enable:get() and (act_scoped or act_charged or act_peek or act_threat)
  cmd.force_defensive = defensive_now

  -- pitch
  if defensive_now then
    if conf.def_type:get() == 'Spin' then
      ui.set(ref.yaw[1], 'Spin')
    end
    apply_pitch('Meta', 0, desync_on_right)
  else
    apply_pitch(conf.pitch_mode:get(), conf.pitch_value:get(), desync_on_right)
  end

  ui.set(ref.yaw[2], (yaw_direction ~= 0) and yaw_direction or clamp(yaw_amount, -180, 180))

  -- helpers
  if menu.aa.helpers:get('Safe Head') then
    local weapon = entity.get_player_weapon(lp)
    if weapon then
      local flags = entity.get_prop(lp, 'm_fFlags') or 0
      local jumping = bit.band(flags, 1) == 0 or cmd.in_jump == 1
      local ducked = (entity.get_prop(lp, 'm_flDuckAmount') or 0) > 0.7
      local class = entity.get_classname(weapon)
      if jumping and ducked and (class == 'CKnife' or class == 'CWeaponTaser') then
        set_safe_head_defaults()
      end
    end
  end

  if menu.aa.helpers:get('Anti-Knife') then
    local lx, ly, lz = entity.get_prop(lp, 'm_vecOrigin')
    if lx then
      for _, enemy in ipairs(entity.get_players(true)) do
        local w = entity.get_player_weapon(enemy)
        if w and entity.get_classname(w) == 'CKnife' then
          local ex, ey, ez = entity.get_prop(enemy, 'm_vecOrigin')
          if ex then
            local dx, dy, dz = ex - lx, ey - ly, ez - lz
            if (dx*dx + dy*dy + dz*dz) <= (250*250) then
              ui.set(ref.yaw_base, 'At targets')
              ui.set(ref.yaw[2], 180)
            end
          end
        end
      end
    end
  end
end

-- ========= Visuals =========
local function indicator()
  if not menu.visuals.cross:get() then return end
  local lp = entity.get_local_player(); if not lp or not entity.is_alive(lp) then return end
  local r,g,b = menu.visuals.cross:get_color()
  local style = menu.visuals.cross_style:get()
  local main_flag = (style == 'Modern') and 'c-b' or 'c'
  renderer.text(cx, cy + 30, r, g, b, 255, main_flag, 0, 'KY-yaw')

  -- keys
  local offset = 40
  local key_r, key_g, key_b = r, g, b
  if ui.get(ref.dt[1]) and ui.get(ref.dt[2]) then
    renderer.text(cx, cy + offset, key_r, key_g, key_b, doubletap_charged() and 255 or 120, 'c', 0, 'dt')
    offset = offset + 10
  end
  if ui.get(ref.os[2]) then renderer.text(cx, cy + offset, key_r, key_g, key_b, 255, 'c', 0, 'onshot'); offset = offset + 10 end
  if ui.get(ref.fs[1]) and ui.get(ref.fs[2]) then renderer.text(cx, cy + offset, key_r, key_g, key_b, 255, 'c', 0, 'fs'); offset = offset + 10 end

  -- manual arrows
  if menu.visuals.manual_arrows:get() and menu.aa.yaw_dir_modes:get('Manual') then
    local ar = { menu.visuals.manual_arrows:get_color() }
    local size = menu.visuals.arrow_size:get()
    local dist = menu.visuals.arrow_offset:get()
    if yaw_direction == -90 then renderer.triangle(cx - dist, cy, cx - dist + size, cy - size/2, cx - dist + size, cy + size/2, ar[1], ar[2], ar[3], 200) end
    if yaw_direction == 90 then renderer.triangle(cx + dist, cy, cx + dist - size, cy - size/2, cx + dist - size, cy + size/2, ar[1], ar[2], ar[3], 200) end
    if yaw_direction == 180 then renderer.triangle(cx, cy - dist, cx - size/2, cy - dist + size, cx + size/2, cy - dist + size, ar[1], ar[2], ar[3], 200) end
  end
end

-- ========= Events =========
safe_callback('paint_ui', function()
  hide_original_menu(false)
end)

safe_callback('paint', function()
  if not menu.header:get() then return end
  indicator()
end)

safe_callback('setup_command', function(cmd)
  if not menu.header:get() then return end
  aa_apply(cmd)
end)

safe_callback('bullet_impact', function(e)
  local lp = entity.get_local_player(); if not lp or not entity.is_alive(lp) then return end
  local ent = client.userid_to_entindex(e.userid); if not ent then return end
  if entity.is_dormant(ent) or not entity.is_enemy(ent) then return end
  local A = { entity.get_prop(ent, 'm_vecOrigin') }
  A[3] = (A[3] or 0) + (entity.get_prop(ent, 'm_vecViewOffset[2]') or 0)
  local B = { e.x, e.y, e.z }
  local P = { entity.hitbox_position(lp, 0) }
  if not (A[1] and B[1] and P[1]) then return end
  local a_to_p = { P[1]-A[1], P[2]-A[2] }
  local a_to_b = { B[1]-A[1], B[2]-A[2] }
  local atb2 = a_to_b[1]^2 + a_to_b[2]^2; if atb2 == 0 then return end
  local t = (a_to_p[1]*a_to_b[1] + a_to_p[2]*a_to_b[2]) / atb2
  local closest = { A[1] + a_to_b[1]*t, A[2] + a_to_b[2]*t }
  local dx,dy = P[1]-closest[1], P[2]-closest[2]
  local delta_2d = math.sqrt(dx*dx + dy*dy)
  if math.abs(delta_2d) <= 60 then _G.__ky_threat_until = globals.curtime() + 0.35 end
end)

safe_callback('shutdown', function()
  hide_original_menu(true)
end)

local out = {}
local function add(s) out[#out+1] = s end
local raw = data.raw
local V21 = helpers.compare_versions(mods["base"], "2.1.0") >= 0
add("base " .. mods["base"] .. (V21 and " (2.1-Syntax)" or " (2.0-Syntax)"))

local item_types = {}
for t, _ in pairs(defines.prototypes and defines.prototypes.item or {}) do item_types[#item_types+1] = t end
if #item_types == 0 then item_types = {"item","tool","ammo","capsule","gun","armor","module","item-with-entity-data","rail-planner","repair-tool","selection-tool","space-platform-starter-pack","spidertron-remote","blueprint","blueprint-book","copy-paste-tool","deconstruction-item","upgrade-item","item-with-inventory","item-with-label","item-with-tags"} end
local function item_exists(n) for _, t in ipairs(item_types) do if raw[t] and raw[t][n] then return true end end return false end
local function thing_exists(kind, n) if kind == "fluid" then return raw.fluid[n] ~= nil end return item_exists(n) end

-- own prototypes: everything whose name mentions arrakis/spice/melange or a few known names
local own = {}
local function is_own(n) return n:find("arrakis") or n:find("spice") or n:find("melange") end
for t, ps in pairs(raw) do for n, p in pairs(ps) do if type(n) == "string" and is_own(n) then own[#own+1] = t .. ":" .. n end end end
add("eigene Prototypen: " .. #own)

for n, r in pairs(raw.recipe) do if is_own(n) then
  for _, i in ipairs(r.ingredients or {}) do if not thing_exists(i.type, i.name) then add("FEHLER recipe " .. n .. " ingredient " .. i.name) end end
  for _, i in ipairs(r.results or {}) do if not thing_exists(i.type, i.name) then add("FEHLER recipe " .. n .. " result " .. i.name) end
    if V21 and i.probability then add("FEHLER 2.1 recipe " .. n .. " probability") end end
  local cats = r.categories or {r.category or "crafting"}
  if V21 and r.category then add("FEHLER 2.1 recipe " .. n .. " category") end
  if not V21 and r.categories then add("FEHLER 2.0 recipe " .. n .. " categories") end
  for _, c in ipairs(cats) do
    if not raw["recipe-category"][c] then add("FEHLER recipe " .. n .. " category " .. c) end
    local found = false
    for _, mt in ipairs({"assembling-machine","furnace","rocket-silo","character"}) do
      for _, m in pairs(raw[mt] or {}) do for _, mc in ipairs(m.crafting_categories or {}) do if mc == c then found = true end end end
    end
    if not found then add("WARN recipe " .. n .. ": keine Maschine für Kategorie " .. c) end
  end
end end

for n, t in pairs(raw.technology) do if is_own(n) then
  for _, e in ipairs(t.effects or {}) do if e.type == "unlock-recipe" and not raw.recipe[e.recipe] then add("FEHLER tech " .. n .. " recipe " .. e.recipe) end end
  for _, p in ipairs(t.prerequisites or {}) do if not raw.technology[p] then add("FEHLER tech " .. n .. " prereq " .. p) end end
  if t.unit then for _, i in ipairs(t.unit.ingredients or {}) do local nm = i[1] or i.name if not item_exists(nm) then add("FEHLER tech " .. n .. " pack " .. tostring(nm)) end end end
  local tr = t.research_trigger
  if tr and tr.type == "mine-entity" then
    if V21 and (tr.entity or not tr.entities) then add("FEHLER 2.1 tech " .. n .. " trigger") end
    if not V21 and (tr.entities or not tr.entity) then add("FEHLER 2.0 tech " .. n .. " trigger") end
    for _, e in ipairs(tr.entities or {tr.entity}) do if not raw.resource[e] then add("FEHLER tech " .. n .. " trigger entity " .. e) end end
  end
  if tr and tr.type == "craft-item" then local it = type(tr.item) == "table" and tr.item.name or tr.item if not item_exists(it) then add("FEHLER tech " .. n .. " trigger item") end end
end end

for n, r in pairs(raw.resource) do if is_own(n) then
  local m = r.minable or {}
  for _, x in ipairs(m.results or {}) do if not thing_exists(x.type, x.name) then add("FEHLER resource " .. n .. " result " .. x.name) end
    if V21 and x.probability then add("FEHLER 2.1 resource " .. n .. " probability") end end
  if m.result and not item_exists(m.result) then add("FEHLER resource " .. n .. " result " .. m.result) end
  local cat = r.category or "basic-solid"
  if not raw["resource-category"][cat] then add("FEHLER resource " .. n .. " category " .. cat) end
end end

-- placeable items, entity minable results, autoplace references
for _, t in ipairs(item_types) do for n, it in pairs(raw[t] or {}) do if is_own(n) then
  if it.place_result then local ok = false for _, ps in pairs(raw) do if ps[it.place_result] and ps[it.place_result].collision_box ~= nil then ok = true end end
    if not ok then add("FEHLER item " .. n .. " place_result " .. it.place_result) end end
  if it.spoil_result and not item_exists(it.spoil_result) then add("FEHLER item " .. n .. " spoil_result") end
  if V21 and it.fuel_category then add("WARN 2.1 item " .. n .. " fuel_category") end
  if it.fuel_category and not raw["fuel-category"][it.fuel_category] then add("FEHLER item " .. n .. " fuel_category " .. it.fuel_category) end
  for _, fc in ipairs(it.fuel_categories or {}) do if not raw["fuel-category"][fc] then add("FEHLER item " .. n .. " fuel_categories " .. fc) end end
end end end

for t, ps in pairs(raw) do for n, p in pairs(ps) do if type(p) == "table" and is_own(n) then
  if p.minable and p.minable.result and not item_exists(p.minable.result) then add("FEHLER " .. t .. " " .. n .. " minable.result " .. p.minable.result) end
  if p.fixed_recipe and not raw.recipe[p.fixed_recipe] then add("FEHLER " .. t .. " " .. n .. " fixed_recipe") end
  for _, c in ipairs(p.crafting_categories or {}) do if not raw["recipe-category"][c] then add("FEHLER " .. t .. " " .. n .. " crafting_category " .. c) end end
  for _, c in ipairs(p.resource_categories or {}) do if not raw["resource-category"][c] then add("FEHLER " .. t .. " " .. n .. " resource_category " .. c) end end
  if p.energy_source and p.energy_source.fuel_categories then for _, c in ipairs(p.energy_source.fuel_categories) do if not raw["fuel-category"][c] then add("FEHLER " .. t .. " " .. n .. " burner fuel " .. c) end end end
  if p.collision_mask and p.collision_mask.layers then for l in pairs(p.collision_mask.layers) do if not raw["collision-layer"][l] then add("FEHLER " .. t .. " " .. n .. " collision layer " .. l) end end end
  for _, rule in ipairs(p.tile_buildability_rules or {}) do
    if not rule.area then add("FEHLER " .. t .. " " .. n .. " tile_buildability_rules ohne area") end
    for _, key in ipairs({"required_tiles", "colliding_tiles"}) do
      for l in pairs(rule[key] and rule[key].layers or {}) do if not raw["collision-layer"][l] then add("FEHLER " .. t .. " " .. n .. " " .. key .. " layer " .. l) end end
    end
  end
end end end

for n, tile in pairs(raw.tile) do if is_own(n) and tile.collision_mask then for l in pairs(tile.collision_mask.layers or {}) do if not raw["collision-layer"][l] then add("FEHLER tile " .. n .. " layer " .. l) end end end end

-- Referenzen in Trigger-Effekten eigener Prototypen (z. B. kopierte Wurm-Effekte)
local entity_types = {}
for t in pairs(defines.prototypes and defines.prototypes.entity or {}) do entity_types[#entity_types+1] = t end
local function entity_exists(n)
  if #entity_types == 0 then for _, ps in pairs(raw) do if ps[n] then return true end end return false end
  for _, t in ipairs(entity_types) do if raw[t] and raw[t][n] then return true end end
  return false
end
local function in_raw(t) return function(n) return raw[t] ~= nil and raw[t][n] ~= nil end end
local ref_checks = {
  ["create-entity"] = {"entity_name", entity_exists},
  ["create-smoke"] = {"entity_name", entity_exists},
  ["create-explosion"] = {"entity_name", entity_exists},
  ["create-fire"] = {"entity_name", entity_exists},
  ["create-trivial-smoke"] = {"smoke_name", in_raw("trivial-smoke")},
  ["create-particle"] = {"particle_name", in_raw("optimized-particle")},
  ["create-sticker"] = {"sticker", in_raw("sticker")},
}
local function walk_refs(where, node, seen)
  if type(node) ~= "table" or seen[node] then return end
  seen[node] = true
  local rc = type(node.type) == "string" and ref_checks[node.type]
  if rc then
    local ref = node[rc[1]]
    if type(ref) == "string" and not rc[2](ref) then add("FEHLER " .. where .. " " .. node.type .. " " .. ref) end
  end
  if node.type == "delayed" and type(node.delayed_trigger) == "string" and not in_raw("delayed-active-trigger")(node.delayed_trigger) then
    add("FEHLER " .. where .. " delayed_trigger " .. node.delayed_trigger)
  end
  for _, v in pairs(node) do walk_refs(where, v, seen) end
end
for _, t in ipairs(entity_types) do for n, p in pairs(raw[t] or {}) do if is_own(n) then
  walk_refs(t .. " " .. n, p, {})
  if p.corpse and not entity_exists(p.corpse) then add("FEHLER " .. t .. " " .. n .. " corpse " .. p.corpse) end
  if p.dying_explosion and type(p.dying_explosion) == "string" and not entity_exists(p.dying_explosion) then add("FEHLER " .. t .. " " .. n .. " dying_explosion " .. p.dying_explosion) end
end end end

-- Spinnenbeine: vorhanden, Positionen gesetzt, Laufgruppen ab 1 lückenlos
for n, p in pairs(raw["spider-vehicle"] or {}) do if is_own(n) then
  local legs = p.spider_engine and p.spider_engine.legs
  if not legs then add("FEHLER spider " .. n .. " ohne spider_engine.legs") else
    if legs.leg then legs = {legs} end
    local groups, max_group = {}, 0
    for i, leg in ipairs(legs) do
      if not raw["spider-leg"][leg.leg or ""] then add("FEHLER spider " .. n .. " leg " .. tostring(leg.leg)) end
      if not leg.mount_position or not leg.ground_position then add("FEHLER spider " .. n .. " Bein " .. i .. " ohne mount/ground_position") end
      local g = leg.walking_group
      if type(g) ~= "number" or g < 1 then add("FEHLER spider " .. n .. " Bein " .. i .. " walking_group " .. tostring(g))
      else groups[g] = true if g > max_group then max_group = g end end
    end
    for g = 1, max_group do if not groups[g] then add("FEHLER spider " .. n .. " walking_group " .. g .. " fehlt") end end
    if #legs == 0 then add("FEHLER spider " .. n .. " ohne Beine") end
  end
  for _, fc in ipairs(p.energy_source and p.energy_source.fuel_categories or {}) do if not raw["fuel-category"][fc] then add("FEHLER spider " .. n .. " fuel_category " .. fc) end end
  if p.tall then add("FEHLER spider " .. n .. " tall gesetzt") end
end end

-- Segmentierte Einheiten: Segmentnamen, Anzahl (höchstens 63)
for n, p in pairs(raw["segmented-unit"] or {}) do if is_own(n) then
  local segs = p.segment_engine and p.segment_engine.segments or {}
  if #segs == 0 or #segs > 63 then add("FEHLER segmented-unit " .. n .. " " .. #segs .. " Segmente") end
  for i, s in ipairs(segs) do if not raw.segment[s.segment or ""] then add("FEHLER segmented-unit " .. n .. " Segment " .. i .. " " .. tostring(s.segment)) end end
  add(string.format("Wurm %s: %d Segmente, investigating %.2f, attacking %.2f Kacheln/s", n, #segs, p.investigating_speed * 60, p.attacking_speed * 60))
end end

-- Prüfstand-Würmer: keine Ascheeffekte mehr (Ascheschwaden/Sticker, Spuren, destroy-cliffs)
local ash_patterns = {"ash%-cloud", "ash%-sticker", "%-trail%-upper", "%-trail%-lower"}
local function has_ash(node, seen)
  if type(node) ~= "table" or seen[node] then return false end
  seen[node] = true
  if node.type == "destroy-cliffs" or node.type == "create-sticker" then return true end
  for _, key in ipairs({"entity_name", "smoke_name", "sticker", "delayed_trigger"}) do
    if type(node[key]) == "string" then for _, pat in ipairs(ash_patterns) do if node[key]:find(pat) then return true end end end
  end
  for _, v in pairs(node) do if has_ash(v, seen) then return true end end
  return false
end
for _, t in ipairs({"segmented-unit", "segment"}) do for n, p in pairs(raw[t] or {}) do if n:find("^arrakis%-test%-worm") then
  if has_ash(p.update_effects, {}) or p.update_effects_while_enraged then add("FEHLER " .. t .. " " .. n .. " hat noch Ascheeffekte") end
  if p.loot or p.corpse then add("FEHLER " .. t .. " " .. n .. " hat noch Beute/Leiche") end
end end end

-- Custom-Inputs und Sprites
for n, ci in pairs(raw["custom-input"] or {}) do if is_own(n) then
  if type(ci.key_sequence) ~= "string" then add("FEHLER custom-input " .. n .. " key_sequence") end
  if ci.item_to_spawn and not item_exists(ci.item_to_spawn) then add("FEHLER custom-input " .. n .. " item_to_spawn " .. ci.item_to_spawn) end
end end
for n, sp in pairs(raw.sprite or {}) do if is_own(n) then
  if not sp.filename and not sp.layers then add("FEHLER sprite " .. n .. " ohne filename/layers") end
end end

-- Kollisionsebene am Fels
if not raw["collision-layer"].arrakis_rock then add("FEHLER collision-layer arrakis_rock fehlt") end
local rock_tile = raw.tile["arrakis-rock"]
if not (rock_tile and rock_tile.collision_mask and rock_tile.collision_mask.layers.arrakis_rock) then add("FEHLER tile arrakis-rock ohne Ebene arrakis_rock") end

-- Phase 3b: Spice nur per Ernter und Hand, Ernter-Regeln, Brikett
local SPICE_CAT = "arrakis-spice-harvest"
local function has_value(list, value) for _, v in pairs(list or {}) do if v == value then return true end end return false end
local expected_3b = {
  ["resource-category"] = {SPICE_CAT},
  car = {"spice-harvester"},
  ["proxy-container"] = {"arrakis-spice-intake", "arrakis-fuel-nozzle"},
  ["item-with-entity-data"] = {"spice-harvester"},
  item = {"arrakis-spice-intake", "arrakis-fuel-nozzle", "arrakis-spice-briquette"},
  recipe = {"spice-harvester", "arrakis-spice-intake", "arrakis-fuel-nozzle", "arrakis-spice-briquette"},
  technology = {"arrakis-spice-harvesting"},
  ["custom-input"] = {"arrakis-harvester-toggle"},
}
for t, names in pairs(expected_3b) do for _, n in ipairs(names) do
  local p = raw[t] and raw[t][n]
  if not p then add("FEHLER 3b: " .. t .. " " .. n .. " fehlt")
  elseif p.hidden then add("FEHLER 3b: " .. t .. " " .. n .. " ist hidden") end
end end
local spice_res = raw.resource["spice-sand"]
if not spice_res or spice_res.category ~= SPICE_CAT then add("FEHLER resource spice-sand Kategorie " .. tostring(spice_res and spice_res.category) .. " statt " .. SPICE_CAT) end
local hand_miners = {}
for _, t in ipairs({"character", "god-controller"}) do for n, p in pairs(raw[t] or {}) do
  local cats = p.mining_categories or {"basic-solid"}
  if has_value(cats, "basic-solid") then
    if has_value(cats, SPICE_CAT) then hand_miners[#hand_miners+1] = t .. ":" .. n
    else add("FEHLER " .. t .. " " .. n .. " baut basic-solid ab, aber nicht " .. SPICE_CAT) end
  end
end end
table.sort(hand_miners)
if #hand_miners == 0 then add("FEHLER keine Spielfigur baut Spice von Hand ab") end
add("Spice von Hand: " .. table.concat(hand_miners, ","))
for n, p in pairs(raw["mining-drill"] or {}) do
  if has_value(p.resource_categories, SPICE_CAT) then add("FEHLER mining-drill " .. n .. " hat " .. SPICE_CAT) end
end
local spice_car = raw.car["spice-harvester"]
if spice_car then
  if spice_car.allow_remote_driving ~= false then add("FEHLER car spice-harvester allow_remote_driving " .. tostring(spice_car.allow_remote_driving)) end
  if spice_car.has_belt_immunity ~= true then add("FEHLER car spice-harvester has_belt_immunity " .. tostring(spice_car.has_belt_immunity)) end
  if spice_car.guns or spice_car.equipment_grid then add("FEHLER car spice-harvester hat Waffen oder Ausrüstungsgitter") end
  if spice_car.trash_inventory_size ~= 0 then add("FEHLER car spice-harvester trash_inventory_size " .. tostring(spice_car.trash_inventory_size)) end
  if spice_car.braking_power or spice_car.friction then add("FEHLER car spice-harvester braking_power/friction (2.1 kennt nur braking_force/friction_force)") end
end
local briquette = raw.item["arrakis-spice-briquette"]
if briquette then
  if briquette.fuel_value ~= "20MJ" then add("FEHLER item arrakis-spice-briquette fuel_value " .. tostring(briquette.fuel_value)) end
  for _, key in ipairs({"fuel_acceleration_multiplier", "fuel_top_speed_multiplier", "fuel_acceleration_multiplier_quality_bonus", "fuel_top_speed_multiplier_quality_bonus"}) do
    if briquette[key] ~= nil then add("FEHLER item arrakis-spice-briquette " .. key .. " gesetzt") end
  end
  if not has_value(briquette.fuel_categories or {briquette.fuel_category}, "chemical") then add("FEHLER item arrakis-spice-briquette nicht chemical") end
end
local briquette_recipe = raw.recipe["arrakis-spice-briquette"]
if briquette_recipe then
  if briquette_recipe.allow_productivity then add("FEHLER recipe arrakis-spice-briquette allow_productivity") end
  if not has_value(briquette_recipe.categories or {briquette_recipe.category}, "spice-refining") then add("FEHLER recipe arrakis-spice-briquette nicht in spice-refining") end
end

-- Prüfstand: Test-Prototypen nur mit Einstellung, alle versteckt, ohne Rezept/Item/Forschung
local tb_setting = settings.startup["arrakis-testbench"]
local tb_on = tb_setting and tb_setting.value
local tb_expected = {
  ["spider-leg"] = {"arrakis-test-flyer-leg", "arrakis-test-flyer-leg-fast"},
  ["spider-vehicle"] = {"arrakis-test-flyer-1", "arrakis-test-flyer-2", "arrakis-test-flyer-4", "arrakis-test-flyer-4-fast"},
  sticker = {"arrakis-test-load-sticker", "arrakis-test-load-sticker-move"},
  car = {"arrakis-test-harvester"},
  ["proxy-container"] = {"arrakis-test-intake", "arrakis-test-nozzle"},
  ["segmented-unit"] = {"arrakis-test-worm", "arrakis-test-worm-rockmask"},
  sprite = {"arrakis-test-carried", "arrakis-test-carried-shadow"},
  ["custom-input"] = {"arrakis-test-key"},
}
local tb_count = 0
local is_entity_type = {}
for _, t in ipairs(entity_types) do is_entity_type[t] = true end
for t, ps in pairs(raw) do for n, p in pairs(ps) do if type(n) == "string" and n:find("^arrakis%-test%-") then
  tb_count = tb_count + 1
  if not tb_on then add("FEHLER Prüfstand aus, aber " .. t .. " " .. n .. " vorhanden") end
  if is_entity_type[t] and p.hidden ~= true then add("FEHLER " .. t .. " " .. n .. " nicht hidden") end
  if t == "recipe" or t == "technology" or item_exists(n) then add("FEHLER Prüfstand: " .. t .. " " .. n .. " (keine Rezepte/Items/Forschung)") end
end end end
if tb_on then
  for t, names in pairs(tb_expected) do for _, n in ipairs(names) do
    if not (raw[t] and raw[t][n]) then add("FEHLER Prüfstand: " .. t .. " " .. n .. " fehlt") end
  end end
  -- Namen "arrakis-test-…" in den Laufzeitdateien müssen Prototypen sein (Tippfehler fallen sonst erst im Spiel auf).
  -- Keine Prototypen (z. B. Oberflächen) hier eintragen:
  local not_prototypes = {["arrakis-test-hold"] = true}
  local files = {"control.lua", "scripts/arrakis-surface.lua", "scripts/testbench/runner.lua", "scripts/testbench/t_flyer.lua",
    "scripts/testbench/t_harvester.lua", "scripts/testbench/t_worm.lua", "scripts/testbench/t_map.lua"}
  local read = 0
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      read = read + 1
      local text = f:read("*a")
      f:close()
      for name in text:gmatch("[\"'](arrakis%-test%-[%w%-_]+)[\"']") do
        local found = not_prototypes[name] or false
        if not found then for _, ps in pairs(raw) do if ps[name] then found = true break end end end
        if not found then add("FEHLER " .. file .. ": unbekannter Name " .. name) end
      end
    end
  end
  if read == 0 then add("WARN Laufzeitdateien nicht gefunden (aus dem Repo-Root starten)") end
end
add("Prüfstand " .. (tb_on and "an" or "aus") .. ": " .. tb_count .. " Test-Prototypen")

-- labs
local labs = {}
for n, l in pairs(raw.lab) do for _, i in ipairs(l.inputs or {}) do if i == "spice-science-pack" then labs[#labs+1] = n end end end
table.sort(labs); add("Labore mit Spice-Wissenschaft: " .. table.concat(labs, ","))
for n, l in pairs(raw.lab) do for _, i in ipairs(l.inputs or {}) do if not item_exists(i) then add("FEHLER lab " .. n .. " input " .. i) end end end

-- planet
local pl = raw.planet.arrakis
if not pl then add("FEHLER planet fehlt") else
  for k in pairs(pl.surface_properties or {}) do if not raw["surface-property"][k] then add("FEHLER planet surface_property " .. k) end end
  local mgs = pl.map_gen_settings or {}
  for k, v in pairs(mgs.property_expression_names or {}) do
    if type(v) == "string" and not raw["noise-expression"][v] and not v:match("^[%d%.%-]+$") then add("WARN planet expr " .. k .. " -> " .. v) end end
  for n in pairs((mgs.autoplace_settings or {}).entity and mgs.autoplace_settings.entity.settings or {}) do local ok = false for _, ps in pairs(raw) do if ps[n] and ps[n].autoplace then ok = true end end if not ok then add("FEHLER planet entity autoplace " .. n) end end
  for n in pairs((mgs.autoplace_settings or {}).tile and mgs.autoplace_settings.tile.settings or {}) do if not raw.tile[n] then add("FEHLER planet tile " .. n) end end
  for n in pairs(mgs.autoplace_controls or {}) do if not raw["autoplace-control"][n] then add("FEHLER planet control " .. n) end end
end
for n, sc in pairs(raw["space-connection"]) do if is_own(n) then if not raw.planet[sc.from] and not raw["space-location"][sc.from] then add("FEHLER connection from") end if not raw.planet[sc.to] and not raw["space-location"][sc.to] then add("FEHLER connection to") end end end

-- settings
for _, st in ipairs({"startup","runtime-global","runtime-per-user"}) do for n, s in pairs(settings[st] or {}) do if is_own(n) then add("Setting " .. st .. " " .. n .. " = " .. tostring(s.value)) end end end

-- inventory of own prototypes by type
local bytype = {}
for _, s in ipairs(own) do local t = s:match("^(.-):") bytype[t] = (bytype[t] or 0) + 1 end
local ts = {} for t, c in pairs(bytype) do ts[#ts+1] = t .. "=" .. c end table.sort(ts)
add("Typen: " .. table.concat(ts, " "))
return table.concat(out, "\n")

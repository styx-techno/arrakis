local out = {}
local function add(s) out[#out+1] = s end
local raw = data.raw
local V21 = helpers.compare_versions(mods["base"], "2.1.0") >= 0
local V2120 = helpers.compare_versions(mods["base"], "2.1.20") >= 0
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

-- 2.1.10: fulgoran-rock verweist in der Factoriopedia auf fulgoran-dust; die Kopie darf das nicht erben.
if raw.tile["arrakis-rock"] and raw.tile["arrakis-rock"].factoriopedia_alternative then add("FEHLER tile arrakis-rock factoriopedia_alternative " .. tostring(raw.tile["arrakis-rock"].factoriopedia_alternative)) end
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

-- Phase 3c (docs/plan-3c.md 3 und 7): Ornithopter, Forschung, Taste, Verknüpfungen, Sticker, Lastbild, Probe
local expected_3c = {
  ["spider-vehicle"] = {"arrakis-ornithopter"},
  ["item-with-entity-data"] = {"arrakis-ornithopter"},
  recipe = {"arrakis-ornithopter"},
  technology = {"arrakis-ornithopter"},
  ["custom-input"] = {"arrakis-carry-toggle"},
  shortcut = {"arrakis-carry", "arrakis-give-remote"},
}
for t, names in pairs(expected_3c) do for _, n in ipairs(names) do
  local p = raw[t] and raw[t][n]
  if not p then add("FEHLER 3c: " .. t .. " " .. n .. " fehlt")
  elseif p.hidden then add("FEHLER 3c: " .. t .. " " .. n .. " ist hidden") end
end end
local expected_3c_hidden = {
  ["spider-leg"] = {"arrakis-flyer-leg"},
  ["simple-entity-with-owner"] = {"arrakis-harvester-probe"},
}
for t, names in pairs(expected_3c_hidden) do for _, n in ipairs(names) do
  local p = raw[t] and raw[t][n]
  if not p then add("FEHLER 3c: " .. t .. " " .. n .. " fehlt")
  elseif p.hidden ~= true then add("FEHLER 3c: " .. t .. " " .. n .. " nicht hidden") end
end end
local function same_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local orni = raw["spider-vehicle"]["arrakis-ornithopter"]
if orni then
  if orni.allow_remote_driving ~= true then add("FEHLER 3c: arrakis-ornithopter allow_remote_driving " .. tostring(orni.allow_remote_driving)) end
  local legs = orni.spider_engine and orni.spider_engine.legs or {}
  if #legs ~= 4 then add("FEHLER 3c: arrakis-ornithopter hat " .. #legs .. " Beine statt 4") end
  local seen_legs = {}
  for i, leg in ipairs(legs) do
    if leg.leg ~= "arrakis-flyer-leg" then add("FEHLER 3c: arrakis-ornithopter Bein " .. i .. " ist " .. tostring(leg.leg)) end
    local lp = raw["spider-leg"][leg.leg or ""]
    if lp and not seen_legs[leg.leg] then
      seen_legs[leg.leg] = true
      local mask = lp.collision_mask
      if not (mask and mask.layers and next(mask.layers) == nil) then add("FEHLER 3c: Bein " .. leg.leg .. " ohne leere Kollisionsmaske") end
      if lp.graphics_set then add("FEHLER 3c: Bein " .. leg.leg .. " hat Grafik") end
    end
    if leg.leg_hit_the_ground_trigger then add("FEHLER 3c: arrakis-ornithopter Bein " .. i .. " mit Bodenstaub-Trigger") end
  end
  local es = orni.energy_source or {}
  if es.type ~= "burner" or not same_list(es.fuel_categories or {}, {V2120 and "arrakis-flight-fuel" or "chemical"}) or es.fuel_inventory_size ~= 2 then
    add("FEHLER 3c: arrakis-ornithopter Brenner " .. tostring(es.type) .. " " .. table.concat(es.fuel_categories or {}, ",") .. " Slots " .. tostring(es.fuel_inventory_size))
  end
  if orni.movement_energy_consumption ~= "800kW" then add("FEHLER 3c: arrakis-ornithopter movement_energy_consumption " .. tostring(orni.movement_energy_consumption)) end
  if orni.guns or orni.equipment_grid then add("FEHLER 3c: arrakis-ornithopter hat Waffen oder Ausrüstungsgitter") end
  if orni.trash_inventory_size ~= 0 then add("FEHLER 3c: arrakis-ornithopter trash_inventory_size " .. tostring(orni.trash_inventory_size)) end
  if not (orni.minable and orni.minable.result == "arrakis-ornithopter") then add("FEHLER 3c: arrakis-ornithopter minable.result " .. tostring(orni.minable and orni.minable.result)) end
  -- Körper ohne eigene Maske: Vorgabe nur trigger_target, der Ernter fährt darunter durch (Plan 3, U21).
  if orni.collision_mask ~= nil then add("FEHLER 3c: arrakis-ornithopter hat eine collision_mask") end
  if orni.tall then add("FEHLER 3c: arrakis-ornithopter tall gesetzt") end
  if orni.icon ~= "__arrakis__/graphics/icons/ornithopter.png" or orni.icon_size ~= 64 or orni.icons then add("FEHLER 0.8.9: arrakis-ornithopter ohne eigenes Symbol") end
  if orni.height ~= 3 or not (orni.graphics_set and orni.graphics_set.render_layer == "air-object") then add("FEHLER 3c: arrakis-ornithopter Flughöhe/render_layer") end
  -- Kein Feld, das auf den Spidertron zeigt, außer der gewollten Explosion (DOC 5.5).
  for _, key in ipairs({"factoriopedia_alternative", "factoriopedia_simulation", "fast_replaceable_group", "next_upgrade", "placeable_by"}) do
    if orni[key] ~= nil then add("FEHLER 3c: arrakis-ornithopter " .. key .. " geerbt") end
  end
end
local orni_item = raw["item-with-entity-data"]["arrakis-ornithopter"]
if orni_item then
  -- Ohne icon_tintable* zeigte ein Item mit gespeicherter Farbe das getönte Spidertron-Bild (Plan 3).
  if orni_item.icon ~= "__arrakis__/graphics/icons/ornithopter.png" or orni_item.icons then add("FEHLER 0.8.9: item arrakis-ornithopter ohne eigenes Symbol") end
  for _, key in ipairs({"icon_tintable", "icon_tintable_mask", "icon_tintable_size", "icon_tintable_mask_size", "icon_tintables", "icon_tintable_masks"}) do
    if orni_item[key] ~= nil then add("FEHLER 3c: item arrakis-ornithopter " .. key .. " gesetzt") end
  end
  if orni_item.place_result ~= "arrakis-ornithopter" then add("FEHLER 3c: item arrakis-ornithopter place_result " .. tostring(orni_item.place_result)) end
end
local orni_tech = raw.technology["arrakis-ornithopter"]
if orni_tech then
  local tr = orni_tech.research_trigger or {}
  local it = type(tr.item) == "table" and tr.item.name or tr.item
  if tr.type ~= "craft-item" or it ~= "spice-harvester" or (tr.count or 1) ~= 1 then add("FEHLER 3c: tech arrakis-ornithopter Trigger " .. tostring(tr.type) .. " " .. tostring(it) .. " " .. tostring(tr.count)) end
  if not has_value(orni_tech.prerequisites, "arrakis-spice-harvesting") then add("FEHLER 3c: tech arrakis-ornithopter ohne Voraussetzung arrakis-spice-harvesting") end
  if orni_tech.unit then add("FEHLER 3c: tech arrakis-ornithopter hat Paketkosten") end
  local unlocks = false
  for _, e in ipairs(orni_tech.effects or {}) do if e.type == "unlock-recipe" and e.recipe == "arrakis-ornithopter" then unlocks = true end end
  if not unlocks then add("FEHLER 3c: tech arrakis-ornithopter schaltet das Rezept nicht frei") end
end
local orni_recipe = raw.recipe["arrakis-ornithopter"]
if orni_recipe and orni_recipe.enabled ~= false then add("FEHLER 3c: recipe arrakis-ornithopter von Anfang an frei") end
-- Tempo-Sticker (0.6.1, docs/plan-3c.md 4.9 und 9): je Zustand eine Familie, eine Stufe t_j = 1,02^j je Sticker
-- (j = −35 … 70), Name mit p = floor(100 · t_j + 0,5), versteckt, vehicle_speed_modifier = BASE / t_j (BASE leer 0,603,
-- beladen 0,427), 216000 Ticks. Die Vertragswerte stehen hier fest wie 0,52 und 0,364 in 0.6.0: Weicht eine Konstante in
-- prototypes/ornithopter-speed.lua ab, FEHLER. Name und Modifier rechnet die Regel aus diesen Werten selbst nach, nicht
-- mit Konstanten oder Tabellen des Moduls; von dort nur parse, bucket und percent. Das Modul liest sie per loadfile (aus
-- dem Repo-Root wie die Laufzeitdateien unten). Die beiden Sticker aus 0.6.0 gibt es nicht mehr.
local PLAN_BASE = {empty = 0.603, loaded = 0.427}
local PLAN_STEP, PLAN_MIN_J, PLAN_MAX_J = 1.02, -35, 70
local speed_chunk = loadfile("prototypes/ornithopter-speed.lua")
local speed_ok, speed = false, nil
if speed_chunk then speed_ok, speed = pcall(speed_chunk) end
local speed_count = {empty = 0, loaded = 0}
if not (speed_ok and type(speed) == "table") then add("FEHLER 3c: prototypes/ornithopter-speed.lua nicht ladbar (aus dem Repo-Root starten): " .. tostring(speed))
else
  local plan_values = {{"BASE_EMPTY", PLAN_BASE.empty}, {"BASE_LOADED", PLAN_BASE.loaded}, {"STEP", PLAN_STEP}, {"MIN_J", PLAN_MIN_J}, {"MAX_J", PLAN_MAX_J}}
  for _, kv in ipairs(plan_values) do
    if speed[kv[1]] ~= kv[2] then add("FEHLER 3c: prototypes/ornithopter-speed.lua " .. kv[1] .. " = " .. tostring(speed[kv[1]]) .. " statt " .. kv[2] .. " (docs/plan-3c.md 9)") end
  end
  for _, state in ipairs({"empty", "loaded"}) do
    for j = PLAN_MIN_J, PLAN_MAX_J do
      local t = PLAN_STEP ^ j
      local n = "arrakis-ornithopter-" .. state .. "-" .. math.floor(100 * t + 0.5)
      local s = raw.sticker[n]
      if not s then add("FEHLER 3c: sticker " .. n .. " fehlt") else
        speed_count[state] = speed_count[state] + 1
        if s.hidden ~= true then add("FEHLER 3c: sticker " .. n .. " nicht hidden") end
        if type(s.vehicle_speed_modifier) ~= "number" or math.abs(s.vehicle_speed_modifier - PLAN_BASE[state] / t) > 1e-9 then add("FEHLER 3c: sticker " .. n .. " vehicle_speed_modifier " .. tostring(s.vehicle_speed_modifier) .. " statt " .. PLAN_BASE[state] / t) end
        if s.duration_in_ticks ~= 216000 then add("FEHLER 3c: sticker " .. n .. " duration_in_ticks " .. tostring(s.duration_in_ticks)) end
        local ln = s.localised_name
        if not (type(ln) == "table" and ln[1] == "entity-name.arrakis-ornithopter-" .. state) then add("FEHLER 3c: sticker " .. n .. " localised_name") end
        local parsed_state, parsed_j = speed.parse(n)
        if parsed_state ~= state or parsed_j ~= j then add("FEHLER 3c: speed.parse(" .. n .. ") = " .. tostring(parsed_state) .. ", " .. tostring(parsed_j)) end
      end
    end
    if speed_count[state] ~= 106 then add("FEHLER 3c: " .. speed_count[state] .. " Tempo-Sticker " .. state .. " statt 106") end
    -- Kohle (t = 1) und Raketentreibstoff (t = 1,15) wie im Plan
    for _, p in ipairs({100, 115}) do
      if not raw.sticker["arrakis-ornithopter-" .. state .. "-" .. p] then add("FEHLER 3c: sticker arrakis-ornithopter-" .. state .. "-" .. p .. " fehlt") end
    end
  end
  if speed.percent(speed.bucket(1)) ~= 100 or speed.percent(speed.bucket(1.15)) ~= 115 then add("FEHLER 3c: speed.bucket: Kohle oder Raketentreibstoff in falscher Stufe") end
  for n in pairs(raw.sticker) do
    if n:find("^arrakis%-ornithopter%-") and not speed.parse(n) then add("FEHLER 3c: sticker " .. n .. " gehört zu keiner Stufe") end
  end
end
for _, n in ipairs({"arrakis-ornithopter-empty", "arrakis-ornithopter-loaded"}) do
  if raw.sticker[n] then add("FEHLER 3c: sticker " .. n .. " aus 0.6.0 gibt es noch") end
end
-- Lastbild (ab 0.8.5): 16 Richtungen aus den Blättern des Ernters, je ein Bild ohne Ebenen; Rumpf 384 px mit scale 0.5,
-- Schatten 256 px mit scale 1 (Festlegungen in tools/grafik/README.md).
local sprite_count = 0
local harvester_gfx = "__arrakis__/graphics/entity/spice-harvester/"
for i = 0, 15 do
  for _, kind in ipairs({"image", "shadow"}) do
    local n = kind == "image" and ("arrakis-harvester-carried-" .. i) or ("arrakis-harvester-carried-shadow-" .. i)
    local sp = raw.sprite[n]
    if not sp then add("FEHLER 3c: sprite " .. n .. " fehlt") else
      sprite_count = sprite_count + 1
      local want = kind == "image" and {"harvester-base.png", 384, 0.5} or {"harvester-shadow.png", 256, 1}
      if sp.layers then add("FEHLER 3c: sprite " .. n .. " hat Ebenen") end
      if sp.filename ~= harvester_gfx .. want[1] then add("FEHLER 3c: sprite " .. n .. " Datei " .. tostring(sp.filename)) end
      if sp.width ~= want[2] or sp.height ~= want[2] then add("FEHLER 3c: sprite " .. n .. " Größe " .. tostring(sp.width)) end
      if sp.scale ~= want[3] then add("FEHLER 3c: sprite " .. n .. " scale " .. tostring(sp.scale)) end
      local d = 4 * i
      if sp.x ~= (d % 8) * want[2] or sp.y ~= math.floor(d / 8) * want[2] then add("FEHLER 3c: sprite " .. n .. " Ausschnitt " .. tostring(sp.x) .. "," .. tostring(sp.y)) end
      if (sp.draw_as_shadow == true) ~= (kind == "shadow") then add("FEHLER 3c: sprite " .. n .. " draw_as_shadow " .. tostring(sp.draw_as_shadow)) end
      if sp.apply_runtime_tint or sp.tint then add("FEHLER 3c: sprite " .. n .. " getönt oder mit Farbmaske") end
    end
  end
end
-- Ernter-Grafik (ab 0.8.5): drei Ebenen zu 64 Richtungen, kein Turm, kein Panzer-Leuchtbild.
do
  local car = raw.car["spice-harvester"]
  local layers = car and car.animation and car.animation.layers or {}
  local want = {{"harvester-base.png", 384, 0.5}, {"harvester-mask.png", 384, 0.5, "apply_runtime_tint"},
                {"harvester-shadow.png", 256, 1, "draw_as_shadow"}}
  if #layers ~= 3 then add("FEHLER 0.8.5: Ernter hat " .. #layers .. " Bildebenen statt 3") end
  for j, w in ipairs(want) do
    local l = layers[j] or {}
    if l.filename ~= harvester_gfx .. w[1] or l.width ~= w[2] or l.height ~= w[2] or l.scale ~= w[3]
        or l.direction_count ~= 64 or l.line_length ~= 8 or (w[4] and l[w[4]] ~= true) or l.tint then
      add("FEHLER 0.8.5: Ernter Ebene " .. j .. " (" .. w[1] .. ") passt nicht zu tools/grafik/README.md")
    end
  end
  if car and (car.turret_animation or car.light_animation) then add("FEHLER 0.8.5: Ernter hat noch Turm oder Panzer-Leuchtbild") end
end
-- Flugtreibstoff (ab 0.9.0): Raketen- und Atomtreibstoff tragen chemical und arrakis-flight-fuel, die einfachen
-- Brennstoffe nur chemical. Vor 2.1.20 (eine Kategorie je Item) bleibt alles bei chemical.
if V2120 then
  if not (raw["fuel-category"] and raw["fuel-category"]["arrakis-flight-fuel"]) then add("FEHLER 0.9.0: fuel-category arrakis-flight-fuel fehlt") end
  local function categories(name)
    local item = raw.item[name]
    if not item then return nil end
    local set = {}
    for _, c in pairs(item.fuel_categories or {item.fuel_category}) do set[c] = true end
    return set
  end
  for _, name in ipairs({"rocket-fuel", "nuclear-fuel"}) do
    local set = categories(name)
    if set and not (set.chemical and set["arrakis-flight-fuel"]) then add("FEHLER 0.9.0: " .. name .. " ohne chemical + arrakis-flight-fuel") end
  end
  for _, name in ipairs({"coal", "wood", "solid-fuel", "carbon", "arrakis-spice-briquette"}) do
    local set = categories(name)
    if set and set["arrakis-flight-fuel"] then add("FEHLER 0.9.0: " .. name .. " ist Flugtreibstoff") end
  end
end
-- Ornithopter-Grafik (ab 0.8.9): Rumpf und Farbmaske, eigener Schatten, kein Spidertron-Unterteil, keine Spidertron-Augen.
do
  local gs = orni and orni.graphics_set or {}
  local layers = gs.animation and gs.animation.layers or {}
  local gfx = "__arrakis__/graphics/entity/ornithopter/"
  local want = {{"ornithopter-base.png", 448, 0.5}, {"ornithopter-mask.png", 448, 0.5, "apply_runtime_tint"},
                {"ornithopter-shadow.png", 256, 1, "draw_as_shadow"}}
  if #layers ~= 2 then add("FEHLER 0.8.9: Ornithopter hat " .. #layers .. " Bildebenen statt 2") end
  for j, w in ipairs(want) do
    local l = (j == 3 and gs.shadow_animation or layers[j]) or {}
    if l.filename ~= gfx .. w[1] or l.width ~= w[2] or l.height ~= w[2] or l.scale ~= w[3] or not l.shift
        or l.direction_count ~= 64 or l.line_length ~= 8 or (w[4] and l[w[4]] ~= true) or l.tint then
      add("FEHLER 0.8.9: Ornithopter Ebene " .. j .. " (" .. w[1] .. ") passt nicht zu tools/grafik/README.md")
    end
  end
  for _, key in ipairs({"base_animation", "shadow_base_animation", "water_reflection", "light_positions", "eye_light"}) do
    if gs[key] ~= nil then add("FEHLER 0.8.9: Ornithopter graphics_set." .. key .. " vom Spidertron geerbt") end
  end
  if orni and orni.corpse ~= "big-remnants" then add("FEHLER 0.8.9: Ornithopter-Wrack " .. tostring(orni.corpse)) end
end
-- Jede Datei __arrakis__/… in den Prototypen muss im Repo liegen (aus dem Repo-Root starten).
do
  local seen, missing, checked = {}, {}, 0
  local function walk(t)
    if seen[t] then return end
    seen[t] = true
    for _, v in pairs(t) do
      if type(v) == "table" then walk(v)
      elseif type(v) == "string" and v:find("^__arrakis__/") and v:find("%.%a+$") and missing[v] == nil then
        local f = io.open(v:sub(13), "rb")
        checked = checked + 1
        missing[v] = not f
        if f then f:close() else add("FEHLER Datei fehlt im Repo: " .. v) end
      end
    end
  end
  walk(raw)
  add("Eigene Dateien geprüft: " .. checked)
end
-- Symbole: Gegenstände, Forschungen, Verknüpfungen und Signale brauchen icon oder icons, Factorio bricht sonst beim
-- Laden ab (0.8.5: Gegenstand spice-harvester ohne Symbol). icon_size gehört zu icon.
do
  local need = {technology = true, shortcut = true, ["virtual-signal"] = true}
  for _, t in ipairs(item_types) do need[t] = true end
  local n_icons = 0
  for t in pairs(need) do
    for n, p in pairs(raw[t] or {}) do
      if is_own(n) then
        n_icons = n_icons + 1
        local icons = p.icons
        if not p.icon and not (type(icons) == "table" and #icons > 0) then add("FEHLER " .. t .. " " .. n .. " ohne icon/icons") end
        if type(icons) == "table" then
          for j, ic in ipairs(icons) do if not ic.icon then add("FEHLER " .. t .. " " .. n .. " icons[" .. j .. "] ohne icon") end end
        end
      end
    end
  end
  add("Symbole geprüft: " .. n_icons)
end
-- Probe: Kasten ±1,6, Maske gleich der des Ernters (der hat keine eigene, dann gilt die Vorgabe für car).
local probe = raw["simple-entity-with-owner"]["arrakis-harvester-probe"]
if probe then
  local box = probe.collision_box or {}
  local lt, rb = box[1] or {}, box[2] or {}
  if lt[1] ~= -1.6 or lt[2] ~= -1.6 or rb[1] ~= 1.6 or rb[2] ~= 1.6 then add("FEHLER 3c: Probe collision_box nicht ±1,6") end
  if probe.minable then add("FEHLER 3c: Probe abbaubar") end
  local car = raw.car["spice-harvester"]
  if car then
    -- Ohne eigene Maske gilt beim Ernter die Vorgabe für car (V23 core/lualib/collision-mask-defaults.lua:174). Mit
    -- --ohne ist der Vanilla-Ordner hier schon gelöscht und collision-mask-util nicht mehr ladbar; dann die Vorgabe von Hand.
    local ok, cmu = pcall(require, "collision-mask-util")
    local want = car.collision_mask or (ok and cmu.get_default_mask("car"))
      or {layers = {player = true, car = true, train = true, is_object = true}, consider_tile_transitions = true}
    local got = probe.collision_mask
    local function same_layers(a, b)
      for l, v in pairs(a.layers or {}) do if v and not (b.layers or {})[l] then return false end end
      for l, v in pairs(b.layers or {}) do if v and not (a.layers or {})[l] then return false end end
      return true
    end
    if not (got and same_layers(want, got)) then add("FEHLER 3c: Probe-Maske ungleich der des Ernters") end
    for _, flag in ipairs({"consider_tile_transitions", "colliding_with_tiles_only", "not_colliding_with_itself"}) do
      if got and (got[flag] or false) ~= (want[flag] or false) then add("FEHLER 3c: Probe-Maske " .. flag .. " ungleich der des Ernters") end
    end
  end
end
-- Verknüpfungen: Verweise vorhanden, Fernbedienung ohne Vanilla-Taste
for n, sc in pairs(raw.shortcut or {}) do if is_own(n) then
  if sc.technology_to_unlock and not raw.technology[sc.technology_to_unlock] then add("FEHLER shortcut " .. n .. " technology_to_unlock " .. sc.technology_to_unlock) end
  if sc.item_to_spawn and not item_exists(sc.item_to_spawn) then add("FEHLER shortcut " .. n .. " item_to_spawn " .. sc.item_to_spawn) end
  if sc.action == "spawn-item" and not sc.item_to_spawn then add("FEHLER shortcut " .. n .. " spawn-item ohne item_to_spawn") end
  local ci = sc.associated_control_input
  if ci and is_own(ci) and not raw["custom-input"][ci] then add("FEHLER shortcut " .. n .. " associated_control_input " .. ci) end
  if not sc.localised_name then add("FEHLER shortcut " .. n .. " ohne localised_name") end
end end
local carry = raw.shortcut["arrakis-carry"]
if carry and (carry.action ~= "lua" or carry.associated_control_input ~= "arrakis-carry-toggle" or carry.technology_to_unlock ~= "arrakis-ornithopter") then add("FEHLER 3c: shortcut arrakis-carry action/Taste/Forschung") end
local give_remote = raw.shortcut["arrakis-give-remote"]
if give_remote and (give_remote.action ~= "spawn-item" or give_remote.item_to_spawn ~= "spidertron-remote" or give_remote.associated_control_input ~= nil or give_remote.technology_to_unlock ~= "arrakis-ornithopter") then add("FEHLER 3c: shortcut arrakis-give-remote action/Item/Taste/Forschung") end
local carry_key = raw["custom-input"]["arrakis-carry-toggle"]
if carry_key and (carry_key.key_sequence ~= "SHIFT + C" or carry_key.consuming ~= "none") then add("FEHLER 3c: custom-input arrakis-carry-toggle " .. tostring(carry_key.key_sequence) .. " / " .. tostring(carry_key.consuming)) end
add("3c: Ornithopter " .. (orni and "da" or "fehlt") .. ", Tempo-Sticker leer " .. speed_count.empty .. "/106, beladen " .. speed_count.loaded .. "/106, Lastbild " .. sprite_count .. "/32 Sprites")

-- Phase 3d1 (docs/plan-3d1.md 3 und 7): Eruption, Sandstaub, Signal, Geräusche, Verknüpfung, Tipps. Pfade und Werte
-- stehen hier fest (nicht aus prototypes/worms.lua gelesen).
local expected_3d1 = {
  explosion = {"arrakis-worm-eruption"},
  ["trivial-smoke"] = {"arrakis-sand-dust"},
  ["virtual-signal"] = {"arrakis-wormsign"},
  sound = {"arrakis-wormsign", "arrakis-rumble"},
  shortcut = {"arrakis-vibration-overlay"},
  ["tips-and-tricks-item"] = {"arrakis-briefing", "arrakis-wormsign-tip"},
}
local count_3d1 = 0
for t, names in pairs(expected_3d1) do for _, n in ipairs(names) do
  local p = raw[t] and raw[t][n]
  if not p then add("FEHLER 3d1: " .. t .. " " .. n .. " fehlt")
  else
    count_3d1 = count_3d1 + 1
    -- Explosionen sind in Vanilla versteckt (die Eruption erbt das von big-artillery-explosion).
    if p.hidden and t ~= "explosion" then add("FEHLER 3d1: " .. t .. " " .. n .. " ist hidden") end
  end
end end
local function walk_particles(node, seen, found)
  if type(node) ~= "table" or seen[node] then return end
  seen[node] = true
  for k, v in pairs(node) do
    if k == "particle_name" and type(v) == "string" then found[#found+1] = v end
    walk_particles(v, seen, found)
  end
end
local SAND_TINT = {r = 1, g = 0.85, b = 0.6}
local function sand_tinted(layer)
  local t = layer.tint
  return type(t) == "table" and (t.r or t[1]) == SAND_TINT.r and (t.g or t[2]) == SAND_TINT.g and (t.b or t[3]) == SAND_TINT.b
end
local eruption = raw.explosion["arrakis-worm-eruption"]
if eruption then
  local particles = {}
  walk_particles(eruption.created_effect, {}, particles)
  local stone, sand = 0, 0
  for _, n in ipairs(particles) do
    if n:find("^explosion%-stone%-particle") then stone = stone + 1 end
    if n:find("^sand%-1%-stone%-particle") then sand = sand + 1 end
    if not raw["optimized-particle"][n] then add("FEHLER 3d1: Eruption Partikel " .. n .. " fehlt") end
  end
  if stone > 0 then add("FEHLER 3d1: Eruption mit " .. stone .. " explosion-stone-particle-*") end
  if sand == 0 then add("FEHLER 3d1: Eruption ohne Sandsteine") end
  local anims = eruption.animations
  if anims and (anims.filename or anims.layers or anims.stripes or anims.filenames) then anims = {anims} end
  local n_anim, untinted = 0, 0
  for _, a in pairs(anims or {}) do
    for _, layer in pairs(a.layers or {a}) do
      n_anim = n_anim + 1
      if not sand_tinted(layer) then untinted = untinted + 1 end
    end
  end
  if n_anim == 0 then add("FEHLER 3d1: Eruption ohne Animation") end
  if untinted > 0 then add("FEHLER 3d1: Eruption " .. untinted .. " von " .. n_anim .. " Animationen/Ebenen nicht getönt") end
  local variations = eruption.sound and eruption.sound.variations or {}
  if #variations ~= 2 then add("FEHLER 3d1: Eruption sound mit " .. #variations .. " Varianten statt 2") end
  local smoke = false
  local seen_smoke = {}
  local function walk_smoke(node)
    if type(node) ~= "table" or seen_smoke[node] then return end
    seen_smoke[node] = true
    if node.type == "create-trivial-smoke" and node.smoke_name == "arrakis-sand-dust" then smoke = true end
    for _, v in pairs(node) do walk_smoke(v) end
  end
  walk_smoke(eruption.created_effect)
  if not smoke then add("FEHLER 3d1: Eruption ohne Sandstaub") end
end
local dust = raw["trivial-smoke"]["arrakis-sand-dust"]
if dust then
  local c = dust.color or {}
  local want = {0.80, 0.65, 0.40, 0.6}
  local got = {c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4]}
  for i = 1, 4 do if got[i] ~= want[i] then add("FEHLER 3d1: Sandstaub color " .. i .. " = " .. tostring(got[i]) .. " statt " .. want[i]) end end
end
local signal = raw["virtual-signal"]["arrakis-wormsign"]
if signal then
  local icon = signal.icons and signal.icons[1] and signal.icons[1].icon or signal.icon
  if icon ~= "__base__/graphics/icons/signal/signal-alert.png" then add("FEHLER 3d1: Signal arrakis-wormsign Icon " .. tostring(icon)) end
end
local function sound_files(sound)
  local files = {}
  if sound.filename then files[#files+1] = sound.filename end
  for _, v in ipairs(sound.variations or {}) do files[#files+1] = v.filename end
  return files
end
local plan_sounds = {
  ["arrakis-wormsign"] = {
    "__space-age__/sound/enemies/demolisher/demolisher-roar-big-1.ogg", "__space-age__/sound/enemies/demolisher/demolisher-roar-big-2.ogg",
    "__space-age__/sound/enemies/demolisher/demolisher-roar-big-3.ogg", "__space-age__/sound/enemies/demolisher/demolisher-roar-big-4.ogg",
    "__space-age__/sound/enemies/demolisher/demolisher-roar-big-5.ogg", "__space-age__/sound/enemies/demolisher/demolisher-roar-big-6.ogg"},
  ["arrakis-rumble"] = {"__space-age__/sound/enemies/demolisher/demolisher-tail-rumble.ogg"},
  ["arrakis-worm-eruption"] = {"__space-age__/sound/explosions/demolisher-explosion-1.ogg", "__space-age__/sound/explosions/demolisher-explosion-2.ogg"},
}
for n, want in pairs(plan_sounds) do
  local p = n == "arrakis-worm-eruption" and (eruption and eruption.sound) or raw.sound[n]
  if p and not same_list(sound_files(p), want) then add("FEHLER 3d1: Geräusch " .. n .. ": " .. table.concat(sound_files(p), ", ")) end
end
local wormsign_sound = raw.sound["arrakis-wormsign"]
if wormsign_sound and wormsign_sound.category ~= "alert" then add("FEHLER 3d1: sound arrakis-wormsign category " .. tostring(wormsign_sound.category)) end
local overlay = raw.shortcut["arrakis-vibration-overlay"]
if overlay and (overlay.action ~= "lua" or overlay.toggleable ~= true or overlay.technology_to_unlock ~= "arrakis-spice-harvesting") then
  add("FEHLER 3d1: shortcut arrakis-vibration-overlay action/toggleable/Forschung")
end
local plan_tips = {["arrakis-briefing"] = "planet-discovery-arrakis", ["arrakis-wormsign-tip"] = "arrakis-spice-harvesting"}
for n, tech in pairs(plan_tips) do
  local tip = raw["tips-and-tricks-item"][n]
  if tip then
    local tr = tip.trigger or {}
    if tip.category ~= "space-age" then add("FEHLER 3d1: Tipp " .. n .. " Kategorie " .. tostring(tip.category)) end
    if tr.type ~= "research" or tr.technology ~= tech then add("FEHLER 3d1: Tipp " .. n .. " Auslöser " .. tostring(tr.type) .. " " .. tostring(tr.technology)) end
    if not (tip.localised_name and tip.localised_description) then add("FEHLER 3d1: Tipp " .. n .. " ohne localised_name/localised_description") end
    if tip.skip_trigger ~= nil then add("FEHLER 3d1: Tipp " .. n .. " mit skip_trigger") end
  end
end
-- Forschungen unverändert gegenüber 0.6.1 (Zahl, Namen, Auslöser).
local plan_techs = {
  ["planet-discovery-arrakis"] = "unit",
  ["arrakis-windtrap"] = "unit",
  ["arrakis-spice-processing"] = "mine-entity spice-sand",
  ["spice-science-pack"] = "craft-item melange 20",
  ["melange-productivity"] = "unit",
  ["arrakis-spice-harvesting"] = "craft-item melange 10",
  ["arrakis-ornithopter"] = "craft-item spice-harvester 1",
}
local tech_count = 0
for n, tech in pairs(raw.technology) do if is_own(n) then
  tech_count = tech_count + 1
  local tr = tech.research_trigger
  local got = "unit"
  if tr then
    -- 2.1: mine-entity mit entities statt entity (prototypes/compat.lua)
    local target = tr.entity or (tr.entities and tr.entities[1]) or tr.item
    if type(target) == "table" then target = target.name end
    got = tr.type .. " " .. tostring(target) .. (tr.type == "craft-item" and (" " .. (tr.count or 1)) or "")
  end
  if plan_techs[n] == nil then add("FEHLER 3d1: neue Forschung " .. n)
  elseif plan_techs[n] ~= got then add("FEHLER 3d1: Forschung " .. n .. " Auslöser " .. got .. " statt " .. plan_techs[n]) end
end end
if tech_count ~= 7 then add("FEHLER 3d1: " .. tech_count .. " eigene Forschungen statt 7") end
add("3d1: " .. count_3d1 .. "/8 Prototypen, " .. tech_count .. " Forschungen")

-- Phase 3d2 (docs/plan-3d2.md 3 und 7): Sandwurm, Bohrstaub, Abtauchen. Namen und Werte stehen hier fest (nicht aus
-- prototypes/sandworm.lua gelesen).
local expected_3d2 = {
  ["segmented-unit"] = {"arrakis-sandworm-small"},
  ["trivial-smoke"] = {"arrakis-sandworm-smoke-front", "arrakis-sandworm-smoke-small-top", "arrakis-sandworm-smoke-small-bottom",
                       "arrakis-sandworm-smoke-big"},
  explosion = {"arrakis-worm-dive"},
}
local count_3d2 = 0
for t, names in pairs(expected_3d2) do for _, n in ipairs(names) do
  if not (raw[t] and raw[t][n]) then add("FEHLER 3d2: " .. t .. " " .. n .. " fehlt") else count_3d2 = count_3d2 + 1 end
end end
-- Knoten im ganzen Prototyp suchen: fn(node) gibt einen Befund (Text) oder nil.
local function find_nodes(node, fn, seen, found)
  if type(node) ~= "table" or seen[node] then return found end
  seen[node] = true
  local hit = fn(node)
  if hit then found[#found+1] = hit end
  for _, v in pairs(node) do find_nodes(v, fn, seen, found) end
  return found
end
local function foreign_effect(node)
  if node.type == "damage" then return "damage" end
  if node.type == "create-sticker" then return "create-sticker" end
  if type(node.particle_name) == "string" and node.particle_name:find("^vulcanus%-") then return node.particle_name end
  if type(node.smoke_name) == "string" and node.smoke_name:find("^demolisher%-") then return node.smoke_name end
  return nil
end
local function corpse_entity(node)
  if node.type == "create-entity" and type(node.entity_name) == "string" and node.entity_name:find("corpse") then return node.entity_name end
  return nil
end
local function cliff_effect(node) if node.type == "destroy-cliffs" then return "destroy-cliffs" end return nil end
local sandworm_parts = 0
for _, t in ipairs({"segmented-unit", "segment"}) do for n, p in pairs(raw[t] or {}) do if n:find("^arrakis%-sandworm%-") then
  sandworm_parts = sandworm_parts + 1
  local where = "FEHLER 3d2: " .. t .. " " .. n
  if has_ash(p.update_effects, {}) then add(where .. " hat Ascheeffekte") end
  local foreign = find_nodes(p, foreign_effect, {}, {})
  if #foreign > 0 then add(where .. " hat " .. table.concat(foreign, ", ")) end
  if #find_nodes(p.update_effects, cliff_effect, {}, {}) > 0 then add(where .. " hat destroy-cliffs in update_effects") end
  if p.update_effects_while_enraged ~= nil then add(where .. " update_effects_while_enraged gesetzt") end
  if p.revenge_attack_parameters ~= nil then add(where .. " revenge_attack_parameters gesetzt") end
  if p.loot ~= nil or p.corpse ~= nil then add(where .. " hat Beute/Leiche") end
  local corpses = find_nodes(p.dying_trigger_effect, corpse_entity, {}, {})
  if #corpses > 0 then add(where .. " dying_trigger_effect erzeugt " .. table.concat(corpses, ", ")) end
  if t == "segment" and p.hidden ~= true then add(where .. " nicht hidden") end
end end end
local head = raw["segmented-unit"]["arrakis-sandworm-small"]
if head then
  local where = "FEHLER 3d2: segmented-unit arrakis-sandworm-small"
  local segs = head.segment_engine and head.segment_engine.segments or {}
  if #segs ~= 12 then add(where .. " " .. #segs .. " Segmente statt 12") end
  for i, sg in ipairs(segs) do
    if type(sg.segment) ~= "string" or not sg.segment:find("^arrakis%-sandworm%-small%-") then add(where .. " Segment " .. i .. " " .. tostring(sg.segment)) end
  end
  for _, key in ipairs({"investigating_speed", "attacking_speed", "enraged_speed"}) do
    if type(head[key]) ~= "number" or math.abs(head[key] - 3.5 / 60) > 1e-9 then add(where .. " " .. key .. " " .. tostring(head[key]) .. " statt 3,5/60") end
  end
  if type(head.patrolling_speed) ~= "number" or math.abs(head.patrolling_speed - 1 / 60) > 1e-9 then add(where .. " patrolling_speed " .. tostring(head.patrolling_speed) .. " statt 1/60") end
  if type(head.enraged_duration) ~= "number" or head.enraged_duration > 60 then add(where .. " enraged_duration " .. tostring(head.enraged_duration)) end
  if head.vision_distance ~= 0 then add(where .. " vision_distance " .. tostring(head.vision_distance)) end
  if head.territory_radius ~= 1 then add(where .. " territory_radius " .. tostring(head.territory_radius)) end
  if head.autoplace ~= nil then add(where .. " hat autoplace") end
  if head.collision_mask and head.collision_mask.layers and head.collision_mask.layers.arrakis_rock then add(where .. " Maske mit arrakis_rock") end
  local icon = head.icons and head.icons[1]
  if not (icon and type(icon.tint) == "table" and sand_tinted(icon)) then add(where .. " Symbol nicht getönt") end
  if not head.localised_name then add(where .. " ohne localised_name") end
end
for _, n in ipairs(expected_3d2["trivial-smoke"]) do
  local smoke = raw["trivial-smoke"][n]
  if smoke then
    local c = smoke.color or {}
    local r, g, b, a = c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4] or 1
    if not (type(r) == "number" and type(g) == "number" and type(b) == "number" and r > g and g > b and r >= 0.5 * a) then
      add("FEHLER 3d2: trivial-smoke " .. n .. " nicht sandfarben")
    end
  end
end
local dive = raw.explosion["arrakis-worm-dive"]
if dive and dive.sound ~= nil then add("FEHLER 3d2: explosion arrakis-worm-dive mit sound") end
add("3d2: " .. count_3d2 .. "/6 Prototypen, " .. sandworm_parts .. " Teile des Sandwurms (Kopf und Segmente)")

-- Prüfstand: Test-Prototypen nur mit Einstellung, alle versteckt, ohne Rezept/Item/Forschung
local tb_setting = settings.startup["arrakis-testbench"]
local tb_on = tb_setting and tb_setting.value
local tb_expected = {
  ["spider-leg"] = {"arrakis-test-flyer-leg", "arrakis-test-flyer-leg-fast"},
  ["spider-vehicle"] = {"arrakis-test-flyer-1", "arrakis-test-flyer-2", "arrakis-test-flyer-4", "arrakis-test-flyer-4-fast"},
  sticker = {"arrakis-test-load-sticker", "arrakis-test-load-sticker-move", "arrakis-test-speed-max-tick", "arrakis-test-speed-max-second"},
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
    "scripts/testbench/t_harvester.lua", "scripts/testbench/t_worm.lua", "scripts/testbench/t_map.lua",
    "scripts/testbench/t_ornithopter.lua", "scripts/vibration.lua", "scripts/worms.lua", "scripts/worms-gui.lua",
    "scripts/testbench/t_jagd.lua", "scripts/sandworm.lua", "scripts/testbench/t_sandwurm.lua"}
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

-- Statische Regeln (docs/plan-3d1.md 7, docs/plan-3d2.md 7) über den Laufzeitcode, ohne Kommentare: Ereignisse nur über
-- event_handler, kein math.random, keine Modultabelle sandworm als globale Variable; sandworm.lua tötet nie (kein die(), kein
-- devour) und nennt die Sandwurm-Force nicht; jeder wörtliche Schlüssel arrakis-message.* steht in beiden Sprachen.
do
  local code_files = {"control.lua"}
  for _, n in ipairs({"arrakis-surface", "flyer-gui", "flyer", "harvester-gui", "harvester", "hold", "intake", "migrate", "sandworm",
                      "terrain", "vibration", "worms-gui", "worms"}) do code_files[#code_files+1] = "scripts/" .. n .. ".lua" end
  for _, n in ipairs({"runner", "t_ernter", "t_flyer", "t_harvester", "t_jagd", "t_karte", "t_map", "t_ornithopter", "t_sandwurm", "t_worm"}) do
    code_files[#code_files+1] = "scripts/testbench/" .. n .. ".lua"
  end
  local function read_file(name)
    local f = io.open(name, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
  end
  local function strip_comments(text)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    local lines = {}
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines+1] = (l:gsub("%-%-.*$", "")) end
    return table.concat(lines, "\n")
  end
  local function locale_keys(lang)
    local keys = {}
    local text = read_file("locale/" .. lang .. "/messages.cfg")
    if not text then return nil end
    local section
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do
      local sec = l:match("^%[([%w%-_]+)%]")
      if sec then section = sec
      elseif section == "arrakis-message" then
        local key = l:match("^([%w%-_]+)=")
        if key then keys[key] = true end
      end
    end
    return keys
  end
  local de, en = locale_keys("de"), locale_keys("en")
  local n_files, n_keys = 0, 0
  for _, file in ipairs(code_files) do
    local text = read_file(file)
    if text then
      n_files = n_files + 1
      local code = strip_comments(text)
      if code:find("script%.on_event") or code:find("script%.on_nth_tick") then add("FEHLER statisch: " .. file .. " registriert Ereignisse an event_handler vorbei") end
      if code:find("math%.random") then add("FEHLER statisch: " .. file .. " benutzt math.random") end
      if file ~= "scripts/sandworm.lua" and code:find("\n%s*sandworm%s*=") then add("FEHLER statisch: " .. file .. " setzt eine globale Modultabelle sandworm") end
      if file == "scripts/sandworm.lua" then
        if code:find("[%.:]die%s*%(") or code:find("devour") then add("FEHLER statisch: scripts/sandworm.lua ruft die() oder devour") end
        if code:find("force%s*=%s*[\"']arrakis%-sandworm[\"']") then add("FEHLER statisch: scripts/sandworm.lua nennt die Sandwurm-Force") end
      end
      if de and en then
        -- Ein Schlüssel mit "-" am Ende ist ein Präfix (z. B. "arrakis-message.state-" .. Zustand): dann reicht einer mit diesem Anfang.
        local function known(keys, key)
          if key:sub(-1) ~= "-" then return keys[key] == true end
          for k in pairs(keys) do if k:sub(1, #key) == key then return true end end
          return false
        end
        for key in code:gmatch("[\"']arrakis%-message%.([%w%-_]+)[\"']") do
          n_keys = n_keys + 1
          if not known(de, key) then add("FEHLER statisch: " .. file .. ": arrakis-message." .. key .. " fehlt in locale/de") end
          if not known(en, key) then add("FEHLER statisch: " .. file .. ": arrakis-message." .. key .. " fehlt in locale/en") end
        end
      end
    end
  end
  if de and en then
    for key in pairs(de) do if not en[key] then add("FEHLER statisch: arrakis-message." .. key .. " nur in locale/de") end end
    for key in pairs(en) do if not de[key] then add("FEHLER statisch: arrakis-message." .. key .. " nur in locale/en") end end
  end
  if n_files == 0 then add("WARN statisch: Laufzeitdateien nicht gefunden (aus dem Repo-Root starten)")
  else add("Statische Regeln: " .. n_files .. "/" .. #code_files .. " Dateien, " .. n_keys .. " wörtliche Meldungsschlüssel") end
end

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
  -- 2.1.7: Planet hinter Raumplattformen; Arrakis hat ihn, wenn Vulcanus ihn hat (in 2.0 keiner von beiden).
  local vulcanus = raw.planet.vulcanus
  if vulcanus and (vulcanus.platform_surface_render_parameters ~= nil) ~= (pl.platform_surface_render_parameters ~= nil) then add("FEHLER planet platform_surface_render_parameters") end
  add("Planet hinter Raumplattformen: " .. (pl.platform_surface_render_parameters and "ja" or "nein"))
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

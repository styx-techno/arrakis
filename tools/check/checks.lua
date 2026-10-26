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
  if es.type ~= "burner" or not same_list(es.fuel_categories or {}, {"chemical"}) or es.fuel_inventory_size ~= 2 then
    add("FEHLER 3c: arrakis-ornithopter Brenner " .. tostring(es.type) .. " " .. table.concat(es.fuel_categories or {}, ",") .. " Slots " .. tostring(es.fuel_inventory_size))
  end
  if orni.movement_energy_consumption ~= "800kW" then add("FEHLER 3c: arrakis-ornithopter movement_energy_consumption " .. tostring(orni.movement_energy_consumption)) end
  if orni.guns or orni.equipment_grid then add("FEHLER 3c: arrakis-ornithopter hat Waffen oder Ausrüstungsgitter") end
  if orni.trash_inventory_size ~= 0 then add("FEHLER 3c: arrakis-ornithopter trash_inventory_size " .. tostring(orni.trash_inventory_size)) end
  if not (orni.minable and orni.minable.result == "arrakis-ornithopter") then add("FEHLER 3c: arrakis-ornithopter minable.result " .. tostring(orni.minable and orni.minable.result)) end
  -- Körper ohne eigene Maske: Vorgabe nur trigger_target, der Ernter fährt darunter durch (Plan 3, U21).
  if orni.collision_mask ~= nil then add("FEHLER 3c: arrakis-ornithopter hat eine collision_mask") end
  if orni.tall then add("FEHLER 3c: arrakis-ornithopter tall gesetzt") end
  if orni.icon ~= nil or not orni.icons then add("FEHLER 3c: arrakis-ornithopter icon statt icons") end
  if orni.height ~= 3 or not (orni.graphics_set and orni.graphics_set.render_layer == "air-object") then add("FEHLER 3c: arrakis-ornithopter Flughöhe/render_layer") end
  -- Kein Feld, das auf den Spidertron zeigt, außer den gewollten (Leiche, Explosion; DOC 5.5).
  for _, key in ipairs({"factoriopedia_alternative", "factoriopedia_simulation", "fast_replaceable_group", "next_upgrade", "placeable_by"}) do
    if orni[key] ~= nil then add("FEHLER 3c: arrakis-ornithopter " .. key .. " geerbt") end
  end
end
local orni_item = raw["item-with-entity-data"]["arrakis-ornithopter"]
if orni_item then
  -- Ohne icon_tintable* zeigte ein Item mit gespeicherter Farbe das getönte Spidertron-Bild (Plan 3).
  if orni_item.icon ~= nil or not orni_item.icons then add("FEHLER 3c: item arrakis-ornithopter icon statt icons") end
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
-- Tempo-Sticker (0.6.1, docs/plan-3c.md 4.9): je Zustand eine Familie, eine Stufe t_j = STEP^j je Sticker, Name mit
-- p = floor(100 · t_j + 0,5), versteckt, vehicle_speed_modifier = BASE / t_j, 216000 Ticks. Name und Modifier rechnet
-- die Regel aus den Konstanten von prototypes/ornithopter-speed.lua selbst nach, nicht mit dessen Tabellen. Das Modul
-- liest sie per loadfile (aus dem Repo-Root wie die Laufzeitdateien unten). Die beiden Sticker aus 0.6.0 gibt es nicht mehr.
local speed_chunk = loadfile("prototypes/ornithopter-speed.lua")
local speed_ok, speed = false, nil
if speed_chunk then speed_ok, speed = pcall(speed_chunk) end
local speed_count = {empty = 0, loaded = 0}
if not (speed_ok and type(speed) == "table") then add("FEHLER 3c: prototypes/ornithopter-speed.lua nicht ladbar (aus dem Repo-Root starten): " .. tostring(speed))
else
  local base = {empty = speed.BASE_EMPTY, loaded = speed.BASE_LOADED}
  for _, state in ipairs({"empty", "loaded"}) do
    for j = speed.MIN_J, speed.MAX_J do
      local t = speed.STEP ^ j
      local n = "arrakis-ornithopter-" .. state .. "-" .. math.floor(100 * t + 0.5)
      local s = raw.sticker[n]
      if not s then add("FEHLER 3c: sticker " .. n .. " fehlt") else
        speed_count[state] = speed_count[state] + 1
        if s.hidden ~= true then add("FEHLER 3c: sticker " .. n .. " nicht hidden") end
        if type(s.vehicle_speed_modifier) ~= "number" or math.abs(s.vehicle_speed_modifier - base[state] / t) > 1e-9 then add("FEHLER 3c: sticker " .. n .. " vehicle_speed_modifier " .. tostring(s.vehicle_speed_modifier) .. " statt " .. base[state] / t) end
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
-- Lastbild: 16 Richtungen, je Bild und Schatten zwei Ebenen mit scale 0.5 (HR-Bilder wie Vanilla; ohne gälte 1).
local sprite_count = 0
for i = 0, 15 do
  for _, kind in ipairs({"image", "shadow"}) do
    local n = kind == "image" and ("arrakis-harvester-carried-" .. i) or ("arrakis-harvester-carried-shadow-" .. i)
    local sp = raw.sprite[n]
    if not sp then add("FEHLER 3c: sprite " .. n .. " fehlt") else
      sprite_count = sprite_count + 1
      local layers = sp.layers or {}
      if #layers ~= 2 then add("FEHLER 3c: sprite " .. n .. " hat " .. #layers .. " Ebenen statt 2") end
      for j, layer in ipairs(layers) do
        if layer.scale ~= 0.5 then add("FEHLER 3c: sprite " .. n .. " Ebene " .. j .. " scale " .. tostring(layer.scale)) end
        if (layer.draw_as_shadow == true) ~= (kind == "shadow") then add("FEHLER 3c: sprite " .. n .. " Ebene " .. j .. " draw_as_shadow " .. tostring(layer.draw_as_shadow)) end
        if layer.apply_runtime_tint then add("FEHLER 3c: sprite " .. n .. " Ebene " .. j .. " mit Farbmaske") end
        if kind == "shadow" and layer.tint then add("FEHLER 3c: sprite " .. n .. " Ebene " .. j .. " Schatten getönt") end
        if not (layer.filename and layer.width and layer.height and layer.x and layer.y) then add("FEHLER 3c: sprite " .. n .. " Ebene " .. j .. " ohne Ausschnitt") end
      end
    end
  end
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
    "scripts/testbench/t_ornithopter.lua"}
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

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
  if t == "spider-vehicle" and p.spider_engine then for _, leg in ipairs(p.spider_engine.legs or {p.spider_engine.legs}) do local ln = leg.leg if ln and not raw["spider-leg"][ln] then add("FEHLER spider " .. n .. " leg " .. ln) end end end
end end end

for n, tile in pairs(raw.tile) do if is_own(n) and tile.collision_mask then for l in pairs(tile.collision_mask.layers or {}) do if not raw["collision-layer"][l] then add("FEHLER tile " .. n .. " layer " .. l) end end end end

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

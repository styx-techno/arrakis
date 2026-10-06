-- Versionsweiche Factorio 2.0 / 2.1.
--
-- Alle Prototypen der Mod werden in 2.0-Syntax geschrieben. Läuft die Mod
-- unter 2.1, schreibt compat.finish() am Ende von data.lua die eigenen
-- Prototypen auf die 2.1-Syntax um. Vanilla und andere Mods bleiben
-- unberührt. Für einen 2.1-Build muss dann nur info.json angepasst werden.
--
-- helpers.compare_versions gibt es im Data-Stage seit 2.0.55.

local compat = {}

local base_version = mods["base"]
compat.v21 = helpers.compare_versions(base_version, "2.1.0") >= 0
compat.v2120 = helpers.compare_versions(base_version, "2.1.20") >= 0

local snapshot

-- Merkt sich alle Prototypen, die vor der Mod existieren.
function compat.start()
  snapshot = {}
  for type_name, prototypes in pairs(data.raw) do
    local names = {}
    for name in pairs(prototypes) do names[name] = true end
    snapshot[type_name] = names
  end
end

local function own_prototypes()
  local result = {}
  for type_name, prototypes in pairs(data.raw) do
    local known = snapshot[type_name] or {}
    for name, prototype in pairs(prototypes) do
      if not known[name] then table.insert(result, prototype) end
    end
  end
  return result
end

-- 2.1: probability -> independent_probability (Item- und Fluid-Ergebnisse)
local function fix_products(products)
  for _, product in pairs(products or {}) do
    if product.probability ~= nil then
      product.independent_probability = product.probability
      product.probability = nil
    end
  end
end

local function to_list(value)
  if type(value) == "table" then return value end
  return {value}
end

-- Fahrzeuge (z. B. per deepcopy vom Panzer): 2.1 kennt nur noch
-- braking_force und friction_force, 2.0 versteht beide Schreibweisen.
function compat.vehicle_physics(prototype, braking_force, friction_force)
  prototype.braking_power = nil
  prototype.friction = nil
  prototype.braking_force = braking_force
  prototype.friction_force = friction_force
end

-- Schreibt die eigenen Prototypen auf die Syntax der laufenden Version um.
function compat.finish()
  assert(snapshot, "compat.start() fehlt")
  if not compat.v21 then
    snapshot = nil
    return
  end
  for _, prototype in pairs(own_prototypes()) do
    -- RecipePrototype::category -> categories
    if prototype.type == "recipe" then
      if prototype.category then
        prototype.categories = {prototype.category}
        prototype.category = nil
      end
      fix_products(prototype.results)
    end

    -- MineEntityTechnologyTrigger::entity -> entities
    local trigger = prototype.type == "technology" and prototype.research_trigger
    if trigger and trigger.type == "mine-entity" and trigger.entity then
      trigger.entities = to_list(trigger.entity)
      trigger.entity = nil
    end

    if prototype.minable then
      fix_products(prototype.minable.results)
    end

    -- ItemPrototype::fuel_category -> fuel_categories (2.1.20)
    if compat.v2120 and prototype.fuel_category then
      prototype.fuel_categories = {prototype.fuel_category}
      prototype.fuel_category = nil
    end
  end
  snapshot = nil
end

return compat

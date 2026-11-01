-- Prüfstand: Flieger-Tests T1, T9, T12 (Vertrag siehe runner.lua, Design 4.2 und 8).
-- T1 misst Tempo, Ankunft und Verbrauch der Flieger-Varianten über Sand, Fels, Wasser und Gebäude.
-- T9 zeigt Bild und Schatten einer getragenen Last und prüft, ob Render-Objekte beim
--    Oberflächenwechsel verschwinden (interaktiv).
-- T12 misst, was beim Drücken der Testtaste in Fahrzeug, Kartenansicht und Fernsteuerung ankommt (interaktiv).
-- Zustand nur in run.data: Zahlen, Texte, Positionen {x, y}, LuaEntity- und LuaRenderObject-Referenzen
-- (vor jeder Benutzung auf valid prüfen).

local FLYER_4 = "arrakis-test-flyer-4"
local FUEL_ITEM = "rocket-fuel"

-- Hilfen ------------------------------------------------------------------------------------

-- Ruft fn geschützt auf. Bei Fehler: Zeile mit level (Standard FEHLER) ins Protokoll.
local function guarded(run, tb, what, fn, level)
  local ok, result = pcall(fn)
  if not ok then
    tb.log(run, level or "FEHLER", what .. " ging nicht: " .. tostring(result))
  end
  return ok, result
end

-- Liest einen Wert; Fehler werden zu Text (für Messzeilen).
local function read(fn)
  local ok, value = pcall(fn)
  if ok then return value end
  return "Fehler: " .. tostring(value)
end

local function pos_text(tb, position)
  if not position then return "–" end
  return "(" .. tb.num(position.x) .. ", " .. tb.num(position.y) .. ")"
end

local function offset(origin, dx, dy)
  return {x = origin.x + dx, y = origin.y + dy}
end

-- Spieler zum Zuschauen hinbringen (merkt sich die Rückkehrposition, siehe tb.watch).
local function bring_player(run, tb, player, position)
  local ok, moved = guarded(run, tb, "Spieler zum Testbereich bringen", function()
    return tb.watch(run, player, position)
  end, "INFO")
  if ok and not moved then
    tb.log(run, "INFO", "Teleport zum Testbereich ging nicht; /arrakis-test zurück bringt dich zurück, falls nötig")
  end
end

-- Flieger erzeugen; nil bei Fehler (wird gemeldet).
local function create_flyer(run, tb, surface, name, position, force)
  local ok, flyer = guarded(run, tb, "Flieger " .. name .. " erzeugen", function()
    return surface.create_entity{name = name, position = position, force = force, create_build_effect_smoke = false}
  end)
  if ok and flyer and flyer.valid then return flyer end
  if ok then tb.log(run, "FEHLER", "Flieger " .. name .. " wurde nicht erzeugt (create_entity gab nil)") end
  return nil
end

-- Treibstoff einlegen; gibt die eingelegte Menge zurück.
local function add_fuel(run, tb, entity, count)
  local ok, inserted = guarded(run, tb, "Treibstoff einlegen", function()
    return tb.fuel(entity, FUEL_ITEM, count)
  end)
  if not ok then return 0 end
  inserted = inserted or 0
  if inserted < count then
    tb.log(run, "FEHLER", string.format("Treibstoff: nur %s von %s %s eingelegt", tostring(inserted), tostring(count), FUEL_ITEM))
  end
  return inserted
end

-- Für die Testdateien scripts/testbench/tests/ (eine je Test; aufgeteilt aus t_flyer.lua, Verhalten unverändert).
return
{
  FLYER_4 = FLYER_4,
  FUEL_ITEM = FUEL_ITEM,
  guarded = guarded,
  read = read,
  pos_text = pos_text,
  offset = offset,
  bring_player = bring_player,
  create_flyer = create_flyer,
  add_fuel = add_fuel,
}

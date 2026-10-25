-- Ablage-Oberfläche arrakis-hold (Phase 3c, docs/plan-3c.md 4.11): Hier stehen getragene Spice-Ernter,
-- während am Ornithopter nur ihr Bild hängt (scripts/flyer.lua). Bibliothek für __core__/lualib/event_handler.
-- Daten: storage.hold = {surface = LuaSurface|nil} (Schema 2, siehe scripts/migrate.lua).
--
-- Stellplätze: 16 × 16 = 256 im 10er-Raster, x, y ∈ {−60, −50, …, 90}. Mit ±4 Kacheln je Platz reicht das von
-- −64 bis 94 und liegt damit ganz in den 5 × 5 erzeugten Chunks (request_to_generate_chunks({0, 0}, 2): Chunks −2 … 2,
-- Kacheln −64 bis 95). Neue, ungenerierte Chunks entstehen so nie.
-- Eine Liste freier Plätze gibt es bewusst nicht (Abweichung von DOC 4.2): Frei ist ein Platz, auf dem nichts steht.
-- Fehlt ein Datensatz oder läuft ein Handler in anderer Reihenfolge, kann so kein Platz verloren gehen, und ein
-- wartender Ernter (storage.stranded) belegt seinen Platz einfach weiter.
-- Teleport zwischen Oberflächen prüft keine Kollision (A23 classes.d.ts:5476); deshalb nur freie Plätze.
-- Der Name ist bewusst ein anderer als die Prüfstand-Ablage arrakis-test-hold (scripts/testbench/runner.lua:37).

local hold = {}

-- Name der Ablage-Oberfläche.
hold.NAME = "arrakis-hold"
-- Zahl der Stellplätze (16 × 16).
hold.SLOTS = 256
-- Raster der Stellplätze (Kacheln) und erste/letzte Koordinate in x und y.
hold.SPACING = 10
hold.FIRST = -60
hold.LAST = 90
-- Halbe Kantenlänge der Fläche, die je Platz frei sein muss (Kacheln).
hold.SLOT_RADIUS = 4

-- Versteckt die Ablage für alle Forces (A23 classes.d.ts:11399) [U25].
local function hide(surface)
  for _, force in pairs(game.forces) do
    force.set_surface_hidden(surface, true)
  end
end

local function slot_area(x, y)
  local r = hold.SLOT_RADIUS
  return {{x - r, y - r}, {x + r, y + r}}
end

local function slot_free(surface, x, y)
  return surface.count_entities_filtered{area = slot_area(x, y), limit = 1} == 0
end

-- Die Ablage, wenn sie in storage steht und gültig ist, sonst nil.
function hold.surface()
  local data = storage.hold
  local surface = data and data.surface
  if surface and surface.valid then return surface end
  return nil
end

-- Gibt die Ablage zurück und legt sie bei Bedarf an. Auch eine vorgefundene Oberfläche wird vorbereitet:
-- Wird die Mod ohne /arrakis-uninstall entfernt, bleibt die leere Ablage im Spielstand (DOC 4.6), und nach dem
-- Wiederhinzufügen beginnt storage.hold leer. generate_with_lab_tiles ist eine Eigenschaft der Oberfläche, kein
-- create_surface-Parameter (A23 classes.d.ts:21003).
function hold.ensure()
  local surface = hold.surface()
  if surface then return surface end
  surface = game.get_surface(hold.NAME) or game.create_surface(hold.NAME)
  surface.generate_with_lab_tiles = true
  surface.request_to_generate_chunks({0, 0}, 2)
  surface.force_generate_chunk_requests()
  hide(surface)
  storage.hold = {surface = surface}
  return surface
end

-- Erster freier Stellplatz in fester Reihenfolge (y, dann x) als {x, y}, sonst nil. Anheben und Teleport laufen im
-- selben Tick nacheinander, also bekommt der nächste Aufruf schon den nächsten Platz.
function hold.take_slot()
  local surface = hold.ensure()
  for y = hold.FIRST, hold.LAST, hold.SPACING do
    for x = hold.FIRST, hold.LAST, hold.SPACING do
      if slot_free(surface, x, y) then return {x = x, y = y} end
    end
  end
  return nil
end

-- Zahl der Plätze, auf denen nichts steht (256 Abfragen; nur für den Prüfstand). Ohne Ablage sind alle frei.
function hold.free_count()
  local surface = hold.surface()
  if not surface then return hold.SLOTS end
  local count = 0
  for y = hold.FIRST, hold.LAST, hold.SPACING do
    for x = hold.FIRST, hold.LAST, hold.SPACING do
      if slot_free(surface, x, y) then count = count + 1 end
    end
  end
  return count
end

-- Vergisst die Ablage (nach dem Löschen oder im Prüfstand); ensure() sucht oder legt sie neu an.
function hold.forget()
  storage.hold = {}
end

-- Neue Force: Ablage auch für sie verstecken [U25].
local function on_force_created(event)
  local surface = hold.surface()
  if surface and event.force and event.force.valid then
    event.force.set_surface_hidden(surface, true)
  end
end

hold.events =
{
  [defines.events.on_force_created] = on_force_created
}

return hold

-- Gelände von Arrakis: Fels, Sand und wo der Spice-Ernter arbeiten darf (Phase 3b).
-- Reine Hilfsfunktionen ohne storage und ohne Ereignisse.

local terrain = {}

local ROCK = "arrakis-rock"
local ARRAKIS = "arrakis"
local TESTBENCH_SURFACE = "arrakis-testbench"

-- Startup-Einstellungen sind beim Laden von control.lua lesbar und ändern sich im Spiel nicht.
local testbench_setting = settings.startup["arrakis-testbench"]
local TESTBENCH = testbench_setting and testbench_setting.value or false

-- Ecken einer Fläche; erlaubt {left_top = …, right_bottom = …} und {{x1, y1}, {x2, y2}}.
local function corners(area)
  local left_top = area.left_top or area[1]
  local right_bottom = area.right_bottom or area[2]
  return left_top.x or left_top[1], left_top.y or left_top[2],
    right_bottom.x or right_bottom[1], right_bottom.y or right_bottom[2]
end

-- Darf auf dieser Oberfläche geerntet werden? Arrakis; mit Startup-Einstellung arrakis-testbench auch die Prüfstand-Fläche.
function terrain.harvest_allowed(surface)
  if not (surface and surface.valid) then return false end
  local name = surface.name
  return name == ARRAKIS or (TESTBENCH and name == TESTBENCH_SURFACE)
end

-- Name der natürlichen Kachel an (x, y): unter Pflaster und Fundament, sonst die sichtbare Kachel.
function terrain.natural_tile_name(surface, x, y)
  local tile = surface.get_tile(math.floor(x), math.floor(y))
  return tile.double_hidden_tile or tile.hidden_tile or tile.name
end

-- Liegt in der ganzen Fläche natürlicher Fels? Gepflasterter Fels zählt als Fels.
function terrain.is_rock_area(surface, area)
  local x1, y1, x2, y2 = corners(area)
  for x = math.floor(x1), math.ceil(x2) - 1 do
    for y = math.floor(y1), math.ceil(y2) - 1 do
      if terrain.natural_tile_name(surface, x, y) ~= ROCK then return false end
    end
  end
  return true
end

-- Liegt unter der Kollisionsbox (gedreht: umschließendes Rechteck) eine natürliche Kachel, die kein Fels ist?
function terrain.has_sand_under(entity)
  local box = entity.bounding_box
  local x1, y1, x2, y2 = corners(box)
  local orientation = box.orientation
  if orientation and orientation ~= 0 then
    local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    local hw, hh = (x2 - x1) / 2, (y2 - y1) / 2
    local angle = orientation * 2 * math.pi
    local c, s = math.abs(math.cos(angle)), math.abs(math.sin(angle))
    local ex, ey = hw * c + hh * s, hw * s + hh * c
    x1, y1, x2, y2 = cx - ex, cy - ey, cx + ex, cy + ey
  end
  local surface = entity.surface
  for x = math.floor(x1), math.ceil(x2) - 1 do
    for y = math.floor(y1), math.ceil(y2) - 1 do
      if terrain.natural_tile_name(surface, x, y) ~= ROCK then return true end
    end
  end
  return false
end

return terrain

-- Oberfläche von Arrakis und Entwicklerbefehl /arrakis (Bibliothek für event_handler).
local arrakis_surface = {}

-- Gibt die Oberfläche von Arrakis zurück (legt sie bei Bedarf an) und erzeugt die Chunks
-- im Umkreis von radius_chunks um 0,0 sofort.
function arrakis_surface.get_or_create(radius_chunks)
  local planet = game.planets["arrakis"]
  local surface = planet.surface or planet.create_surface()
  surface.request_to_generate_chunks({0, 0}, radius_chunks)
  surface.force_generate_chunk_requests()
  return surface
end

-- Entwickler-Hilfe für Phase 0: /arrakis teleportiert einen Admin direkt nach Arrakis.
local function teleport_command(command)
  local player = game.get_player(command.player_index)
  if not player then return end
  if not player.admin then
    player.print("Nur Admins dürfen /arrakis benutzen.")
    return
  end
  local surface = arrakis_surface.get_or_create(8)
  local position = surface.find_non_colliding_position("character", {0, 0}, 32, 1) or {0, 0}
  player.teleport(position, surface)
end

function arrakis_surface.add_commands()
  commands.add_command("arrakis", "Teleportiert dich nach Arrakis (nur Admins, zum Testen).", teleport_command)
end

return arrakis_surface

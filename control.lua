-- Entwickler-Hilfe für Phase 0: /arrakis teleportiert einen Admin direkt nach Arrakis.
commands.add_command("arrakis", "Teleportiert dich nach Arrakis (nur Admins, zum Testen).", function(command)
  local player = game.get_player(command.player_index)
  if not player then return end
  if not player.admin then
    player.print("Nur Admins dürfen /arrakis benutzen.")
    return
  end
  local planet = game.planets["arrakis"]
  local surface = planet.surface or planet.create_surface()
  surface.request_to_generate_chunks({0, 0}, 3)
  surface.force_generate_chunk_requests()
  local position = surface.find_non_colliding_position("character", {0, 0}, 32, 1) or {0, 0}
  player.teleport(position, surface)
end)

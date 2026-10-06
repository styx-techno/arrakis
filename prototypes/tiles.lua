-- Fels-Kachel: Kopie des Fulgora-Gesteins mit eigener Verteilung.
-- Nur hier ist Bauen sicher vor Sandwürmern (ab Phase 3).
local rock = table.deepcopy(data.raw.tile["fulgoran-rock"])
rock.name = "arrakis-rock"
rock.order = "b[natural]-z[arrakis]-a[rock]"
rock.sprite_usage_surface = nil
rock.layer = 11
rock.map_color = {150, 105, 70}
rock.autoplace = {probability_expression = "1 + arrakis_rock * 20"}
-- Eigene Kollisionsebene zusätzlich zu den Ebenen der Fulgora-Kopie (prototypes/collision-layers.lua).
rock.collision_mask.layers.arrakis_rock = true

data:extend({rock})

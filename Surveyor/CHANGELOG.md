# Surveyor

## 0.1.0

- World map layer: on a zone map, outlines every area with an exploration bit along its chunk
  boundary; undiscovered areas gold, discovered areas green. Continent and other map types draw
  nothing.
- Explored (green) comes from the client's explored map overlays (`GetExploredMapTextures`) matched
  against the baked WorldMapOverlay table; a map without baked overlays falls back to the position
  probe, where an unknown area id no longer counts as explored. `/survey probe` reports the match.
- Borders are solid lines over a black shadow,
  2 pixels thick by default; the shadow is left out on a map where it would push the total past the
  8000-line cap.
- Area names inside each outline on zone maps (toggle with `/survey names`); continent maps keep
  Blizzard's own zone names.
- A zone map draws only the areas of zones lying at least 90% inside it, not the subzones of
  neighbouring zones at its edges.
- Options page under Esc > Options > AddOns (`/survey config`): enabled, mode, area names, line
  thickness (1 to 6 px), line opacity (10 to 100%) and the minimap button.
- Hide explored areas (options checkbox or `/survey explored`): explored areas draw no border, shadow or name.
- `/survey probe` prints what the client and the data report at the player's position.
- `/survey on | off | names | xp | all | config | probe | status`; `xp` (default) draws only the areas that pay
  discovery XP.
- Border data generated offline from Forever 1.60.1.70450.
- Initial scaffold.

# Piece models

Drop chess piece models in this folder and the game uses them. Leave it empty
and it falls back to the primitive stand-ins built in `piece_visual.gd`. No code
changes either way.

## Adding the LowPoly Chess Set

<https://nailfighter.itch.io/lowpoly-chess-set> — CC0, free, no attribution
required.

1. Download the pack from itch.io and unzip it.
2. Copy the six piece `.fbx` files from the pack's `Models/` folder into this
   folder.
3. **Copy the textures in too**, from `Texture/Wood049_1K-JPG/`: the three files
   named `Wood049_1K_Color.jpg`, `_Normal.jpg` and `_Roughness.jpg`. They must
   sit in this folder, flat, beside the models — an `.fbx` references its
   textures by bare filename, so a missing one produces
   `Can't open file from path 'res://assets/pieces/Wood049_1K_Color.jpg'` on
   every import. The meshes still load, but the log fills with errors.
   (The game overrides materials anyway, so these are only needed to keep the
   import clean and to leave the pack usable as authored.)
4. Skip `Chess Scene.fbx` and the `Blend Files/` folder. Neither is used.
5. Open the project in Godot. The importer picks up the new files
   automatically — watch the Output panel for import errors.
6. Run. Nothing else to configure.

Skip the pack's chess board model. Boards are generated in `board_visual.gd`
because every square needs to be individually pickable and individually
highlightable, which a single board mesh cannot do.

## What the loader will accept

`piece_models.gd` is deliberately forgiving, because asset packs disagree about
naming, units and up-axis.

- **Formats**: `.glb`, `.gltf`, `.fbx`, `.obj`, `.dae`, `.blend`, `.tscn`,
  `.scn`, `.res`. (`.blend` only works if Godot is configured with a path to
  Blender; `.fbx` imports natively in Godot 4.3+.)
- **Naming**: a file per piece, matched by finding any of that piece's aliases
  anywhere in the filename — `king.fbx`, `Chess_King.glb` and `King_White.fbx`
  all work, case-insensitively. Where both a light and a dark variant exist, the
  loader prefers the one that does not say "black".
- **Misspellings and synonyms**: the alias list in `PieceModels.TYPE_ALIASES`
  covers what packs actually ship rather than what they should. This pack calls
  the bishop `Bisop.fbx` (a typo in the pack) and the knight `Horse.fbx`; both
  are matched. Add to that list if a pack uses some other word — the failure mode
  is silent, and shows up only as one piece still being a primitive.
- **One combined scene**: if no filename matches, the first model in the folder
  is treated as a scene holding every piece, and child nodes are matched by
  name the same way.
- **Any scale**: each model is measured and rescaled to a fixed target height,
  so the pack's units do not matter. Heights are in `PieceModels.TARGET_HEIGHT`
  — adjust them there if the silhouettes need rebalancing.
- **Z-up exports**: detected (depth much greater than height) and laid upright.
- **Partial sets**: a type with no model falls back to its primitive on its own,
  so you can drop in one piece at a time.

## Materials

The pack's own black and white materials are **not** used. Every mesh gets
`material_override` from `Palette`, because piece colour carries real
information here: off-black versus off-white separates the two players, and
matte versus glossy separates each player's level-1 army from their level-3
army. Keeping the authored materials would lose the army distinction.

To use a pack's materials instead, drop the `PieceModels.apply_material()` call
in `piece_visual.gd::_build_meshes()` — and then find another way to tell your
own two armies apart.

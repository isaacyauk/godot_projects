# Deckbuilder layer — what was added and how it hooks into the overworld

Everything from the GodotGameLab "Slay the Spire in Godot 4" series up to and
including the Season 2 finale, ported into this project's folder layout and
wired to the overworld instead of the tutorial's node map.

Nothing that already existed was deleted. Files you already had were extended,
never replaced wholesale — the old prototype `Scenes/battle.tscn` still loads.

---

## Running an encounter from the overworld

1. Drop `Scenes/triggers/encounter_trigger.tscn` into an overworld scene.
2. Pick an `Encounter Type` in the inspector: `BATTLE`, `SHOP`, `CAMPFIRE`,
   `TREASURE` or `EVENT`.
3. For a battle, either assign a specific `Battle Stats` resource from
   `battles/`, or leave it empty to roll a random battle of the matching tier
   from `battles/battle_stats_pool.tres`.
4. `Trigger On Touch` fires the moment the player steps on it; leave it off and
   the player presses `ui_accept` while standing on the tile.
5. `Encounter Chance` below 1.0 turns it into a random-encounter tile.
6. `One Shot` (default on) keeps a cleared encounter cleared for the rest of the
   run.

The trigger calls `GameState.request_encounter(...)`, which switches to
`Scenes/run/run.tscn`. When the encounter finishes, `Run` writes the results
back into `GameState` and returns the player to the exact overworld tile and
scene they left from.

## The run state

`global/GameState.gd` is the bridge. It keeps:

- `character: CharacterStats` — live HP, mana, and the persistent deck
- `run_stats: RunStats` — gold, card-reward weights, cards removed
- `relics: Array[Relic]`
- `cleared_encounters` — so one-shot triggers stay defeated
- `world_map_position` / `overworld_scene_path` — where to come back to

`GameState.start_new_run()` builds a fresh run from
`characters/warrior/warrior.tres`. `GameState.end_run()` wipes it (this is what
the Game Over screen does).

## Scene map

| Path | What it is |
| --- | --- |
| `Scenes/run/run.tscn` | Hosts one encounter + the persistent top bar (HP, gold, relics, deck view, pause menu) |
| `Scenes/battle/battle.tscn` | Full combat scene: turn loop, mana, piles, intents, tooltips, statuses |
| `Scenes/battle_reward/` | Post-combat gold / card / relic rewards |
| `Scenes/shop/` | Cards, relics, and the card-removal service |
| `Scenes/campfire/` | Rest (+30% max HP) and Forge (upgrade a card) |
| `Scenes/treasure/` | Chest that rolls an unowned relic |
| `Scenes/event_rooms/` | Gamble + Helpful Boi random events |
| `Scenes/enemy/` | Enemy AI action picker, weighted action selection, enemy handler |
| `Scenes/player/player_handler.gd` | Player turn order: relics → statuses → draw → end turn → discard |
| `Scenes/status_handler/`, `Scenes/modifier_handler/` | Buff/debuff pipeline (Exposed, Muscle, True Strength) |
| `Scenes/relic_handler/` | Relic slots, tooltips, paging |
| `Scenes/ui/card_selection_view.tscn` | Shared "pick a card from your deck" overlay used by Forge and card removal |

New autoloads registered in `project.godot`: `RNG`, `Shaker`, `MusicPlayer`,
`SFXPlayer`. `Events` and `GameState` keep their existing UIDs.

## Files that were extended rather than added

- `custom resources/card.gd` — gained rarity, cost, exhausts, icon, tooltip,
  sound, the effect pipeline, and the upgrade system. `Type.DEFEND` occupies the
  slot the tutorial calls `SKILL`, so your existing `.tres` cards still load.
- `custom resources/card_pile.gd` — fixed `cards.size` → `cards.size()`, added
  `remove_card()` and the explicit deep-copy helpers.
- `custom resources/stats.gd` / `character_stats.gd` — `set_max_health`,
  draftable cards, starting relic, `player_hit` signal.
- `global/events.gd` — the full event bus.
- `global/GameState.gd` — run state on top of your `world_map_position`.
- `Scenes/card_ui/*` — visuals, playability, tooltips, `post_enter()`.
  The old `Color` / `CardState` debug nodes are still there, just hidden;
  `CardUI.set_debug_state()` drives them if you re-enable them.
- `Scenes/enemy_battle.gd` + `Scenes/enemy.tscn` — intents, statuses, modifiers.
  `stats` stays typed as `Stats` (not `EnemyStats`) so
  `enemies/dev_crab/test_enemy.tres` keeps working.
- `Scenes/player_battle.gd` + `Scenes/player_battle.tscn` — statuses, modifiers.
  It no longer calls `create_instance()`; the run owns the live stats so HP
  carries between encounters.
- `Scenes/hand_logic/player_hand.gd` — draw/discard/enable/disable.
- `Scenes/enemy.tscn` / `Scenes/player_battle.tscn` — joined the tutorial's
  `enemies` / `player` groups *in addition to* your `enemies_battle` /
  `player_battle` groups, so nothing that referenced the old names broke.

## Card upgrades (deck customization)

`Card.upgrade()` marks the card, appends `+` to its id, optionally reduces cost
(`upgrade_cost_reduction`) and calls `_apply_upgrade()`.

Concrete cards store their bonus in `upgrade_power`, which is **exported on
purpose**: plain script vars are not carried over by `Resource.duplicate()`, so
an upgrade kept in a plain var would silently vanish the moment the deck was
copied into the draw pile.

To make a new card upgradable, override `_apply_upgrade()` and read
`upgrade_power` wherever you use the base number:

```gdscript
extends Card

var base_damage := 4

func get_damage() -> int:
    return base_damage + upgrade_power

func _apply_upgrade() -> void:
    upgrade_power = 3
```

## Season 2 finale fixes

| # | Fix | Where |
| --- | --- | --- |
| 1 | Fast-click double-fire lock | `Scripts/encounter_trigger.gd` (`_fired` guard) — the map-node version of this bug does not exist here |
| 2 | Campfire rest spamming | `Scenes/campfire/campfire.gd` disables Rest on the first click |
| 3 | Off-card dragging | `card_base_state.gd` `mouse_over_card` |
| 4 | Deck-view scroll pass-through | `mouse_force_pass_scroll_events = false` on `card_pile_view.tscn` and `card_selection_view.tscn` |
| 5 | Sub-resource deep duplication | `CardPile.duplicate_cards()` / `custom_duplicate()`, used by `PlayerHandler`, `CharacterStats`, `BattleReward`, `Shop` |
| 6 | Target array persistence | `targets.clear()` in both the aiming and dragging cancel paths |
| 7 | Unix floating-card bug | `CardState.post_enter()` + `CardStateMachine` calling it |
| 8 | Game Over soft-lock | Game Over leaves the scene entirely (`end_run()` → overworld); `Shaker` null-checks |
| 9 | Empty relic pool crash | `RNG.array_pick_random` returns null; guards in `Treasure`, `Shop`, `BattleReward` |
| 10 | Exact-gold purchase | `>=` in `shop_card.gd`, `shop_relic.gd`, and the removal service |

## Known gaps

- No save/load. `SaveGame` was intentionally left out because the run now lives
  in the overworld, not on a map. `GameState` is the obvious place to add it.
- Only the Warrior is set up (`characters/warrior/warrior.tres`). The assassin
  and wizard from the tutorial were not ported.
- `Scenes/battle.tscn` (your original prototype) is untouched and still uses
  `dev_warrior_*` cards with no effects — the real combat scene is
  `Scenes/battle/battle.tscn`.
- Art lives in `Placeholder Assets/deckbuilder/` (Kenney's tiny dungeon pack +
  the tutorial's sound effects). The tutorial's background music track was not
  copied.

# Wild Ranch – Development Documentation

The design source of truth is `Wild_Ranch_Complete_Design_Notes.docx`. This file records
*how* the game is built: architecture (B), the implementation checklist (C), and the
implementation decisions made along the way.

---

## B. Architecture

### Toolchain
- **Rojo** syncs `SRC/` into Studio (`default.project.json`). Tool versions pinned in `rokit.toml`.
- Code lives in files. Maps, models and other 3D content are built in Studio.
- Third-party code is vendored (copied in, pinned to a commit) under `SRC/Server/Vendor/`;
  licenses in `THIRD_PARTY_LICENSES/`.

| Folder | Roblox location |
|---|---|
| `SRC/Shared` | `ReplicatedStorage.Shared` |
| `SRC/Server` | `ServerScriptService.Server` |
| `SRC/Client` | `StarterPlayer.StarterPlayerScripts.Client` |

### Code layout
```
SRC/Shared/Config/   all tunable numbers (locked values from the design doc; OPEN items marked)
SRC/Shared/Types/    data shapes shared by client and server (Animal, PlayerData)
SRC/Shared/Rules/    pure game-rule functions (rolls, income, stamina, taming math)  [Phase 2]
SRC/Shared/Net/      Remotes – the one list of every RemoteEvent/RemoteFunction
SRC/Shared/Util/     Signal, Loader
SRC/Server/Main      boots Services/ ; Services/<Name>Service.luau ; Data/ (schema, migrations)
SRC/Server/Vendor/   ProfileStore
SRC/Client/Main      boots Controllers/ ; Controllers/<Name>Controller.luau ; UI/ (later)
```

### Conventions
- One `Script` (server) and one `LocalScript` (client). Everything else is a ModuleScript.
- Services/controllers are plain tables with optional `LoadOrder`, `Init`, `Start`.
  `Init` = local setup only; `Start` = may use other modules. Modules reach each other by `require`.
- The server owns all rolls, saved data, the taming meter, income, purchases and unlocks.
  Every remote argument from a client is validated on the server.
- No magic numbers in gameplay code: values come from `Shared/Config`.
- Undecided design values are left **unset** in config with an `OPEN QUESTION` comment, so
  code fails loudly instead of guessing.

### Animal data structure (one shape for an animal's whole life)
`Shared/Types/Animal.luau` defines two shapes, so the same traits flow unchanged
from spawning → taming → inventory → ranch → mount:

| Shape | When it exists | Fields |
|---|---|---|
| `AnimalTraits` | Rolled in the run plan at the starting line; never re-rolled | `Species`, `Stars` (0–5), `Variant` (Normal/Gold/Rainbow), `BiomeCaught` |
| `OwnedAnimal` (saved) | Created by the server on Capture & Return Home | all traits + `Level` (starts at 1), `Placed` (in ranch or not); stored under a server-generated unique id |

- Only the server creates an owned animal or changes its fields.
- Derived stats (income/sec, max stamina, max level) are **computed** from these fields plus
  Config by `Shared/Rules`, never stored, so a save can't hold a stale or tampered number.
- `BiomeCaught` is a biome id; its income multiplier is looked up from `BiomeConfig`.

### Save data
- ProfileStore with session locking; one profile per player, key `Player_<UserId>`.
- `SchemaVersion` in every save. On load, migrations upgrade old saves step by step
  (`Server/Data/Migrations`). A save newer than the server understands is never touched:
  the player is kicked with a "server outdated" message instead of risking data loss.

### Reproducible run generation
- At the starting line the server creates a **seed** (`Random.new():NextInteger(1, 2^31 - 1)`).
- `Shared/Rules/RunPlanner` is a pure function: `RunPlanner.Plan(seed, biome, reachableSegments)`
  → run plan. It uses one `Random.new(seed)` and draws in a fixed order
  (segment → animal count → per animal: line position, side, species, stars, variant).
  Same seed + same inputs + same config = identical plan.
- The seed is logged with each run and kept in the run session, so any encounter can be
  replayed in Studio with a debug command.

### Multiplayer course model (designer decision 2026-11-18)
- **Course geometry is shared**: one course per biome in the world; all riders use it at once.
- **Encounters are individual**: each player's run has its own seeded plan. Player A may see a
  Gold Deer where Player B sees a normal Fox; neither sees the other's encounter animals.
  - The server keeps each player's plan; only that player's client receives it and renders
    those animals locally.
- **Players cannot collide**: riders (and mounts) are in a collision group that does not collide
  with other riders, so passing through someone never changes your steering or path.
- **Targeting only considers your own encounter animals**, never other players or their animals.
- The server validates every target, lasso and catch against **that player's** plan and position.

### Monetization
- `MonetizationService` (gem products, Robux, `ProcessReceipt`) stays in the architecture but is
  **not implemented until Phase 11**, isolated so a purchase failure can never block the core loop.

---

## C. Development Roadmap – Implementation Checklist

Rule: each phase builds a **functional** system and is tested before the next phase starts.
Visual quality (animations, terrain, models, VFX, sound, UI styling) is **not** part of a
build phase – it belongs to Phase 13. Phase order is fixed.

### Phase 0 – Project skeleton ✅
- [x] Rojo project, folder layout, Loader, Remotes list, locked config values
- [x] Test: Rojo build places every script correctly

### Phase 1 – Data foundation ✅
- [x] ProfileStore saving with session locks, versioned schema + migrations
- [x] Owned animals: unique id, `{Species, Stars, Variant, BiomeCaught, Level, Placed}`
- [x] Coins and gems balances; client receives a read-only copy of its own data
- [x] Studio debug commands (give/remove animal, add coins, print profile)
- [x] Test: data survives rejoin
- [x] Test: **two players** join, get separate profiles, and save independently

### Phase 2 – Rules modules ✅
- [x] Star/variant/species rolls with normalization, income, stamina, level caps, taming math
- [x] Test: automated tests + large roll simulations match the design doc's odds

### Phase 3 – Grey-box course & riding
- [ ] Grey-box Plains: starting area, starting line, segments, walls, bush strips (plain parts)
- [ ] Auto-forward riding with left/right steering on PC, mobile and gamepad
- [ ] **Temporary test mount** with fixed stamina (removed in Phase 8)
- [ ] Stamina drains by distance; collapse at 0 ends the run; return to ranch
- [ ] Test: ride until stamina runs out on all three input types
- Not in this phase: terrain, real models, animations, effects

### Phase 4 – Run generation & encounters
- [ ] Reachability → segments generated; seeded RunPlanner; spawn lines; left/right sides
- [ ] Animals emerge from bushes, flee ahead, can pull ahead
- [ ] Test: debug view of lines; same seed reproduces the same plan; unreachable segments empty
- Not in this phase: emergence animation polish, final animal models

### Phase 5 – Targeting & lasso
- [ ] Yellow/red ring selection and lock rules, dotted outline, stars shown, `???` names
- [ ] Lasso trigger and biome lasso requirement
- [ ] Test: lock/unlock behaves exactly as the design doc describes

### Phase 6 – Taming QTE
- [ ] Server-authoritative meter, random directional prompts, grace, drain, mistake rule
- [ ] Success popup (Capture & Return Home) and thrown-off failure
- [ ] Test: all three input types; server rejects forged inputs
- Not in this phase: prompt art, popup styling

### Phase 7 – Ranch, inventory, income
- [ ] Plot assignment, place/pick up, roaming, capacity, collection pad, income ticking
- [ ] Test: full loop catch → place → earn → collect; two players' plots stay separate

### Phase 8 – Mounts
- [ ] Mount selection, coin leveling, star-based level caps; replaces the test mount
- [ ] Test: a leveled mount reaches farther segments

### Phase 9 – Biome progression
- [ ] Unlocks, level select, Savannah, starting-area shop, lasso tiers, biome multipliers
- [ ] Test: reaching Savannah unlocks it permanently and it can be selected later

### Phase 10 – Journal
- [ ] Species/variant entries, silhouettes + `???`, star records, completion %, milestone rewards
- [ ] Test: entries and completion update correctly on capture

### Phase 11 – Failure, retry, monetization
- [ ] Result screen; **gem retry first** (restart at the start of the level)
- [ ] Then Robux products with safe receipt handling, isolated from the core loop
- [ ] Test: retry restarts the correct level; purchases grant exactly once

### Phase 12 – Leaderboards
- [ ] Most animals caught, most money earned, rarest catch boards in the spawn area

### Phase 13 – Polish
- [ ] Low-poly art, terrain, animal models and animations, emergence/taming VFX, sound
- [ ] Final UI styling for PC/mobile/console, performance pass on low-end mobile

### Later
- Quests (gem source), stealing

---

## Open design decisions (by phase that needs them)

These are undecided in the design notes. Each must be decided by the designer **before** the
phase that depends on it is implemented. Until then the config value stays unset and any code
that needs it fails with an `OPEN QUESTION` error. Remove a row once decided and log it below.

| Needed by | Decision |
|---|---|
| Before they are added | Obstacles and jumping: what they are, placement, jump controls. **Excluded from Phase 3** (designer decision 2026-11-18); may relate to aggressive animals (Phase 4) |
| Phase 3 | Segments per biome (the multiplier chart implies 5), segment length, corridor width |
| Phase 3 | Stamina consumed per stud; temporary test mount's stamina |
| Phase 4 | Species list per biome and spawn weights by distance |
| Phase 4 | Animal count per segment: equal chance of 3, 4 or 5? |
| Phase 4 | Bush emergence trigger distance; flee speed/turning/aggression; whether Gold/Rainbow escape faster |
| Phase 5 | Yellow/red ring radii, lasso trigger, lasso tiers and prices |
| Phase 6 | Taming balance concern (two correct inputs inside the grace period always tame) – keep or adjust |
| Phase 7 | **Rainbow stat multiplier (3× or 4×)** |
| Phase 7 | **Species base income**; **biome income multipliers** |
| Phase 7 | Starting coins/gems, inventory and ranch capacities, pen milestones, offline income |
| Phase 8 | **Species base stamina**, stamina per level, mount level prices |
| Phase 8 | Starter mount for new players (they own no animals); Phase 3 uses the temporary test mount instead |
| Phase 9 | Biome unlock requirements, starting-area shop items and prices |
| Phase 10 | Journal milestone rewards |
| Phase 11 | Gem retry cost, Robux products and prices, quests |
| Phase 12 | How "rarest catch" is ranked; whether "money earned" means lifetime earnings |

---

## Implementation decision log
- 2026-11-15 – Use Rojo with file-based source in `SRC/` (designer approved).
- 2026-11-15 – Designer refinements adopted: dedicated animal data structure; seeded,
  reproducible RunPlanner; MonetizationService deferred until Phase 11.
- 2026-11-15 – Capture biome stored as an id, not a copy of its multiplier; tuning a biome's
  multiplier applies to animals already caught there (designer approved).
- 2026-11-15 – Newly captured animals start at mount Level 1 (designer approved).
- 2026-11-15 – Saved animal record = `{Species, Stars, Variant, BiomeCaught, Level, Placed}`,
  keyed by a server-generated unique id. Save data carries `SchemaVersion` with migrations.
  Saving uses ProfileStore, vendored at commit `45c9847` (designer approved).
- 2026-11-15 – Roadmap adjustments (designer): temporary test mount in Phase 3; Phase 1 verifies
  two players get separate profiles that save independently; Phase 11 tests gem retry first,
  then Robux, with purchase handling isolated from the core loop.
- 2026-11-15 – Roadmap separates building a system (functional, grey-box) from polishing it
  (Phase 13). This checklist (Section C) is the working implementation checklist (designer).
- 2026-11-18 – Segment star multiplier boosts **3–5★ only**; 0–2★ keep their base weights, then
  the distribution is normalized to 100% (designer decision). At 2×: 45.0 / 22.5 / 12.6 /
  14.4 / 4.5 / 0.9 % for 0–5★.
- 2026-11-18 – *Interpretation:* the Gold/Rainbow multiplier applies to a species' **base**
  stamina; the fixed per-level stamina bonus is added on top and is not multiplied. Level 1 has
  no bonus. All random rolls draw from arrays in a fixed order so a seed always reproduces.
- 2026-11-18 – Review follow-up: rules reject NaN/infinite/negative weights, non-positive or
  non-finite stamina rates and amounts, and non-finite taming time steps; edge-case tests added
  for invalid weights, stamina rates, star ratings and inputs after a finished tame.
- 2026-11-18 – Shared course geometry with individually generated encounters per player; players
  pass through each other without affecting steering or targeting; the server validates each
  player's encounters and catches independently (designer decision).
- 2026-11-18 – Starter mount moved to "needed by Phase 8": Phase 3 rides the temporary test mount.
- 2026-11-18 – Obstacles and jumping are excluded from Phase 3 until designed; runs end only by
  stamina reaching 0 or a failed tame. Riding code leaves room to add them later (designer decision).
- 2026-11-18 – Review follow-up (ChatGPT on df339fe): WeightedRandom also rejects a total weight
  that overflows to infinity; edge-case test added.

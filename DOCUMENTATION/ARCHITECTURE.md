# Wild Ranch – Technical Architecture

The design source of truth is `Wild_Ranch_Complete_Design_Notes.docx`. This file records
*how* the game is built and the implementation decisions made along the way.

## Toolchain
- **Rojo** syncs `SRC/` into Studio (`default.project.json`). Tool versions pinned in `rokit.toml`.
- Code lives in files. Maps, models and other 3D content are built in Studio.

| Folder | Roblox location |
|---|---|
| `SRC/Shared` | `ReplicatedStorage.Shared` |
| `SRC/Server` | `ServerScriptService.Server` |
| `SRC/Client` | `StarterPlayer.StarterPlayerScripts.Client` |

## Code layout
```
SRC/Shared/Config/   all tunable numbers (locked values from the design doc; OPEN items marked)
SRC/Shared/Rules/    pure game-rule functions (rolls, income, stamina, taming math)  [Phase 2]
SRC/Shared/Net/      Remotes – the one list of every RemoteEvent/RemoteFunction
SRC/Shared/Util/     Signal, Loader
SRC/Server/Main      boots Services/ ; Services/<Name>Service.luau
SRC/Client/Main      boots Controllers/ ; Controllers/<Name>Controller.luau ; UI/ (later)
```

## Conventions
- One `Script` (server) and one `LocalScript` (client). Everything else is a ModuleScript.
- Services/controllers are plain tables with optional `LoadOrder`, `Init`, `Start`.
  `Init` = local setup only; `Start` = may use other modules. Modules reach each other by `require`.
- The server owns all rolls, saved data, the taming meter, income, purchases and unlocks.
  Every remote argument from a client is validated on the server.
- No magic numbers in gameplay code: values come from `Shared/Config`.
- Undecided design values are left **unset** in config with an `OPEN QUESTION` comment, so
  code fails loudly instead of guessing.

## Animal data structure (one shape for an animal's whole life)
`Shared/Types/Animal.luau` (Phase 1) defines two shapes, so the same traits flow unchanged
from spawning → taming → inventory → ranch → mount:

| Shape | When it exists | Fields |
|---|---|---|
| `AnimalTraits` | Rolled in the run plan at the starting line; never re-rolled | `Species`, `Stars` (0–5), `Variant` (Normal/Gold/Rainbow), `Biome` (biome it was encountered in) |
| `OwnedAnimal` | Created by the server on Capture & Return Home | all `AnimalTraits` + `Id` (server GUID), `Level`, `Location` (Inventory/Ranch), `CaughtAt` |

- Only the server creates an `OwnedAnimal` or changes its fields.
- Derived stats (income/sec, max stamina, max level) are **computed** from these fields plus
  Config by `Shared/Rules`, never stored, so a save can't hold a stale or tampered number.
- The biome is stored as an id (`Biome = "Plains"`); its income multiplier is looked up from
  `BiomeConfig`. (Recommendation – see decision log.)

## Reproducible run generation
- At the starting line the server creates a **seed** (`Random.new():NextInteger(1, 2^31 - 1)`).
- `Shared/Rules/RunPlanner` is a pure function: `RunPlanner.Plan(seed, biome, reachableSegments)`
  → run plan. It uses one `Random.new(seed)` and draws in a fixed order
  (segment → animal count → per animal: line position, side, species, stars, variant).
  Same seed + same inputs + same config = identical plan.
- The seed is logged with each run and kept in the run session, so any encounter can be
  replayed in Studio with a debug command.
- Changing draw order or config values changes which plan a seed produces; that is expected.

## Monetization
- `MonetizationService` (gem products, Robux, `ProcessReceipt`) stays in the architecture but is
  **not implemented until Phase 11**, after core gameplay and the coin economy work.

## Roadmap
0. Skeleton ✅ · 1. Data foundation · 2. Rules modules · 3. Grey-box course & riding ·
4. Run generation & encounters · 5. Targeting & lasso · 6. Taming QTE ·
7. Ranch, inventory, income · 8. Mounts · 9. Biome progression · 10. Journal ·
11. Failure/retry/monetization · 12. Leaderboards · 13. Polish · Later: quests, stealing

## Implementation decision log
- 2026-11-15 – Use Rojo with file-based source in `SRC/` (designer approved).
- 2026-11-15 – Designer refinements adopted: dedicated animal data structure; seeded,
  reproducible RunPlanner; MonetizationService deferred until Phase 11.
- 2026-11-15 – *Recommendation, awaiting confirmation:* store the capture biome as an id rather
  than a copy of its multiplier number, so tuning a biome's multiplier later applies to animals
  already caught there.
- 2026-11-15 – *Recommendation, awaiting confirmation:* newly captured animals start at
  mount Level 1.

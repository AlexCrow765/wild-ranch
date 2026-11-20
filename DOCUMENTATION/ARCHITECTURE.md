# Wild Ranch – Development Documentation

The design source of truth is `DOCUMENTATION/Wild_Ranch_Complete_Design_Notes.docx`. This file
records *how* the game is built: architecture (B), the implementation checklist (C), and the
implementation decisions made along the way.

Where a later designer decision recorded here replaces a rule in the design notes, the
**"Designer decisions that supersede the design notes"** section below lists it. Those entries
win over the .docx until the .docx is updated.

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
SRC/Shared/Rules/    pure game-rule functions (rolls, income, speed, stamina, level scaling, taming math)
SRC/Shared/Net/      Remotes – the one list of every RemoteEvent/RemoteFunction
SRC/Shared/Util/     Signal, Loader, WeightedRandom, Validate
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
- Derived stats (income/sec, speed, max stamina, max level) are **computed** from these fields plus
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
  (segment → animal count (1–3) → which encounter slots → per animal: side, emergence position,
  species, stars, variant).
  Same seed + same inputs + same config = identical plan.
- The seed is logged with each run and kept in the run session, so any encounter can be
  replayed in Studio with a debug command.

### Run validation: accepted progress vs physical position
Two different "positions" exist during a ride; gameplay must use the right one.

| | **Accepted progress** (`RunProgress.Progress`) | **Physical position** (the character's `HumanoidRootPart`) |
|---|---|---|
| Owned by | the server | the player's client (it simulates its own character) |
| Can go backwards | never | yes |
| Upper limit | `speed × (elapsed + LeadAllowanceSeconds)` — at most **8 studs** ahead of a perfect rider at 32 studs/s | not limited directly; the server only **moves the character back** once it is more than `PullBackStuds` (**20 studs**, unchanged since Phase 3, intentional) beyond accepted progress |
| Used for | stamina, collapse, end of course, the stamina bar / distance sent to the client, logs, `runinfo` | only: detecting the starting-line crossing, the input to `RunProgress.Step`, and the pull-back / sideways-correction checks |

- So a character can **physically** be up to about **28 studs** ahead of a perfect rider at
  32 studs/s (8-stud lead allowance + 20-stud pull-back threshold) before it is moved back —
  in general `speed × LeadAllowanceSeconds + PullBackStuds`. Legitimate riders never get there:
  measured lead is 0.
- That physical tolerance **cannot earn anything**: stamina, distance and run end are calculated
  only from accepted progress (regression test in `Course.spec`). The 20-stud margin exists only
  so honest players are not visibly rubber-banded by small corrections.
- **Rule for later phases:** encounter targeting, lassoing and catching (Phases 4–6) must be
  validated on the server against **accepted progress** (and the server's own animal positions),
  never against the raw character position, which may be up to ~28 studs further ahead.

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

### Biome course dimensions (designer decisions 2026-11-18)
| Value | Decision |
|---|---|
| Segments per biome | **5**, after the starting area |
| Baseline riding speed | **32 studs/s** |
| Segment length | **576 studs** (≈ 18 s at 32 studs/s) |
| Full biome length | **2,880 studs** (5 × 576) |
| Target time for a full biome | **≈ 90 s** with enough stamina (starting area not included) |
| Star-odds multipliers | starting area 1×, Seg 1 1×, Seg 2 1.25×, Seg 3 1.5×, Seg 4 1.75×, Seg 5 2× (3–5★ boosted only, see `RarityConfig`) |

- The 90 s is a **target** for a player whose stamina lasts the whole biome, **not** a guaranteed
  run length: a mount with less stamina runs out partway through.
- **Travel time and stamina are separate mechanics.** The 18 s per segment sets course length;
  it is **not** a stamina drain rate. Stamina drains by distance only.
- Stamina decides how far a player gets; mount leveling and upgrades let players reach
  progressively deeper segments.

### Corridor and bushes (designer decisions 2026-11-18)
- **Total corridor width: 100 studs.**
- Bushes line **both sides**, each up to **13 studs** wide.
- **Invisible collision boundaries** stop players and mounts from entering the bushes.
- With maximum-width bushes the playable centre is **at least 74 studs** wide (100 − 2 × 13).
- Encounter animals emerge **from these bushes** into the corridor.

### Encounter generation (designer decisions 2026-11-18)
- Each segment independently generates **1–3 animals** → **5–15 animals** per full biome.
- Each segment has **predefined encounter slots**; the server randomly selects slots for each
  player's run. Selected slots have **varied spacing, subject to a minimum separation**.
  (Slot count, layout and the minimum separation are still open.)
- Each animal emerges from the **left or right** bushes and has an assigned **emergence position**.
- Species, star rating and variant are decided in the player's **run plan** at the starting line.
- Plans are **independent per player** even though the course geometry is shared.

### Emergence and animal movement (designer decisions 2026-11-18)
- Animals start **hidden inside their assigned bushes**; when the player approaches, the animal
  **runs out of the bushes** into the corridor.
- Movement uses **Rodeo Stampede** as the behavioural reference.
- Animals have **species-specific movement speeds and behaviours**; they are **not** forced to
  move at the player's speed. Species should feel distinct, and some should be substantially
  harder to pursue, so players need progressively better mounts to catch them reliably.
- Detailed per-species behaviour profiles are designed later, with the animal roster.

### Animal stats, mount leveling and variants (designer decisions 2026-11-18)
**Species base stats.** Every species has its own independently designed **base speed**,
**base stamina** and **base income**. There is no required trade-off between speed and stamina.

**Variant multipliers** (apply equally to all three base stats; supersede the old Gold 2× /
Rainbow 3–4×):

| Variant | Speed | Stamina | Income |
|---|---:|---:|---:|
| Normal | 1× | 1× | 1× |
| Gold | 1.25× | 1.25× | 1.25× |
| Rainbow | 1.75× | 1.75× | 1.75× |

**Mount leveling.** Same rates for every species, additive, never compounded:
- Speed: **+0.1%** of base speed per level gained (small secondary benefit).
- Stamina: **+1%** of base stamina per level gained (the main benefit).

The variant multiplier is applied to the species' base stats **before** level bonuses:
```
Speed   = Base Speed   × Variant × (1 + 0.001 × (Level − 1))
Stamina = Base Stamina × Variant × (1 + 0.01  × (Level − 1))
Income  = Base Income  × Variant × Star income multiplier × Biome income multiplier
```

**Star rating** (unchanged): stars affect only the **income multiplier** (1, 1.25, 1.5, 1.75, 2,
2.5 for 0–5★) and the **maximum mount level** (5, 10, 20, 30, 40, 50). Stars do **not** change
base speed, base stamina or the growth percentages.

### Phase 3 prototype targets (designer decisions 2026-11-18)
- **Temporary test mount: 100 stamina**, riding at the 32 studs/s baseline.
- **Starter mount target:** reach about **halfway through Segment 2**, about **864 studs**
  (576 + 288), about **27 s** of riding at 32 studs/s.
- **Provisional stamina drain: ≈ 0.11574 stamina per stud** (100 ÷ 864).
  **This is a prototype value that must be validated in Studio**, not a final balance value.

### Designer decisions that supersede the design notes
These later decisions replace rules in `Wild_Ranch_Complete_Design_Notes.docx`. Follow these
until the .docx is updated.

| Design notes said | Now (2026-11-18) |
|---|---|
| 3–5 animals per segment, one invisible spawning line per animal, segment split evenly, random point along the line (§2.C) | 1–3 animals per segment in randomly selected predefined encounter slots with varied spacing and a minimum separation |
| Mount speed removed completely as a core/visible/upgradable stat; leveling does not increase speed (§2.F) | Species have base speed; leveling adds +0.1% of base speed per level; variants multiply speed |
| Each mount level adds a fixed stamina amount (§2.F) | Each level adds 1% of the (variant-adjusted) base stamina – still a fixed amount per level for a given animal, but it scales with the species |
| Gold 2× base stats; Rainbow 3× or 4× (§2.D) | Gold 1.25×, Rainbow 1.75× on speed, stamina and income |
| Animals run just ahead of the player at a pace that lets the player choose (§2.E) | Species-specific speeds and behaviours; some species are substantially harder to pursue |

### Blender → Roblox asset scale (designer convention, verified 2026-11-19)
- **1 Blender unit = 1 Roblox stud.** Model at the real stud size; never rely on export scaling.
- Keep transforms clean before export: scale (1, 1, 1), rotation (0, 0, 0), origin placed
  deliberately (e.g. geometric centre).
- **Blender FBX export settings** (Roblox-recommended; tested):

  | Setting | Value |
  |---|---|
  | Limit to | Selected objects, Mesh |
  | Scale | 1.0 |
  | Apply Unit | on |
  | Apply Scalings | **FBX Unit Scale** |
  | Forward / Up | **Z Forward / Y Up** |
  | Apply Transform | off |
  | Apply Modifiers | on |
  | Smoothing | Face |
  | Leaf bones / Animation / Custom properties / Embed textures | off |

  Blender scene left at its defaults (Metric, Unit Scale 1.0). The exported FBX reports
  UnitScaleFactor 100, which Studio imports correctly with these settings.
- **Studio 3D Importer:** Scale Unit **Stud**, World Forward **Front**, World Up **Top**.
- **Verified:** `TEST_10_STUD_CUBE` (10 × 10 × 10 Blender units) imported as a MeshPart of
  Size **10, 10, 10** studs (Model scale 1, pivot Y = 5 on a Y = 0 surface).
- Roblox limits to respect: ≤ 20,000 triangles per mesh, no N-gons, no zero-thickness geometry.
- Test exports live in `ASSETS/_ScaleTest/` and are not part of the game code.

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

### Phase 3 – Grey-box course & riding ✅
- [x] Grey-box Plains: starting area, starting line, 5 × 576-stud segments, 100-stud corridor,
      bush strips (up to 13 studs each side) behind invisible collision boundaries (plain parts)
- [x] Auto-forward riding at 32 studs/s with left/right steering on PC, mobile and gamepad;
      riders pass through each other
- [x] **Temporary test mount** with 100 stamina (removed in Phase 8)
- [x] Stamina drains by distance (provisional ≈ 0.11574/stud); collapse at 0 ends the run;
      return to ranch
- [x] Test: the test mount runs out at ≈ 864 studs (about halfway through Segment 2); tune the
      drain rate in Studio if needed
- [x] Test: ride until stamina runs out on all three input types
- Studio results (2026-11-19): 58 automated tests pass; collapse at 864.3 and 865.1 studs
  (Segment 2) with 0 rejected samples; PC, gamepad, mobile (device emulator) and two-player
  checks confirmed by the designer. Real-phone test still to do. Drain rate 0.11574/stud kept.
- Not in this phase: terrain, real models, animations, effects

### Phase 4 – Run generation & encounters
- [ ] Reachability → segments generated; seeded RunPlanner; 1–3 animals per segment in
      randomly selected encounter slots; left/right side and emergence position per animal
- [ ] Animals hide in bushes, run out as the player approaches, then move with
      species-specific speed and behaviour; can pull ahead
- [ ] Server decides when an animal emerges from the rider's **accepted progress**
      (`RunProgress.Progress`), not the raw character position
- [ ] Test: debug view of slots; same seed reproduces the same plan; unreachable segments empty
- Not in this phase: emergence animation polish, final animal models

### Phase 5 – Targeting & lasso
- [ ] Yellow/red ring selection and lock rules, dotted outline, stars shown, `???` names
- [ ] Lasso trigger and biome lasso requirement
- [ ] Server validates every target, lasso and catch against the rider's **accepted progress**
      and the server's own animal positions (the character may physically be up to ~28 studs
      ahead); client requests alone never select or catch
- [ ] Test: lock/unlock behaves exactly as the design doc describes; a client claiming a
      catch from an invalid position is rejected

### Phase 6 – Taming QTE
- [ ] Server-authoritative meter, random directional prompts, grace, drain, mistake rule
- [ ] Success popup (Capture & Return Home) and thrown-off failure
- [ ] Test: all three input types; server rejects forged inputs
- Not in this phase: prompt art, popup styling

### Phase 7 – Ranch, inventory, income
- [ ] Plot assignment, place/pick up, roaming, capacity, collection pad, income ticking
- [ ] Test: full loop catch → place → earn → collect; two players' plots stay separate

### Phase 8 – Mounts
- [ ] Mount selection, coin leveling (+1% base stamina, +0.1% base speed per level),
      star-based level caps; replaces the test mount
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
| Phase 3 | **Final stamina consumption per stud** – provisional 0.11574/stud must be validated in Studio |
| Phase 3 | Exact corridor/bush geometry implementation (bush shapes, boundary placement within the 100-stud corridor) |
| Phase 3 | Any movement tuning needed after Studio testing (steering feel, acceleration) |
| Phase 4 | Species list per biome and spawn weights by distance |
| Phase 4 | Encounter slot count and layout per segment; minimum separation between selected slots |
| Phase 4 | Chance of 1, 2 or 3 animals per segment (equal unless decided otherwise) |
| Phase 4 | Bush emergence trigger distance; species movement/escape behaviours (Rodeo Stampede reference); whether Gold/Rainbow escape faster |
| Phase 5 | Yellow/red ring radii, lasso trigger, lasso tiers and prices |
| Phase 6 | Taming balance concern (two correct inputs inside the grace period always tame) – keep or adjust |
| Phase 7 | **Species base income**; **biome income multipliers** |
| Phase 7 | Starting coins/gems, inventory and ranch capacities, pen milestones, offline income |
| Phase 8 | **Species base speed and base stamina**; mount level prices |
| Phase 8 | Which animal the starter mount is (its reach target is ≈ 864 studs); Phase 3 uses the temporary test mount instead |
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
- 2026-11-18 – *Interpretation (superseded later the same day by the stat/leveling decision
  below):* the Gold/Rainbow multiplier applied to base stamina only, with a flat per-level bonus.
  Still current: all random rolls draw from arrays in a fixed order so a seed always reproduces.
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
- 2026-11-18 – Each biome has **5 segments**; target time to ride a full biome is **90 s**
  (~18 s per segment at consistent forward movement). Segment multipliers unchanged
  (start 1×, then 1×, 1.25×, 1.5×, 1.75×, 2×). 90 s is a target for players with enough
  stamina, not a guaranteed run length. Travel time is separate from stamina: the 18 s sets
  segment length, not a drain rate; stamina per stud is still undecided (designer decision).
- 2026-11-18 – Course dimensions (designer): 32 studs/s baseline riding speed; 576-stud segments;
  2,880-stud biome; ≈ 90 s full traversal. Corridor 100 studs wide with bushes up to 13 studs per
  side behind invisible collision boundaries (≥ 74-stud playable centre). Supersedes an earlier
  70-stud corridor / 24 studs/s / 2-minute proposal that was never adopted here.
- 2026-11-18 – Encounters (designer): 1–3 animals per segment (5–15 per biome) in randomly selected
  predefined slots with varied spacing and a minimum separation; left/right emergence position per
  animal; animals hide in bushes and run out as the player approaches; species-specific movement
  (Rodeo Stampede reference). **Supersedes** the design notes' 3–5 animals / one spawning line per
  animal.
- 2026-11-18 – Stats (designer): species have independent base speed, stamina and income. Leveling
  adds +0.1% base speed and +1% base stamina per level (additive, from base). Variants Gold 1.25×,
  Rainbow 1.75× on all three stats, applied before level bonuses. Stars affect only income and
  max level. **Supersedes** the design notes' "no mount speed stat", fixed stamina per level and
  Gold 2× / Rainbow 3–4×.
- 2026-11-18 – Phase 3 prototype (designer): test mount 100 stamina; starter mount should reach
  ≈ 864 studs (mid-Segment 2, ≈ 27 s); provisional drain ≈ 0.11574 stamina/stud, to be
  validated in Studio.
- 2026-11-18 – Code aligned with the Phase 3 decisions (no Phase 3 gameplay built): variant
  multipliers Gold 1.25× / Rainbow 1.75×; `MountConfig` speed/stamina growth (0.1% / 1% per
  level), provisional `StaminaPerStud = 100/864`, `TestMountStamina = 100`; `CourseConfig` course
  dimensions and 1–3 animals per segment; `SpeciesConfig` gains `BaseSpeed`; new `LevelScaling`
  and `Speed` rules; `Stamina.Max` uses the percentage formula; tests updated.
- 2026-11-18 – Phase 3 implementation choices (pending designer review and Studio tests):
  grey-box world is built by `WorldService` from `CourseConfig` at server start; an existing
  Workspace part named `StartingFloor` is reused as-is (else a 250 × 1 × 100 floor is created) and
  the course is laid out from it (floor LookVector = riding direction, front edge = starting
  line). `RunSessionService` owns run state (Ranch → StartingArea → Riding → Collapsed → Ranch);
  the client (`RideController`) only steers its own character. The server's speed cap is
  measured from run start (speed × elapsed × 1.25 + 6 studs), so bursty network updates are not
  flagged; riders further ahead than 20 studs or outside the corridor are moved back. Riders are
  in the `Riders` collision group, which does not collide with itself. Approved provisional
  values in `CourseConfig`: steer speed 16 studs/s, 3 s "Out of stamina" message.
- 2026-11-19 – Phase 3 accepted by the designer after Studio testing. Provisional drain of
  100/864 stamina per stud confirmed (collapses at ≈ 864 studs). Fixed during testing: the
  client no longer waits for Roblox's `PlayerModule` (absent in the test place). Added a
  Studio-only `speed` debug command for faster testing; the approved 32 studs/s is unchanged.
- 2026-11-19 – Blender → Roblox scale convention verified: 1 Blender unit = 1 stud with FBX
  export Apply Scalings = FBX Unit Scale, Scale 1.0, Z Forward / Y Up, and Studio Scale Unit =
  Stud. A 10 × 10 × 10 test cube imported as Size 10, 10, 10 (designer convention).
- 2026-11-19 – Phase 3 review fixes (ChatGPT on 9ae2c9d): run sessions now change state through
  `Shared/Rules/RunSessionState` (state, biome and run change together; every change bumps the
  Token), so a respawn or death returns to Ranch immediately and can never leave a session
  Riding without a run; the Heartbeat recovers any invalid session. Mobile steering tracks each
  touch separately (`Shared/Util/HoldTracker`) and releases on end/cancel anywhere, on sliding
  off the button, on run end and on focus loss. 18 regression tests (76 total); Studio checks
  for respawn mid-run, respawn during the collapse message, emulator and mouse steering passed.
  Speed validation finding acknowledged; proposal pending designer decision (unchanged).
- 2026-11-20 – Speed validation (review finding 3, designer approved): the accepted forward limit
  is now `speed × (elapsed + LeadAllowanceSeconds)` with `LeadAllowanceSeconds = 0.25`, replacing
  the earlier `speed × elapsed × 1.25 + 6 studs` (which let a constant 25% speed hack through and
  let riders save up headroom). Chosen after Studio measurement: 4 runs at 32 and 120 studs/s
  showed a largest lead of 0 over a perfect rider. Pull-back threshold (20 studs) unchanged; lead
  measurement and rejected-sample logging kept. Tests: legitimate and bursty riders pass;
  constant 10% / 25% hacks rejected within ~2.5 s / ~1 s; saved-up headroom cannot be used.
- 2026-11-20 – Review clarification (ChatGPT on f397764 / 8c914a4): the 20-stud pull-back
  threshold is intentional and unchanged. Documented the difference between accepted progress
  (`RunProgress.Progress`, server-owned, drives stamina and run end) and the physical character
  position (may be up to ~28 studs ahead at 32 studs/s before being moved back). Regression test
  added showing the physical tolerance earns no extra progress or stamina. Phases 4–5 must
  validate emergence, targeting, lasso and catching against accepted progress.

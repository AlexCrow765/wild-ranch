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

## Roadmap
0. Skeleton ✅ · 1. Data foundation · 2. Rules modules · 3. Grey-box course & riding ·
4. Run generation & encounters · 5. Targeting & lasso · 6. Taming QTE ·
7. Ranch, inventory, income · 8. Mounts · 9. Biome progression · 10. Journal ·
11. Failure/retry/monetization · 12. Leaderboards · 13. Polish · Later: quests, stealing

## Implementation decision log
- 2026-11-15 – Use Rojo with file-based source in `SRC/` (designer approved).

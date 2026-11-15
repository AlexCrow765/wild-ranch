# Wild Ranch — Claude Code Project Instructions

## 1. Project purpose

Wild Ranch is a Roblox animal-collecting, taming, and ranch-management game. Players ride through biome courses, encounter and tame animals, return them to their ranch, and earn passive income from animals placed there.

Work incrementally. Implement the current agreed phase, preserve existing behavior, and do not build future phases early unless explicitly requested.

## 2. Source of truth and decision authority

Read these project documents before making architectural or gameplay changes:

1. `Wild_Ranch_Complete_Design_Notes.docx` — game-design source of truth, including the designer's gameplay decisions.
2. `DOCUMENTATION/ARCHITECTURE.md` — technical architecture, implementation conventions, development roadmap (Section C), and decision log.
3. This `CLAUDE.md` — operating instructions for Claude Code.

The design notes are authoritative for gameplay. The architecture document is authoritative for the agreed technical structure and implementation checklist. This file governs your working process; it does not override either source on game design.

Rules:
- Treat explicit designer-approved decisions as fixed.
- Do not silently change, reinterpret, or "improve" an approved mechanic.
- Do not invent values for undecided mechanics, economy, progression, or configuration.
- If a required value or behavior is undecided, leave it clearly marked as an `OPEN QUESTION` and ask the designer before implementing dependent behavior.
- Distinguish confirmed decisions from recommendations and assumptions.
- When a decision is approved, update the appropriate documentation and decision log in the same task.
- If documents conflict, do not silently choose. Identify the conflict, explain its impact, and ask the designer. Preserve the existing implementation until a decision is made unless it is unsafe.
- Do not mark roadmap checkboxes complete merely because code was written or compiled. Complete them only after the stated acceptance tests pass.

## 3. Architecture and code organization

Follow `default.project.json` and the existing architecture. The intended Rojo mappings are:

- `SRC/Shared` → `ReplicatedStorage.Shared`
- `SRC/Server` → `ServerScriptService.Server`
- `SRC/Client` → `StarterPlayer.StarterPlayerScripts.Client`

Conventions:
- Keep source code in files and use Rojo to sync it to Studio.
- Keep maps, models, and other 3D content in Roblox Studio unless the project explicitly adopts a file-based asset workflow.
- Use one server Script and one client LocalScript as the entry points; other code should be ModuleScripts, following the existing loader pattern.
- Services and controllers should follow the existing `LoadOrder`, `Init`, and `Start` conventions.
- Put tunable gameplay values in `SRC/Shared/Config`. Avoid magic numbers in gameplay logic.
- Put deterministic, side-effect-free game rules in `SRC/Shared/Rules` so they can be tested independently.
- Keep remote definitions centralized in `SRC/Shared/Net/Remotes`.
- Keep shared data types in `SRC/Shared/Types`.
- Keep server authority in server services. The server owns saved data, rolls, taming outcomes, income, purchases, and unlocks.
- Validate every client-provided remote argument on the server. Never trust the client to award currency, create or modify owned animals, decide capture success, or grant progression.
- Do not expose another player's private profile data to a client.
- Preserve the single animal data model across encounter, capture, inventory, ranch, and mount systems. Do not store derived values that should be calculated from current configuration.
- Preserve seeded/reproducible run generation as specified in the architecture when implementing the run planner.
- Keep monetization isolated and deferred until Phase 11.

## 4. Data safety

Player data is critical. Treat persistence changes conservatively.

- Use the existing ProfileStore integration and session-locking approach. Do not replace the persistence library or change its version without approval.
- Preserve schema versioning and sequential migrations.
- Never overwrite a save from a newer schema version that this server does not understand.
- Never silently delete invalid or unrecognized animal records. Report validation problems and preserve data for diagnosis.
- Make migrations safe: validate inputs, work on a copy where appropriate, and avoid leaving a partially migrated profile.
- Do not weaken session locking, shutdown handling, or save error handling to make tests pass.
- Do not use live production data for destructive tests. Clearly explain any Studio API Services or publishing requirements before persistence tests.

## 5. Development workflow

For each assigned task:

1. **Orient:** Inspect the relevant source documents, current code, configuration, and Git status before editing.
2. **Plan:** State the scope, files likely to change, dependencies, and acceptance tests. Ask before proceeding if a design decision is missing or the task would expand scope materially.
3. **Implement:** Make the smallest coherent change that satisfies the approved requirements. Avoid unrelated refactors.
4. **Validate:** Run the available formatter, type/lint checks, tests, and `rojo build` as applicable. Do not claim a test passed unless you actually ran it.
5. **Inspect:** Review your own diff for accidental changes, security issues, data-loss risks, magic numbers, and documentation drift.
6. **Document:** Update architecture, decision log, and roadmap checkboxes only when justified by completed work and passing tests.
7. **Report:** Summarize files changed, behavior added, commands/tests actually run and their results, tests still requiring Roblox Studio, known limitations, and any open questions.
8. **Version control:** Make focused commits with descriptive messages when requested or when the task's agreed workflow calls for it. Never force-push, rewrite shared history, or discard user changes. Do not commit secrets, credentials, local environment files, generated caches, or unrelated files. Push only when the user has authorized pushing for that task.

Do not overwrite, reset, stash, or discard uncommitted user work without explicit permission. Before switching branches or pulling remote changes, check for a clean working tree and explain any conflict risk.

## 6. Phase and testing discipline

- Follow Section C of `DOCUMENTATION/ARCHITECTURE.md` in order.
- Build functional grey-box systems in their assigned phases. Visual polish, final models, animations, VFX, sound, and final UI styling belong in Phase 13 unless the designer explicitly changes the plan.
- Each phase must satisfy its own acceptance tests before being called complete.
- Separate automated/code-level validation from tests that require Roblox Studio, published experiences, API Services, multiple clients, or physical devices.
- Never claim Studio, multiplayer, mobile, gamepad, persistence, or purchase tests were run unless they were actually run.
- When a test cannot be run in the current environment, provide exact steps for the designer to run and mark it as pending.

## 7. Current project status

Use the latest Git history and Section C checklist as the status authority; do not assume this section remains current.

At the time these instructions were created:
- Phase 0 has been implemented and its Rojo build test was recorded as passing in the architecture document.
- Phase 1 code was committed as `7aab120`.
- Phase 1 still requires Roblox Studio verification, including persistence across rejoins and two-player profile separation/independent saving.
- Do not begin Phase 2 until the designer confirms Phase 1 acceptance tests pass, unless explicitly instructed otherwise.

## 8. Communication style

- Be precise, practical, and transparent.
- Explain technical risks in plain language.
- Ask one focused question at a time when clarification is necessary.
- Do not overwhelm the designer with unrelated options.
- Never represent an assumption as an approved design decision.
- At the end of each task, give a concise implementation and test report, and identify the next required action.

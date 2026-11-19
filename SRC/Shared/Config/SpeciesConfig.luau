--!strict
--[[
	SpeciesConfig
	Every animal species, keyed by species id.

	Design rules (LOCKED, section 2.D): each biome has a limited species pool and a
	species is exclusive to the biome it is introduced in.

	OPEN QUESTIONS: the real species list per biome, base speed, base stamina, base income,
	spawn weights by distance, and movement/aggression behaviour.

	DebugOnly species exist only so systems can be tested before the real roster is
	decided. They must never appear in spawning, the journal, or leaderboards.
]]

export type Species = {
	Id: string,
	DisplayName: string,
	Biome: string, -- biome id from BiomeConfig
	DebugOnly: boolean?,
	BaseSpeed: number?, -- studs/s; OPEN QUESTION: per-species value not decided
	BaseStamina: number?, -- OPEN QUESTION: per-species value not decided
	BaseIncome: number?, -- OPEN QUESTION: per-species value not decided
	-- OPEN: spawn weights by distance, behaviour
}

local SpeciesConfig = {}

SpeciesConfig.Species = table.freeze({
	TestCritter = table.freeze({
		Id = "TestCritter",
		DisplayName = "Test Critter",
		Biome = "Plains",
		DebugOnly = true,
	}) :: Species,
}) :: { [string]: Species }

return table.freeze(SpeciesConfig)

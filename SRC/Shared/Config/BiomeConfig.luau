--!strict
--[[
	BiomeConfig
	Biome list and order along the course.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.B (LOCKED):
	Level 1 = Plains, Level 2 = Savannah. Later biomes are undecided.
	Add a biome by appending to Order and adding an entry to Biomes.
]]

export type Biome = {
	Id: string,
	DisplayName: string,
	Level: number,
	IncomeMultiplier: number?, -- OPEN QUESTION: per-biome value not decided
	-- OPEN: lasso requirement, unlock requirement, species pool.
}

local BiomeConfig = {}

BiomeConfig.Order = table.freeze({ "Plains", "Savannah" })

BiomeConfig.Biomes = table.freeze({
	Plains = table.freeze({ Id = "Plains", DisplayName = "Plains", Level = 1 }) :: Biome,
	Savannah = table.freeze({ Id = "Savannah", DisplayName = "Savannah", Level = 2 }) :: Biome,
})

return table.freeze(BiomeConfig)

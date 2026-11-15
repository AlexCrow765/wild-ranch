--!strict
--[[
	EconomyConfig
	Passive income and ranch economy.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.H (LOCKED).
	Income per second = species base income
	                    x variant stat multiplier (RarityConfig)
	                    x star income multiplier (below)
	                    x biome income multiplier (permanent, from the biome it was caught in)
	Only animals physically placed in the ranch earn. Inventory animals do not.
]]

local EconomyConfig = {}

-- Income multiplier keyed by star rating.
EconomyConfig.StarIncomeMultiplier = table.freeze({
	[0] = 1.00,
	[1] = 1.25,
	[2] = 1.50,
	[3] = 1.75,
	[4] = 2.00,
	[5] = 2.50,
})

-- OPEN QUESTIONS (needed by Phase 7):
-- starting inventory capacity, ranch capacity upgrades and prices,
-- physical pen-size milestones (5, 10, 20 were examples), offline income.

return table.freeze(EconomyConfig)

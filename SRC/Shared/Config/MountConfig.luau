--!strict
--[[
	MountConfig
	Mount leveling and stamina.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.F (LOCKED).
	- Leveling is bought with coins (no XP).
	- Each level adds a FIXED amount of stamina; it does not change income or stars.
	- Stamina drains by distance traveled, not time. Speed is not a mount stat.
]]

local MountConfig = {}

-- Level a newly captured animal starts at (designer approved 2026-11-15).
MountConfig.StartingLevel = 1

-- Maximum mount level, keyed by star rating.
MountConfig.MaxLevelByStars = table.freeze({
	[0] = 5,
	[1] = 10,
	[2] = 20,
	[3] = 30,
	[4] = 40,
	[5] = 50,
})

-- OPEN QUESTIONS (needed by Phase 3/8):
-- MountConfig.StaminaPerLevel        fixed stamina added per level
-- MountConfig.StaminaPerStud         stamina consumed per stud traveled
-- MountConfig.LevelCost              coin price per level

return table.freeze(MountConfig)

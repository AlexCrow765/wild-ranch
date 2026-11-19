--!strict
--[[
	MountConfig
	Mount leveling, speed and stamina.

	Sources: design notes section 2.F, as superseded by designer decisions of 2026-11-18
	(see "Designer decisions that supersede the design notes" in ARCHITECTURE.md):
	- Leveling is bought with coins (no XP).
	- Each species has its own base speed and base stamina (SpeciesConfig).
	- Each level gained adds a percentage of the (variant-adjusted) base stat, never compounded:
	    Speed   = Base Speed   x Variant x (1 + SpeedGrowthPerLevel   x (Level - 1))
	    Stamina = Base Stamina x Variant x (1 + StaminaGrowthPerLevel x (Level - 1))
	- Stars only set the maximum level (and income); they do not change speed or stamina.
	- Stamina drains by distance traveled, not time.
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

-- Fraction of base stat gained per level above StartingLevel (same for every species).
MountConfig.SpeedGrowthPerLevel = 0.001 -- +0.1% of base speed per level
MountConfig.StaminaGrowthPerLevel = 0.01 -- +1% of base stamina per level

-- Stamina consumed per stud traveled.
-- PROVISIONAL prototype value (designer, 2026-11-18): 100 stamina / 864 studs, so a 100-stamina
-- mount reaches about halfway through Segment 2. Must be validated in Studio; not final balance.
MountConfig.StaminaPerStud = 100 / 864

-- Temporary Phase 3 test mount (removed when Phase 8 mount selection lands).
-- It rides at CourseConfig.BaselineRidingSpeed.
MountConfig.TestMountStamina = 100

-- OPEN QUESTIONS (needed by Phase 8):
-- MountConfig.LevelCost              coin price per level
-- which animal the starter mount is (its reach target is ~864 studs)

return table.freeze(MountConfig)

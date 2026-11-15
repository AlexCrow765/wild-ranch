--!strict
--[[
	TamingConfig
	Directional quick-time-event taming minigame.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.G (LOCKED).
	Do not change these values without the designer's approval.
]]

local TamingConfig = {}

-- Meter values are percentage points (0-100).
TamingConfig.StartPercent = 50
TamingConfig.SuccessPercent = 100 -- reaching this tames the animal
TamingConfig.FailPercent = 0 -- reaching this throws the player off and ends the run

-- The meter does not drain during this window at the start of the minigame.
TamingConfig.GracePeriodSeconds = 1.5

TamingConfig.CorrectInputGain = 25
TamingConfig.IncorrectInputPenalty = 15 -- regardless of rarity

-- Only one incorrect input counts per prompt; it resets when the next prompt appears.
TamingConfig.MaxCountedMistakesPerPrompt = 1

-- Prompts are completely random, one at a time. No universal action button.
TamingConfig.Directions = table.freeze({ "Up", "Down", "Left", "Right" })

-- Continuous drain after the grace period, in percentage points per second.
-- Total drain = star drain + variant extra drain (they stack).
TamingConfig.StarDrainPerSecond = table.freeze({
	[0] = 3,
	[1] = 3,
	[2] = 3,
	[3] = 5,
	[4] = 5,
	[5] = 5,
})

TamingConfig.VariantExtraDrainPerSecond = table.freeze({
	Normal = 0,
	Gold = 10,
	Rainbow = 10,
})

return table.freeze(TamingConfig)

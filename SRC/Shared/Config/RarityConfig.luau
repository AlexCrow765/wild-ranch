--!strict
--[[
	RarityConfig
	Star-rating and visual-variant numbers.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.D (LOCKED).
	Do not change these values without the designer's approval.
]]

local RarityConfig = {}

RarityConfig.MinStars = 0
RarityConfig.MaxStars = 5

-- Baseline star odds in percent, keyed by star rating (0-5). Sums to 100.
RarityConfig.StarBaseOdds = table.freeze({
	[0] = 50,
	[1] = 25,
	[2] = 14,
	[3] = 8,
	[4] = 2.5,
	[5] = 0.5,
})

-- Star-odds multiplier for each zone of a biome. Resets to the baseline at the
-- next biome's starting area. The adjusted distribution is normalized to 100%.
RarityConfig.StartingAreaStarMultiplier = 1
RarityConfig.SegmentStarMultipliers = table.freeze({ 1, 1.25, 1.5, 1.75, 2 })
RarityConfig.MaxStarMultiplier = 2

-- OPEN QUESTION (needed by Phase 4): which star tiers count as "higher stars"
-- and receive the segment multiplier before normalization (1-5 stars, or 2-5 stars?).

-- Visual variants. Rolled independently of star rating and do NOT receive the
-- segment star multiplier. Odds in percent; sums to 100.
RarityConfig.VariantOrder = table.freeze({ "Normal", "Gold", "Rainbow" })
RarityConfig.VariantOdds = table.freeze({
	Normal = 97,
	Gold = 2.5,
	Rainbow = 0.5,
})

-- Multiplier applied to a species' base stats (base income and base stamina).
-- OPEN QUESTION: Rainbow is 3x or 4x (designer has not chosen). Left unset on purpose;
-- code that needs it must fail loudly rather than guess.
RarityConfig.VariantStatMultiplier = table.freeze({
	Normal = 1,
	Gold = 2,
	-- Rainbow = ?,
})

return table.freeze(RarityConfig)

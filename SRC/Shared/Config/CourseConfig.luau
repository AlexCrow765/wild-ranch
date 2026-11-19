--!strict
--[[
	CourseConfig
	Biome course dimensions and encounter layout.

	Sources: design notes section 2.C, as superseded by designer decisions of 2026-11-18
	(see ARCHITECTURE.md "Biome course dimensions", "Corridor and bushes", "Encounter generation"):
	- 5 segments per biome after the starting area; ~18 s per segment, ~90 s per biome.
	- 1-3 animals per segment in randomly selected predefined encounter slots (no herds).
	- Each animal independently emerges from the left or right bushes.
	- Everything is rolled when the player crosses the starting line.
	- Travel time is separate from stamina: the 18 s sets segment length, not a drain rate.
]]

local CourseConfig = {}

-- Course length
CourseConfig.SegmentsPerBiome = 5
CourseConfig.BaselineRidingSpeed = 32 -- studs per second
CourseConfig.SegmentTargetSeconds = 18
CourseConfig.SegmentLengthStuds = 576 -- 32 studs/s x 18 s
CourseConfig.BiomeLengthStuds = 2880 -- 5 x 576

-- Corridor (playable centre >= 100 - 2 x 13 = 74 studs; invisible boundaries keep riders out of bushes)
CourseConfig.CorridorWidthStuds = 100
CourseConfig.MaxBushWidthStuds = 13 -- per side

-- Encounters
CourseConfig.MinAnimalsPerSegment = 1
CourseConfig.MaxAnimalsPerSegment = 3
CourseConfig.LeftSideChance = 0.5 -- independent per animal (design notes 2.C)

-- OPEN QUESTIONS (needed by Phase 3/4):
-- encounter slot count and layout per segment, minimum separation between selected slots,
-- chance of 1/2/3 animals, bush emergence trigger distance, exact bush/boundary geometry.

return table.freeze(CourseConfig)

--!strict
--[[
	CourseConfig
	Course segments and animal spawn layout.

	Source: Wild_Ranch_Complete_Design_Notes.docx, section 2.C (LOCKED).
	- Each reachable segment rolls 3-5 animals. No herds.
	- One invisible spawning line per animal; the segment is split as evenly as possible.
	- Each animal's spawn point is random along its own line.
	- Each animal independently rolls left/right side (50/50).
	- Everything is rolled when the player crosses the starting line.
]]

local CourseConfig = {}

CourseConfig.MinAnimalsPerSegment = 3
CourseConfig.MaxAnimalsPerSegment = 5

CourseConfig.LeftSideChance = 0.5

-- OPEN QUESTIONS (needed by Phase 3):
-- segments per biome (the multiplier chart implies 5), segment length,
-- corridor width, wall dimensions, bush emergence trigger distance.

return table.freeze(CourseConfig)

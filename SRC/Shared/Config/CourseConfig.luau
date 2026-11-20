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

-- Riding controls (designer approved 2026-11-18)
-- PC: A/D and Left/Right arrows. Gamepad: left stick and D-pad left/right. Mobile: two on-screen buttons.
CourseConfig.SteerSpeed = 16 -- studs/s sideways. PROVISIONAL: tune in Studio.
CourseConfig.SteerStickDeadzone = 0.2 -- gamepad stick deadzone (implementation detail)

-- Run end (designer approved 2026-11-18). Replaced by the Phase 11 result screen.
CourseConfig.CollapseMessage = "Out of stamina"
CourseConfig.CollapseMessageSeconds = 3 -- PROVISIONAL

-- Starting area floor (designer approved 2026-11-18): 250 wide x 1 tall x 100 deep.
-- If Workspace already contains a BasePart with this name, it is reused as-is and the course
-- is built from its position; otherwise the server creates one at DefaultStartingFloorCFrame.
-- The floor's LookVector is the riding direction; its front edge is the starting line.
CourseConfig.StartingFloorName = "StartingFloor"
CourseConfig.StartingFloorSize = Vector3.new(250, 1, 100)
CourseConfig.DefaultStartingFloorCFrame = CFrame.new(0, 0.5, 0)

-- Grey-box build details (implementation only, not gameplay; replaced by art in Phase 13)
CourseConfig.GreyBox = table.freeze({
	OuterWallHeight = 12, -- visible boundary walls at the corridor edges
	InvisibleWallHeight = 30, -- keeps riders out of the bushes / off the floor edges
	BushHeight = 6,
	HubSize = Vector3.new(120, 1, 120), -- placeholder ranch hub (until Phase 7)
	HubDistanceBehindFloor = 150, -- studs behind the starting floor's back edge
})

-- Server-side movement validation (implementation tolerances, not gameplay)
-- Accepted forward distance <= speed x (elapsed + LeadAllowanceSeconds). Designer approved
-- 2026-11-20 after Studio measurement showed a legitimate rider's lead over speed x elapsed
-- is 0 (positions reach the server late, never early).
CourseConfig.Validation = table.freeze({
	LeadAllowanceSeconds = 0.25, -- of travel at the mount's speed (8 studs at 32 studs/s)
	PullBackStuds = 20, -- if a rider is this far beyond the accepted position, move them back
	LateralToleranceStuds = 4, -- allowed beyond the playable half-width before correction
})

-- OPEN QUESTIONS (needed by Phase 3/4):
-- encounter slot count and layout per segment, minimum separation between selected slots,
-- chance of 1/2/3 animals, bush emergence trigger distance, exact bush/boundary geometry.

return table.freeze(CourseConfig)

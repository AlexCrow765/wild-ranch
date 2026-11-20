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
MountConfig.TestMountName = "Test Mount" -- placeholder shown in the riding HUD (designer approved)
-- Visual only: how far below the rider's root centre the test mount block's top sits. Tune in
-- Studio so the seated rider rests on the saddle: smaller = rider sits lower on the mount (the
-- mount stays on the ground because the rider lift uses the same value). Phase 3 used 1; 2 left
-- the designer's test avatar floating ~0.5 studs above the horse's saddle, so 1.5 is the current
-- tuned value.
MountConfig.TestMountSeatDrop = 1.5

-- Test mount model (designer request 2026-11-20): a low-poly horse made in Blender
-- (ASSETS/Mounts/TestHorse.blend / .fbx), imported in Studio and saved as
-- ServerStorage.<TestMountFolder>.<TestMountModel>. It needs an Attachment named <SeatAttachment>
-- at the saddle, its front (LookVector) pointing toward the horse's head. If the model or the
-- attachment is missing, the grey-box block is used instead.
MountConfig.TestMountFolder = "Mounts"
MountConfig.TestMountModel = "TestHorse"
MountConfig.SeatAttachment = "Seat"
MountConfig.MountInstanceName = "TestMount" -- name of the mount inside the rider's character

-- Riding pose (designer approved 2026-11-20).
-- OPEN: set this to the asset id of the published "Ride" animation (a number, e.g. 1234567890)
-- once it exists. While nil, the rider uses Roblox's built-in sit animation from the character's
-- default Animate script as a temporary pose. No other code changes are needed to switch.
MountConfig.RideAnimationId = nil :: number?

-- OPEN QUESTIONS (needed by Phase 8):
-- MountConfig.LevelCost              coin price per level
-- which animal the starter mount is (its reach target is ~864 studs)

return table.freeze(MountConfig)

--!strict
--[[
	WorldService
	Builds the Phase 3 grey-box world from CourseConfig and owns collision groups.

	- Starting floor: reuses Workspace.<StartingFloorName> if it exists (never moved or resized);
	  otherwise creates a 250 x 1 x 100 floor. The course is built from the floor's position:
	  its LookVector is the riding direction and its front edge is the starting line.
	- Plains course: 5 x 576-stud segments in a 100-stud corridor; bush strips (13 studs) on both
	  sides behind invisible boundaries; visible outer walls; an end wall at 2,880 studs.
	- Placeholder ranch hub with the spawn point, behind the starting floor (until Phase 7).
	- "Riders" collision group: riders never collide with each other.

	Grey-box parts are plain and replaced by art in Phase 13. Parts carry a "WildRanchRole"
	attribute so later systems (e.g. Phase 4 bushes) can find them without relying on names.
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared:WaitForChild("Config"):WaitForChild("CourseConfig"))
local CourseLayout = require(Shared:WaitForChild("Rules"):WaitForChild("CourseLayout"))

local PlayerService = require(script.Parent:WaitForChild("PlayerService"))

local WorldService = {
	LoadOrder = 5,
	RIDER_GROUP = "Riders",
}

-- Biomes that have a built course in this phase. Savannah arrives with Phase 9.
local BUILT_BIOMES = { "Plains" }

type Course = { Origin: CFrame, Floor: BasePart }

local courses: { [string]: Course } = {}
local hubSpawn: SpawnLocation

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, props: { [string]: any }?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	if props then
		for key, value in props do
			(part :: any)[key] = value
		end
	end
	part.Parent = parent
	return part
end

local function invisibleWall(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	return makePart(parent, name, size, cframe, {
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
end

local function getOrCreateFloor(parent: Instance): BasePart
	local existing = Workspace:FindFirstChild(CourseConfig.StartingFloorName, true)
	if existing and existing:IsA("BasePart") then
		local size = existing.Size
		local expected = CourseConfig.StartingFloorSize
		if (size - expected).Magnitude > 0.01 then
			warn(`[WorldService] {existing:GetFullName()} is {size}, expected {expected}; using it as-is`)
		end
		if not existing.Anchored then
			warn(`[WorldService] {existing:GetFullName()} is not anchored`)
		end
		print(`[WorldService] Using existing starting floor {existing:GetFullName()}`)
		return existing
	end
	print("[WorldService] No existing starting floor found; creating one")
	return makePart(parent, CourseConfig.StartingFloorName, CourseConfig.StartingFloorSize, CourseConfig.DefaultStartingFloorCFrame, {
		Color = Color3.fromRGB(120, 170, 90),
	})
end

local function buildCourse(biomeId: string, root: Instance): Course
	local folder = Instance.new("Folder")
	folder.Name = biomeId
	folder.Parent = root

	local floor = getOrCreateFloor(folder)
	local floorSize = floor.Size
	local origin = CourseLayout.OriginFromFloor(floor.CFrame, floorSize)
	local greyBox = CourseConfig.GreyBox

	local length = CourseConfig.BiomeLengthStuds
	local segmentLength = CourseConfig.SegmentLengthStuds
	local corridorWidth = CourseConfig.CorridorWidthStuds
	local corridorHalf = CourseLayout.CorridorHalfWidth()
	local playHalf = CourseLayout.PlayableHalfWidth()
	local bushWidth = CourseConfig.MaxBushWidthStuds

	-- Course-space helper: forward distance d, lateral x, height y -> CFrame facing forward.
	local function at(d: number, x: number, y: number): CFrame
		return origin * CFrame.new(x, y, -d)
	end

	-- Ground, one part per segment (alternating colours so segments are easy to see)
	for segment = 1, CourseConfig.SegmentsPerBiome do
		local startD = CourseLayout.SegmentStart(segment)
		local ground = makePart(folder, `Segment{segment}`, Vector3.new(corridorWidth, 1, segmentLength), at(startD + segmentLength / 2, 0, -0.5), {
			Color = if segment % 2 == 1 then Color3.fromRGB(150, 190, 110) else Color3.fromRGB(135, 175, 95),
		})
		ground:SetAttribute("WildRanchRole", "SegmentGround")
		ground:SetAttribute("Segment", segment)
		if segment > 1 then
			makePart(folder, `Segment{segment}Marker`, Vector3.new(playHalf * 2, 0.2, 1), at(startD, 0, 0.1), {
				Color = Color3.fromRGB(240, 240, 240),
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
			})
		end
	end

	-- Starting line
	local line = makePart(folder, "StartingLine", Vector3.new(playHalf * 2, 0.2, 2), at(1, 0, 0.1), {
		Color = Color3.fromRGB(220, 60, 60),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	line:SetAttribute("WildRanchRole", "StartingLine")

	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"

		-- Bush strips (no collision: animals will emerge from them in Phase 4)
		local bush = makePart(folder, `Bushes{sideName}`, Vector3.new(bushWidth, greyBox.BushHeight, length), at(length / 2, side * (corridorHalf - bushWidth / 2), greyBox.BushHeight / 2), {
			Color = Color3.fromRGB(60, 120, 50),
			CanCollide = false,
			CanTouch = false,
		})
		bush:SetAttribute("WildRanchRole", "Bushes")
		bush:SetAttribute("Side", sideName)

		-- Invisible boundary keeping riders out of the bushes
		invisibleWall(folder, `BushBoundary{sideName}`, Vector3.new(1, greyBox.InvisibleWallHeight, length), at(length / 2, side * (playHalf + 0.5), greyBox.InvisibleWallHeight / 2))

		-- Visible outer boundary wall
		makePart(folder, `OuterWall{sideName}`, Vector3.new(1, greyBox.OuterWallHeight, length), at(length / 2, side * (corridorHalf + 0.5), greyBox.OuterWallHeight / 2), {
			Color = Color3.fromRGB(110, 95, 80),
		})

		-- Starting area: front walls either side of the playable opening, and side walls
		local floorHalfWidth = floorSize.X / 2
		local frontWidth = floorHalfWidth - playHalf
		invisibleWall(folder, `FloorFrontWall{sideName}`, Vector3.new(frontWidth, greyBox.InvisibleWallHeight, 1), at(-0.5, side * (playHalf + frontWidth / 2), greyBox.InvisibleWallHeight / 2))
		invisibleWall(folder, `FloorSideWall{sideName}`, Vector3.new(1, greyBox.InvisibleWallHeight, floorSize.Z), at(-floorSize.Z / 2, side * (floorHalfWidth + 0.5), greyBox.InvisibleWallHeight / 2))
	end

	invisibleWall(folder, "FloorBackWall", Vector3.new(floorSize.X, greyBox.InvisibleWallHeight, 1), at(-(floorSize.Z + 0.5), 0, greyBox.InvisibleWallHeight / 2))

	-- End of the biome (the next biome's starting area arrives in Phase 9)
	makePart(folder, "EndWall", Vector3.new(corridorWidth, greyBox.OuterWallHeight, 1), at(length + 0.5, 0, greyBox.OuterWallHeight / 2), {
		Color = Color3.fromRGB(110, 95, 80),
	})

	return { Origin = origin, Floor = floor }
end

local function buildHub(root: Instance, floor: BasePart)
	local greyBox = CourseConfig.GreyBox
	local floorSize = floor.Size
	local hubCFrame = floor.CFrame * CFrame.new(0, 0, floorSize.Z / 2 + greyBox.HubDistanceBehindFloor + greyBox.HubSize.Z / 2)

	local folder = Instance.new("Folder")
	folder.Name = "RanchHub"
	folder.Parent = root

	-- Top of the hub is level with the top of the starting floor.
	local topY = floorSize.Y / 2
	makePart(folder, "HubFloor", greyBox.HubSize, hubCFrame * CFrame.new(0, topY - greyBox.HubSize.Y / 2, 0), {
		Color = Color3.fromRGB(170, 140, 100),
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "RanchSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = hubCFrame * CFrame.new(0, topY + 0.5, 0)
	spawn.Color = Color3.fromRGB(200, 170, 120)
	spawn.Parent = folder
	hubSpawn = spawn
end

local function setupCollisionGroups()
	if not PhysicsService:IsCollisionGroupRegistered(WorldService.RIDER_GROUP) then
		PhysicsService:RegisterCollisionGroup(WorldService.RIDER_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(WorldService.RIDER_GROUP, WorldService.RIDER_GROUP, false)
end

local function assignRiderGroup(character: Model)
	local function apply(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = WorldService.RIDER_GROUP
		end
	end
	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	character.DescendantAdded:Connect(apply)
end

-- Course origin (centre of the starting line on the floor top, LookVector = forward).
function WorldService.GetCourseOrigin(biomeId: string): CFrame?
	local course = courses[biomeId]
	return if course then course.Origin else nil
end

function WorldService.HasCourse(biomeId: string): boolean
	return courses[biomeId] ~= nil
end

-- Where a player arrives in a biome's starting area: centre of the floor, facing forward.
function WorldService.GetStartingAreaSpawn(biomeId: string): CFrame?
	local course = courses[biomeId]
	if course == nil then
		return nil
	end
	return course.Floor.CFrame * CFrame.new(0, course.Floor.Size.Y / 2 + 3, 0)
end

function WorldService.GetHubSpawn(): CFrame
	return hubSpawn.CFrame * CFrame.new(0, 3.5, 0)
end

function WorldService:Init()
	setupCollisionGroups()

	local root = Workspace:FindFirstChild("WildRanchWorld")
	if root then
		root:Destroy() -- rebuilt from config every server start
	end
	root = Instance.new("Folder")
	root.Name = "WildRanchWorld"
	root.Parent = Workspace

	for _, biomeId in BUILT_BIOMES do
		courses[biomeId] = buildCourse(biomeId, root :: Instance)
	end
	buildHub(root :: Instance, courses.Plains.Floor)
end

function WorldService:Start()
	PlayerService.OnPlayerAdded(function(player: Player)
		player.RespawnLocation = hubSpawn
		player.CharacterAdded:Connect(assignRiderGroup)
		if player.Character then
			assignRiderGroup(player.Character)
		end
	end)
end

return WorldService

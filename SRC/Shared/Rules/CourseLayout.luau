--!strict
--[[
	CourseLayout
	Pure course geometry in "course space":
	  distance  = studs forward from the starting line (negative = in the starting area)
	  lateral   = studs right of the corridor centre line (negative = left)

	The course origin is a CFrame at the centre of the starting line, on the floor's top
	surface, with LookVector = riding direction. All biomes share these dimensions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared:WaitForChild("Config"):WaitForChild("CourseConfig"))

local CourseLayout = {}

-- Half of the playable centre width (between the invisible bush boundaries): 37 studs.
function CourseLayout.PlayableHalfWidth(): number
	return (CourseConfig.CorridorWidthStuds - 2 * CourseConfig.MaxBushWidthStuds) / 2
end

function CourseLayout.CorridorHalfWidth(): number
	return CourseConfig.CorridorWidthStuds / 2
end

-- Start distance of segment n (1-based).
function CourseLayout.SegmentStart(segment: number): number
	assert(segment >= 1 and segment <= CourseConfig.SegmentsPerBiome and segment % 1 == 0, `invalid segment {segment}`)
	return (segment - 1) * CourseConfig.SegmentLengthStuds
end

function CourseLayout.SegmentEnd(segment: number): number
	return CourseLayout.SegmentStart(segment) + CourseConfig.SegmentLengthStuds
end

-- 0 = starting area (before the line); 1..5 = segment; the very end counts as the last segment.
function CourseLayout.SegmentAt(distance: number): number
	if distance < 0 then
		return 0
	end
	local segment = math.floor(distance / CourseConfig.SegmentLengthStuds) + 1
	return math.min(segment, CourseConfig.SegmentsPerBiome)
end

function CourseLayout.IsPastEnd(distance: number): boolean
	return distance >= CourseConfig.BiomeLengthStuds
end

-- World position -> (distance, lateral) relative to a course origin.
function CourseLayout.ToCourseSpace(origin: CFrame, worldPosition: Vector3): (number, number)
	local offset = worldPosition - origin.Position
	return offset:Dot(origin.LookVector), offset:Dot(origin.RightVector)
end

-- (distance, lateral, height) -> world position.
function CourseLayout.ToWorld(origin: CFrame, distance: number, lateral: number, height: number): Vector3
	return origin.Position + origin.LookVector * distance + origin.RightVector * lateral + origin.UpVector * height
end

-- Course origin (centre of the starting line, floor top) from the starting floor part.
function CourseLayout.OriginFromFloor(floorCFrame: CFrame, floorSize: Vector3): CFrame
	return floorCFrame * CFrame.new(0, floorSize.Y / 2, -floorSize.Z / 2)
end

return CourseLayout

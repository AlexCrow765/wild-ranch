--!strict
--[[
	HubLayout
	Pure, deterministic Ranch Hub geometry (Stage 1). No Instances are created here.

	Two layers:
	  Compute2D(floorSize)          everything in the flat hub frame (see HubConfig for the frame)
	  Compute(floorCFrame, floorSize) the same layout placed in the world, anchored to the existing
	                                  Plains starting floor exactly like the course is
	                                  (CourseLayout.OriginFromFloor), so the floor, starting line and
	                                  course never move.

	Placement: the hub centre sits behind the floor's back edge by RunwayLength + PlazaRadius,
	on the course centre line, level with the floor top. The runway runs from the plaza edge to the
	centre of the floor's back edge.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HubConfig = require(Shared:WaitForChild("Config"):WaitForChild("HubConfig"))
local Geometry2D = require(Shared:WaitForChild("Util"):WaitForChild("Geometry2D"))
local CourseLayout = require(script.Parent:WaitForChild("CourseLayout"))

export type Rect = {
	Centre: Vector2,
	Axis: Vector2, -- unit direction of Length
	Length: number,
	Width: number,
	Polygon: Geometry2D.Polygon,
}

export type Plot = {
	Index: number,
	AngleDegrees: number,
	Colour: Color3,
	Radial: Vector2, -- unit, hub centre -> plot
	Lateral: Vector2, -- unit, the plot's right when looking from the plaza
	Area: Rect, -- the fixed dirt plot (Length = depth along Radial)
	FrontCentre: Vector2, -- middle of the plaza-facing edge (the entrance)
	HomePoint: Vector2, -- where every return lands; faces the plaza
	Sign: Vector2,
	PadCentre: Vector2,
	PadRadius: number,
	InitialPen: Rect,
	MaxPen: Rect,
}

export type Layout2D = {
	Plots: { Plot },
	PlazaRadius: number,
	GrassRadius: number,
	Runway: Rect,
	Floor: Rect, -- the existing starting floor's footprint in the hub frame
	FloorBackX: number,
	FloorFrontX: number, -- the starting line
	PermanentMerchant: Rect,
	TravelingMerchant: Rect,
	Paths: { Rect }, -- nominal walking lines: [1] to the runway mouth, [2..6] to each plot entrance
}

export type WorldPlot = {
	Index: number,
	CFrame: CFrame, -- plot centre on the ground, LookVector toward the plaza
	Entrance: CFrame,
	Home: CFrame,
	Sign: CFrame,
	Pad: CFrame,
}

export type WorldLayout = {
	Centre: CFrame, -- hub centre on the ground; LookVector = toward the floor (course forward)
	Layout: Layout2D,
	Plots: { WorldPlot },
	Runway: CFrame, -- runway centre; LookVector toward the floor
	PermanentMerchant: CFrame,
	TravelingMerchant: CFrame,
}

local HubLayout = {}

local function direction(angleDegrees: number): Vector2
	local a = math.rad(angleDegrees)
	return Vector2.new(math.cos(a), math.sin(a))
end

local function rect(centre: Vector2, axis: Vector2, length: number, width: number): Rect
	return {
		Centre = centre,
		Axis = axis.Unit,
		Length = length,
		Width = width,
		Polygon = Geometry2D.Rect(centre, axis, length, width),
	}
end

local function merchantRect(spot: { Radius: number, AngleDegrees: number, Length: number, Width: number }): Rect
	local radial = direction(spot.AngleDegrees)
	return rect(radial * spot.Radius, radial, spot.Length, spot.Width)
end

-- Largest pen that fits a plot: full width minus side margins; depth minus back margin and front strip.
function HubLayout.MaxPenSize(): (number, number)
	local pen = HubConfig.Pen
	return HubConfig.PlotWidth - 2 * pen.SideMargin, HubConfig.PlotDepth - pen.BackMargin - pen.FrontStrip
end

-- Pen rectangle for a plot, anchored BackMargin from the plot's back edge and centred sideways (O5).
-- Phase 7 upgrades only change width/depth. Errors if the pen would not fit.
function HubLayout.PenRect(plot: Plot, width: number, depth: number): Rect
	local maxWidth, maxDepth = HubLayout.MaxPenSize()
	assert(width > 0 and depth > 0, "pen size must be positive")
	assert(width <= maxWidth + 1e-9, `pen width {width} exceeds the maximum {maxWidth}`)
	assert(depth <= maxDepth + 1e-9, `pen depth {depth} exceeds the maximum {maxDepth}`)
	local backDistance = HubConfig.PlotCentreRadius + HubConfig.PlotDepth / 2 - HubConfig.Pen.BackMargin
	return rect(plot.Radial * (backDistance - depth / 2), plot.Radial, depth, width)
end

-- The whole layout in the hub frame. floorSize is the existing starting floor's size
-- (only its depth Z and width X are used, for the floor footprint).
function HubLayout.Compute2D(floorSize: Vector3): Layout2D
	local plazaRadius = HubConfig.PlazaRadius
	local runwayLength = HubConfig.RunwayLength
	local frontDistance = HubConfig.PlotCentreRadius - HubConfig.PlotDepth / 2
	local points = HubConfig.PlotPoints

	local plots: { Plot } = {}
	for index = 1, HubConfig.PlotCount do
		local angle = HubConfig.FirstPlotAngleDegrees + (index - 1) * HubConfig.PlotAngleStepDegrees
		local radial = direction(angle)
		local lateral = Vector2.new(-radial.Y, radial.X)
		local plot: Plot = {
			Index = index,
			AngleDegrees = angle,
			Colour = HubConfig.PlotColors[index],
			Radial = radial,
			Lateral = lateral,
			Area = rect(radial * HubConfig.PlotCentreRadius, radial, HubConfig.PlotDepth, HubConfig.PlotWidth),
			FrontCentre = radial * frontDistance,
			HomePoint = radial * (frontDistance + points.HomePointInset),
			Sign = radial * (frontDistance - points.SignOutset) + lateral * points.SignLateral,
			PadCentre = radial * (frontDistance - points.PadOutset) + lateral * points.PadLateral,
			PadRadius = points.PadRadius,
			InitialPen = nil :: any,
			MaxPen = nil :: any,
		}
		plot.InitialPen = HubLayout.PenRect(plot, HubConfig.Pen.InitialWidth, HubConfig.Pen.InitialDepth)
		plot.MaxPen = HubLayout.PenRect(plot, HubLayout.MaxPenSize())
		plots[index] = plot
	end

	local forward = Vector2.new(1, 0)
	local floorBackX = plazaRadius + runwayLength
	local paths: { Rect } = {
		rect(forward * (plazaRadius / 2), forward, plazaRadius, HubConfig.RunwayWidth),
	}
	for _, plot in plots do
		table.insert(paths, rect(plot.Radial * (frontDistance / 2), plot.Radial, frontDistance, HubConfig.Validation.EntrancePathWidth))
	end

	return {
		Plots = plots,
		PlazaRadius = plazaRadius,
		GrassRadius = HubConfig.GrassRadius,
		Runway = rect(forward * (plazaRadius + runwayLength / 2), forward, runwayLength, HubConfig.RunwayWidth),
		Floor = rect(forward * (floorBackX + floorSize.Z / 2), forward, floorSize.Z, floorSize.X),
		FloorBackX = floorBackX,
		FloorFrontX = floorBackX + floorSize.Z,
		PermanentMerchant = merchantRect(HubConfig.PermanentMerchant),
		TravelingMerchant = merchantRect(HubConfig.TravelingMerchant),
		Paths = paths,
	}
end

-- Clearance measurements (studs) used by tests and for reporting. Smaller = tighter.
function HubLayout.Measure(layout: Layout2D): { [string]: number }
	local origin = Vector2.zero
	local m: { [string]: number } = {
		MinPlotGap = math.huge,
		PlotToPlaza = math.huge,
		PlotToRunway = math.huge,
		PlotToFloor = math.huge,
		PlotToMerchant = math.huge,
		OutermostPlotCorner = 0,
	}
	for i, plot in layout.Plots do
		for j = i + 1, #layout.Plots do
			m.MinPlotGap = math.min(m.MinPlotGap, Geometry2D.PolygonDistance(plot.Area.Polygon, layout.Plots[j].Area.Polygon))
		end
		m.PlotToPlaza = math.min(m.PlotToPlaza, Geometry2D.NearestToPoint(plot.Area.Polygon, origin) - layout.PlazaRadius)
		m.PlotToRunway = math.min(m.PlotToRunway, Geometry2D.PolygonDistance(plot.Area.Polygon, layout.Runway.Polygon))
		m.PlotToFloor = math.min(m.PlotToFloor, Geometry2D.PolygonDistance(plot.Area.Polygon, layout.Floor.Polygon))
		m.PlotToMerchant = math.min(
			m.PlotToMerchant,
			Geometry2D.PolygonDistance(plot.Area.Polygon, layout.PermanentMerchant.Polygon),
			Geometry2D.PolygonDistance(plot.Area.Polygon, layout.TravelingMerchant.Polygon)
		)
		m.OutermostPlotCorner = math.max(m.OutermostPlotCorner, Geometry2D.FarthestFromPoint(plot.Area.Polygon, origin))
	end
	m.GrassMargin = layout.GrassRadius - m.OutermostPlotCorner
	m.GrassToFloor = layout.FloorBackX - layout.GrassRadius
	m.MerchantToRunway = math.min(
		Geometry2D.PolygonDistance(layout.PermanentMerchant.Polygon, layout.Runway.Polygon),
		Geometry2D.PolygonDistance(layout.TravelingMerchant.Polygon, layout.Runway.Polygon)
	)
	m.MerchantToPath = math.huge
	for _, path in layout.Paths do
		m.MerchantToPath = math.min(
			m.MerchantToPath,
			Geometry2D.PolygonDistance(layout.PermanentMerchant.Polygon, path.Polygon),
			Geometry2D.PolygonDistance(layout.TravelingMerchant.Polygon, path.Polygon)
		)
	end
	return m
end

-- ===== World placement =====

-- Hub centre on the ground, same orientation as the floor (LookVector = course forward).
function HubLayout.HubCentre(floorCFrame: CFrame, floorSize: Vector3): CFrame
	local origin = CourseLayout.OriginFromFloor(floorCFrame, floorSize) -- starting line centre
	return origin * CFrame.new(0, 0, floorSize.Z + HubConfig.RunwayLength + HubConfig.PlazaRadius)
end

function HubLayout.ToWorld(centre: CFrame, point: Vector2, height: number?): Vector3
	return centre.Position + centre.LookVector * point.X + centre.RightVector * point.Y + centre.UpVector * (height or 0)
end

function HubLayout.ToHub(centre: CFrame, worldPosition: Vector3): Vector2
	local offset = worldPosition - centre.Position
	return Vector2.new(offset:Dot(centre.LookVector), offset:Dot(centre.RightVector))
end

-- A ground-level CFrame at a hub point whose LookVector points along `facing` (hub frame).
function HubLayout.WorldCFrame(centre: CFrame, point: Vector2, facing: Vector2): CFrame
	local position = HubLayout.ToWorld(centre, point)
	local look = centre.LookVector * facing.X + centre.RightVector * facing.Y
	return CFrame.lookAt(position, position + look, centre.UpVector)
end

function HubLayout.Compute(floorCFrame: CFrame, floorSize: Vector3): WorldLayout
	local centre = HubLayout.HubCentre(floorCFrame, floorSize)
	local layout = HubLayout.Compute2D(floorSize)
	local plots: { WorldPlot } = {}
	for _, plot in layout.Plots do
		local inward = -plot.Radial
		plots[plot.Index] = {
			Index = plot.Index,
			CFrame = HubLayout.WorldCFrame(centre, plot.Area.Centre, inward),
			Entrance = HubLayout.WorldCFrame(centre, plot.FrontCentre, inward),
			Home = HubLayout.WorldCFrame(centre, plot.HomePoint, inward),
			Sign = HubLayout.WorldCFrame(centre, plot.Sign, inward),
			Pad = HubLayout.WorldCFrame(centre, plot.PadCentre, inward),
		}
	end
	return {
		Centre = centre,
		Layout = layout,
		Plots = plots,
		Runway = HubLayout.WorldCFrame(centre, layout.Runway.Centre, layout.Runway.Axis),
		PermanentMerchant = HubLayout.WorldCFrame(centre, layout.PermanentMerchant.Centre, layout.PermanentMerchant.Axis),
		TravelingMerchant = HubLayout.WorldCFrame(centre, layout.TravelingMerchant.Centre, layout.TravelingMerchant.Axis),
	}
end

return HubLayout

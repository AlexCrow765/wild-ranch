--!strict
-- Ranch Hub Stage 1: HubConfig + HubLayout geometry (no world is built here).
-- Clearance tests use the minimums in HubConfig.Validation, so provisional sizes can be tuned
-- without editing these tests; they fail only if a change breaks the layout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Rules = Shared:WaitForChild("Rules")
local HubConfig = require(Config:WaitForChild("HubConfig"))
local CourseConfig = require(Config:WaitForChild("CourseConfig"))
local HubLayout = require(Rules:WaitForChild("HubLayout"))
local CourseLayout = require(Rules:WaitForChild("CourseLayout"))
local Geometry2D = require(Shared:WaitForChild("Util"):WaitForChild("Geometry2D"))

-- Roblox Vector2/Vector3/CFrame components are 32-bit floats (~7 significant digits), so layout
-- values built from them are only exact to ~1e-5 studs at hub distances.
local EPS = 1e-3
local WORLD_EPS = 1e-3
local FLOOR_SIZE = CourseConfig.StartingFloorSize
local DEFAULT_FLOOR = CourseConfig.DefaultStartingFloorCFrame
local ROTATED_FLOOR = CFrame.new(437, 12.5, -819) * CFrame.Angles(0, math.rad(-63), 0)

local function angleOf(v: Vector2): number
	local degrees = math.deg(math.atan2(v.Y, v.X))
	return if degrees < 0 then degrees + 360 else degrees
end

local function floorBackEdge(floorCFrame: CFrame): Vector3
	return (floorCFrame * CFrame.new(0, FLOOR_SIZE.Y / 2, FLOOR_SIZE.Z / 2)).Position
end

return function(t)
	local layout = HubLayout.Compute2D(FLOOR_SIZE)
	local m = HubLayout.Measure(layout)
	local v = HubConfig.Validation

	t.test("approved provisional values are in HubConfig (O1, O2, O5)", function()
		t.eq(HubConfig.PlotCount, 5)
		t.eq(HubConfig.PlotAngleStepDegrees, 72)
		t.eq(HubConfig.FirstPlotAngleDegrees, 36, "runway uses the 0° gap between Plots 5 and 1")
		t.eq(HubConfig.PlotWidth, 120)
		t.eq(HubConfig.PlotDepth, 120)
		t.eq(HubConfig.PlotCentreRadius, 195)
		t.eq(HubConfig.PlazaRadius, 120)
		t.eq(HubConfig.RunwayWidth, 40)
		t.eq(HubConfig.RunwayLength, 160)
		t.eq(HubConfig.GrassRadius, 275)
		t.eq(HubConfig.Pen.InitialWidth, 60)
		t.eq(HubConfig.Pen.InitialDepth, 60)
		t.eq(HubConfig.Pen.BackMargin, 4)
	end)

	t.test("five unique plots, 72° apart at 36/108/180/252/324, equal size, centres at r = 195", function()
		t.eq(#layout.Plots, 5)
		local expected = { 36, 108, 180, 252, 324 }
		for i, plot in layout.Plots do
			t.near(angleOf(plot.Area.Centre), expected[i], 1e-3, `plot {i} angle`)
			t.near(plot.Area.Centre.Magnitude, 195, EPS, `plot {i} radius`)
			t.eq(plot.Area.Length, 120)
			t.eq(plot.Area.Width, 120)
			for j = i + 1, 5 do
				t.truthy((plot.Area.Centre - layout.Plots[j].Area.Centre).Magnitude > 100, "distinct positions")
			end
		end
	end)

	t.test("every plot faces the plaza (entrance toward the hub centre)", function()
		local world = HubLayout.Compute(DEFAULT_FLOOR, FLOOR_SIZE)
		for _, plot in world.Plots do
			local toCentre = (world.Centre.Position - plot.CFrame.Position).Unit
			t.near(plot.CFrame.LookVector:Dot(toCentre), 1, WORLD_EPS, `plot {plot.Index} faces the centre`)
		end
	end)

	t.test("no plot overlap; every neighbour gap >= MinPlotGap", function()
		for i, a in layout.Plots do
			for j = i + 1, #layout.Plots do
				t.truthy(Geometry2D.PolygonDistance(a.Area.Polygon, layout.Plots[j].Area.Polygon) > 0, `plots {i}/{j} overlap`)
			end
		end
		t.truthy(m.MinPlotGap >= v.MinPlotGap, `min plot gap {m.MinPlotGap}`)
	end)

	t.test("plots clear of the plaza, runway, starting floor and both merchant spots", function()
		t.truthy(m.PlotToPlaza >= v.MinPlotToPlaza, `plaza {m.PlotToPlaza}`)
		t.truthy(m.PlotToRunway >= v.MinPlotToRunway, `runway {m.PlotToRunway}`)
		t.truthy(m.PlotToFloor >= v.MinPlotToFloor, `floor {m.PlotToFloor}`)
		t.truthy(m.PlotToMerchant >= v.MinPlotToMerchant, `merchants {m.PlotToMerchant}`)
	end)

	t.test("grass contains every plot and stops before the starting floor", function()
		t.truthy(m.GrassMargin >= v.MinGrassMargin, `grass margin {m.GrassMargin}`)
		t.truthy(m.GrassToFloor > 0, `grass reaches the floor ({m.GrassToFloor})`)
	end)

	t.test("runway runs from the plaza edge to the floor's back edge, between Plots 5 and 1", function()
		local runway = layout.Runway
		t.near(runway.Centre.X - runway.Length / 2, layout.PlazaRadius, EPS, "starts at the plaza edge")
		t.near(runway.Centre.X + runway.Length / 2, layout.FloorBackX, EPS, "ends at the floor back edge")
		t.near(runway.Centre.Y, 0, EPS, "on the course centre line")
		t.eq(angleOf(runway.Axis), 0)
	end)

	t.test("runway meets the floor's back edge in the world (default and rotated/offset floor)", function()
		for _, floorCFrame in { DEFAULT_FLOOR, ROTATED_FLOOR } do
			local world = HubLayout.Compute(floorCFrame, FLOOR_SIZE)
			local runway = world.Layout.Runway
			local farEnd = HubLayout.ToWorld(world.Centre, runway.Centre + runway.Axis * (runway.Length / 2))
			t.near((farEnd - floorBackEdge(floorCFrame)).Magnitude, 0, WORLD_EPS, "runway end on the floor back edge")
			local origin = CourseLayout.OriginFromFloor(floorCFrame, FLOOR_SIZE)
			local _, lateral = CourseLayout.ToCourseSpace(origin, world.Centre.Position)
			t.near(lateral, 0, WORLD_EPS, "hub centre on the course centre line")
			t.near(world.Centre.LookVector:Dot(origin.LookVector), 1, WORLD_EPS, "hub faces the course direction")
		end
	end)

	t.test("nothing in the hub reaches the starting floor or the course (both floors)", function()
		for _, floorCFrame in { DEFAULT_FLOOR, ROTATED_FLOOR } do
			local world = HubLayout.Compute(floorCFrame, FLOOR_SIZE)
			local origin = CourseLayout.OriginFromFloor(floorCFrame, FLOOR_SIZE)
			local function behindFloor(point: Vector2, label: string)
				local distance = CourseLayout.ToCourseSpace(origin, HubLayout.ToWorld(world.Centre, point))
				t.truthy(distance < -FLOOR_SIZE.Z + WORLD_EPS, `{label} reaches the floor/course (d = {distance})`)
			end
			for _, plot in world.Layout.Plots do
				for k, corner in plot.Area.Polygon do
					behindFloor(corner, `plot {plot.Index} corner {k}`)
				end
			end
			behindFloor(Vector2.new(world.Layout.GrassRadius, 0), "grass edge")
			for _, corner in world.Layout.PermanentMerchant.Polygon do
				behindFloor(corner, "permanent merchant")
			end
		end
	end)

	t.test("initial pen 60 x 60 inside its plot, 4 studs from the back, centred sideways", function()
		for _, plot in layout.Plots do
			local pen = plot.InitialPen
			t.eq(pen.Width, 60)
			t.eq(pen.Length, 60)
			t.truthy(Geometry2D.PolygonInside(pen.Polygon, plot.Area.Polygon), `pen inside plot {plot.Index}`)
			local penBack = pen.Centre:Dot(plot.Radial) + pen.Length / 2
			local plotBack = HubConfig.PlotCentreRadius + HubConfig.PlotDepth / 2
			t.near(plotBack - penBack, 4, EPS, "4-stud back margin")
			t.near(pen.Centre:Dot(plot.Lateral), 0, EPS, "centred sideways")
		end
	end)

	t.test("maximum pen is 112 x 104, fits the plot and keeps the 12-stud front strip free", function()
		local maxWidth, maxDepth = HubLayout.MaxPenSize()
		t.eq(maxWidth, 112)
		t.eq(maxDepth, 104)
		for _, plot in layout.Plots do
			local pen = plot.MaxPen
			t.truthy(Geometry2D.PolygonInside(pen.Polygon, plot.Area.Polygon), `max pen inside plot {plot.Index}`)
			local penFront = pen.Centre:Dot(plot.Radial) - pen.Length / 2
			local plotFront = HubConfig.PlotCentreRadius - HubConfig.PlotDepth / 2
			t.near(penFront - plotFront, 12, EPS, "front strip")
			t.truthy(plot.HomePoint:Dot(plot.Radial) < penFront, "home point stays in front of the largest pen")
		end
	end)

	t.test("pens grow toward the entrance and sideways; the back edge never moves; oversize rejected", function()
		local plot = layout.Plots[1]
		local small = HubLayout.PenRect(plot, 60, 60)
		local big = HubLayout.PenRect(plot, 90, 80)
		local function back(r)
			return r.Centre:Dot(plot.Radial) + r.Length / 2
		end
		local function front(r)
			return r.Centre:Dot(plot.Radial) - r.Length / 2
		end
		t.near(back(small), back(big), EPS, "back edge fixed")
		t.truthy(front(big) < front(small), "front edge moves toward the entrance")
		t.errors(function()
			HubLayout.PenRect(plot, 113, 60)
		end, "exceeds the maximum")
		t.errors(function()
			HubLayout.PenRect(plot, 60, 105)
		end, "exceeds the maximum")
	end)

	t.test("home point on the dirt; sign and collection pad on the grass strip, outside plot and plaza", function()
		for _, plot in layout.Plots do
			t.truthy(Geometry2D.PointInPolygon(plot.HomePoint, plot.Area.Polygon), `home inside plot {plot.Index}`)
			t.eq(Geometry2D.PointInPolygon(plot.Sign, plot.Area.Polygon), false, "sign outside the dirt")
			t.truthy(plot.Sign.Magnitude > layout.PlazaRadius, "sign outside the plaza")
			local padNearest = plot.PadCentre.Magnitude - plot.PadRadius
			t.truthy(padNearest > layout.PlazaRadius, "pad outside the plaza")
			t.truthy(Geometry2D.NearestToPoint(plot.Area.Polygon, plot.PadCentre) >= plot.PadRadius, "pad outside the dirt")
		end
	end)

	t.test("merchant spots: inside the plaza, opposite each other, 16 x 10, clear of runway and walking lines", function()
		for _, spot in { layout.PermanentMerchant, layout.TravelingMerchant } do
			t.truthy(Geometry2D.FarthestFromPoint(spot.Polygon, Vector2.zero) <= layout.PlazaRadius, "inside the plaza")
			t.eq(spot.Length, 16)
			t.eq(spot.Width, 10)
		end
		t.near(math.abs(angleOf(layout.TravelingMerchant.Centre) - angleOf(layout.PermanentMerchant.Centre)), 180, 1e-3, "opposite sides")
		t.truthy(m.MerchantToRunway >= v.MinMerchantToRunway, `merchant to runway {m.MerchantToRunway}`)
		t.truthy(m.MerchantToPath >= v.MinMerchantToPath, `merchant to walking lines {m.MerchantToPath}`)
	end)

	t.test("layout is deterministic (same inputs -> identical output)", function()
		local a = HubLayout.Compute2D(FLOOR_SIZE)
		local b = HubLayout.Compute2D(FLOOR_SIZE)
		for i, plot in a.Plots do
			for k, corner in plot.Area.Polygon do
				t.eq(corner, b.Plots[i].Area.Polygon[k])
			end
			t.eq(plot.HomePoint, b.Plots[i].HomePoint)
			t.eq(plot.InitialPen.Centre, b.Plots[i].InitialPen.Centre)
		end
		local wa = HubLayout.Compute(ROTATED_FLOOR, FLOOR_SIZE)
		local wb = HubLayout.Compute(ROTATED_FLOOR, FLOOR_SIZE)
		t.eq(wa.Centre, wb.Centre)
		for i, plot in wa.Plots do
			t.eq(plot.Home, wb.Plots[i].Home)
		end
	end)

	t.test("rotated/offset floor: the same layout, moved and turned with the floor", function()
		local default = HubLayout.Compute(DEFAULT_FLOOR, FLOOR_SIZE)
		local rotated = HubLayout.Compute(ROTATED_FLOOR, FLOOR_SIZE)
		for i, plot in rotated.Plots do
			-- In the hub's own frame, every point is identical for both floors.
			local hubPoint = HubLayout.ToHub(rotated.Centre, plot.CFrame.Position)
			t.near((hubPoint - rotated.Layout.Plots[i].Area.Centre).Magnitude, 0, WORLD_EPS, `plot {i} hub coords`)
			-- Distances from the hub centre and between plots are preserved in the world.
			t.near(
				(plot.CFrame.Position - rotated.Centre.Position).Magnitude,
				(default.Plots[i].CFrame.Position - default.Centre.Position).Magnitude,
				WORLD_EPS,
				`plot {i} distance from centre`
			)
			-- Ground level follows the floor top.
			local height = (plot.CFrame.Position - rotated.Centre.Position):Dot(rotated.Centre.UpVector)
			t.near(height, 0, WORLD_EPS, `plot {i} on the ground plane`)
		end
		t.near(
			(rotated.Centre.Position - floorBackEdge(ROTATED_FLOOR)).Magnitude,
			HubConfig.RunwayLength + HubConfig.PlazaRadius,
			WORLD_EPS,
			"hub centre distance from the floor back edge"
		)
	end)
end

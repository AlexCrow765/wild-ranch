--!strict
--[[
	Geometry2D
	Pure 2D helpers for convex polygons (rectangles) and circles, used by HubLayout and its tests.
	Points are Vector2. Polygons are arrays of corners in order (clockwise or anticlockwise).
]]

local Geometry2D = {}

export type Polygon = { Vector2 }

-- Rectangle corners from its centre, the unit direction of its "length" axis, and full sizes.
function Geometry2D.Rect(centre: Vector2, lengthAxis: Vector2, length: number, width: number): Polygon
	local u = lengthAxis.Unit
	local v = Vector2.new(-u.Y, u.X)
	local hl, hw = length / 2, width / 2
	return {
		centre + u * hl + v * hw,
		centre + u * hl - v * hw,
		centre - u * hl - v * hw,
		centre - u * hl + v * hw,
	}
end

local function cross(a: Vector2, b: Vector2, c: Vector2): number
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

function Geometry2D.PointInPolygon(point: Vector2, polygon: Polygon): boolean
	local sign = 0
	for i = 1, #polygon do
		local a = polygon[i]
		local b = polygon[i % #polygon + 1]
		local c = cross(a, b, point)
		if c ~= 0 then
			local s = if c > 0 then 1 else -1
			if sign ~= 0 and s ~= sign then
				return false
			end
			sign = s
		end
	end
	return true
end

function Geometry2D.PointToSegment(point: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	local t = if lengthSq > 0 then math.clamp((point - a):Dot(ab) / lengthSq, 0, 1) else 0
	return (point - (a + ab * t)).Magnitude
end

local function segmentsCross(a: Vector2, b: Vector2, c: Vector2, d: Vector2): boolean
	return cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0
end

-- Shortest distance between two convex polygons; 0 if they touch or overlap.
function Geometry2D.PolygonDistance(a: Polygon, b: Polygon): number
	for _, p in a do
		if Geometry2D.PointInPolygon(p, b) then
			return 0
		end
	end
	for _, p in b do
		if Geometry2D.PointInPolygon(p, a) then
			return 0
		end
	end
	local best = math.huge
	for i = 1, #a do
		local a1, a2 = a[i], a[i % #a + 1]
		for j = 1, #b do
			local b1, b2 = b[j], b[j % #b + 1]
			if segmentsCross(a1, a2, b1, b2) then
				return 0
			end
			best = math.min(
				best,
				Geometry2D.PointToSegment(a1, b1, b2),
				Geometry2D.PointToSegment(b1, a1, a2)
			)
		end
	end
	return best
end

-- Nearest and farthest distance from a point to a polygon (0 nearest if the point is inside).
function Geometry2D.NearestToPoint(polygon: Polygon, point: Vector2): number
	if Geometry2D.PointInPolygon(point, polygon) then
		return 0
	end
	local best = math.huge
	for i = 1, #polygon do
		best = math.min(best, Geometry2D.PointToSegment(point, polygon[i], polygon[i % #polygon + 1]))
	end
	return best
end

function Geometry2D.FarthestFromPoint(polygon: Polygon, point: Vector2): number
	local best = 0
	for _, corner in polygon do
		best = math.max(best, (corner - point).Magnitude)
	end
	return best
end

-- True if every corner of `inner` lies inside `outer` (convex).
function Geometry2D.PolygonInside(inner: Polygon, outer: Polygon): boolean
	for _, p in inner do
		if not Geometry2D.PointInPolygon(p, outer) then
			return false
		end
	end
	return true
end

return Geometry2D

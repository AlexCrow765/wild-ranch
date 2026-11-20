--!strict
--[[
	HoldTracker
	Pure bookkeeping for on-screen "hold" buttons (mobile steering).

	Each active input (a touch finger or the mouse button) is tracked separately by its key
	(the InputObject in the game, any value in tests). A button counts as held while at least
	one active input is pressing it, so:
	  - two fingers on the same button: lifting one keeps it held,
	  - a finger that slides off the button, is cancelled, or lifts anywhere releases only
	    its own hold,
	  - Clear() drops everything (run ended, buttons hidden, window lost focus).
	A key can hold only one button at a time; pressing again moves it.
]]

export type Tracker = {
	Holds: { [any]: string }, -- input key -> button name
}

local HoldTracker = {}

function HoldTracker.new(): Tracker
	return { Holds = {} }
end

function HoldTracker.Press(tracker: Tracker, key: any, button: string)
	assert(key ~= nil, "input key required")
	tracker.Holds[key] = button
end

-- Releases one input. Returns true if it was holding something.
function HoldTracker.Release(tracker: Tracker, key: any): boolean
	if key ~= nil and tracker.Holds[key] ~= nil then
		tracker.Holds[key] = nil
		return true
	end
	return false
end

-- Releases every input currently holding `button`.
function HoldTracker.ReleaseButton(tracker: Tracker, button: string)
	for key, held in tracker.Holds do
		if held == button then
			tracker.Holds[key] = nil
		end
	end
end

function HoldTracker.Clear(tracker: Tracker)
	table.clear(tracker.Holds)
end

function HoldTracker.IsHeld(tracker: Tracker, button: string): boolean
	for _, held in tracker.Holds do
		if held == button then
			return true
		end
	end
	return false
end

function HoldTracker.IsTracking(tracker: Tracker, key: any): boolean
	return key ~= nil and tracker.Holds[key] ~= nil
end

function HoldTracker.ButtonFor(tracker: Tracker, key: any): string?
	return if key ~= nil then tracker.Holds[key] else nil
end

-- True if a screen point lies inside a GUI rectangle (inclusive edges).
function HoldTracker.IsInside(point: Vector2, absolutePosition: Vector2, absoluteSize: Vector2): boolean
	return point.X >= absolutePosition.X
		and point.Y >= absolutePosition.Y
		and point.X <= absolutePosition.X + absoluteSize.X
		and point.Y <= absolutePosition.Y + absoluteSize.Y
end

return HoldTracker

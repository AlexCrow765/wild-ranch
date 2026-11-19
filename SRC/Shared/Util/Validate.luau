--!strict
--[[
	Validate
	Small checks shared by rules modules so bad config values fail with a clear message.
]]

local Validate = {}

-- True for real numbers only: rejects non-numbers, NaN and +/- infinity.
function Validate.IsFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- True for finite whole numbers.
function Validate.IsInteger(value: any): boolean
	return Validate.IsFiniteNumber(value) and value % 1 == 0
end

return Validate

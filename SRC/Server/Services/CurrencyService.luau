--!strict
--[[
	CurrencyService
	Server-only coin and gem balance changes. Amounts must be positive whole numbers.
	Spend* fails (and changes nothing) if the balance is too low.
]]

local DataService = require(script.Parent:WaitForChild("DataService"))

export type Currency = "Coins" | "Gems"

local CurrencyService = {
	LoadOrder = 20,
}

local function isValidAmount(amount: any): boolean
	return typeof(amount) == "number" and amount > 0 and amount % 1 == 0 and amount < math.huge
end

function CurrencyService.Get(player: Player, currency: Currency): number?
	local data = DataService.Get(player)
	return if data then data[currency] else nil
end

function CurrencyService.Add(player: Player, currency: Currency, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end
	local updated = DataService.Update(player, function(data)
		data[currency] += amount
	end)
	return updated
end

function CurrencyService.Spend(player: Player, currency: Currency, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end
	local updated, spent = DataService.Update(player, function(data)
		if data[currency] < amount then
			return false
		end
		data[currency] -= amount
		return true
	end)
	return updated and spent == true
end

return CurrencyService

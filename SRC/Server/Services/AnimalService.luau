--!strict
--[[
	AnimalService
	Server-only creation and editing of owned animals.

	Every owned animal is stored in PlayerData.Animals under a unique id:
	  Animals[id] = {Species, Stars, Variant, BiomeCaught, Level, Placed}

	None of these functions are reachable from the client. Later systems call them after
	their own validation (TamingService -> Give, RanchService -> SetPlaced,
	MountService -> SetLevel). Capacity limits arrive with Phase 7.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animal = require(Shared:WaitForChild("Types"):WaitForChild("Animal"))
local MountConfig = require(Shared:WaitForChild("Config"):WaitForChild("MountConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local AnimalService = {
	LoadOrder = 20,
}

local function newId(): string
	return HttpService:GenerateGUID(false)
end

-- Creates an owned animal (Level 1, not placed). Returns its id, or nil + reason.
function AnimalService.Give(player: Player, traits: Animal.AnimalTraits): (string?, string?)
	local ok, reason = Animal.ValidateTraits(traits)
	if not ok then
		return nil, reason
	end

	local id = newId()
	local updated = DataService.Update(player, function(data)
		data.Animals[id] = Animal.NewOwned(traits)
	end)
	if not updated then
		return nil, "player data not loaded"
	end
	return id
end

function AnimalService.Remove(player: Player, id: string): boolean
	local updated, removed = DataService.Update(player, function(data)
		if data.Animals[id] == nil then
			return false
		end
		data.Animals[id] = nil
		return true
	end)
	return updated and removed == true
end

-- Copy of one animal record (safe to read or modify; changes are not saved).
function AnimalService.Get(player: Player, id: string): Animal.OwnedAnimal?
	local data = DataService.Get(player)
	local record = data and data.Animals[id]
	return if record then table.clone(record) else nil
end

-- Copies of all of a player's animals, keyed by id.
function AnimalService.List(player: Player): { [string]: Animal.OwnedAnimal }
	local result = {}
	local data = DataService.Get(player)
	if data then
		for id, record in data.Animals do
			result[id] = table.clone(record)
		end
	end
	return result
end

function AnimalService.Count(player: Player): number
	local count = 0
	local data = DataService.Get(player)
	if data then
		for _ in data.Animals do
			count += 1
		end
	end
	return count
end

function AnimalService.SetPlaced(player: Player, id: string, placed: boolean): boolean
	if typeof(placed) ~= "boolean" then
		return false
	end
	local updated, changed = DataService.Update(player, function(data)
		local record = data.Animals[id]
		if record == nil then
			return false
		end
		record.Placed = placed
		return true
	end)
	return updated and changed == true
end

-- Sets a mount level within StartingLevel..MaxLevelByStars[stars]. Coin cost is MountService's job.
function AnimalService.SetLevel(player: Player, id: string, level: number): (boolean, string?)
	local updated, ok, reason = false, false, nil :: string?
	updated = DataService.Update(player, function(data)
		local record = data.Animals[id]
		if record == nil then
			reason = "no such animal"
			return
		end
		local maxLevel = Animal.MaxLevel(record.Stars)
		if typeof(level) ~= "number" or level % 1 ~= 0 or level < MountConfig.StartingLevel or level > maxLevel then
			reason = `level must be {MountConfig.StartingLevel}-{maxLevel}`
			return
		end
		record.Level = level
		ok = true
	end)
	if not updated then
		return false, "player data not loaded"
	end
	return ok, reason
end

return AnimalService

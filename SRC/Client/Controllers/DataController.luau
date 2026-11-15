--!strict
--[[
	DataController
	Read-only client copy of this player's own saved data.

	  DataController.Data       current copy (nil until loaded)
	  DataController.Changed    fires (data) whenever the server sends an update

	The client never writes data; it asks the server through validated remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local DataController = {
	LoadOrder = 5,
	Data = nil :: any,
	Changed = Signal.new(),
}

local function countAnimals(data: any): number
	local count = 0
	for _ in data.Animals do
		count += 1
	end
	return count
end

local function receive(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local first = DataController.Data == nil
	DataController.Data = data
	if first then
		print(`[DataController] Data loaded: {data.Coins} coins, {data.Gems} gems, {countAnimals(data)} animals`)
	end
	DataController.Changed:Fire(data)
end

function DataController:Start()
	Remotes.Event("PlayerDataSnapshot").OnClientEvent:Connect(receive)

	-- In case the first snapshot was sent before we were listening.
	if self.Data == nil then
		local ok, data = pcall(function()
			return Remotes.Function("GetPlayerData"):InvokeServer()
		end)
		if ok and data and self.Data == nil then
			receive(data)
		end
	end
end

return DataController

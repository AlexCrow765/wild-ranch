--!strict
--[[
	PlayerService
	Join/leave hub for other services.

	OnPlayerAdded also runs the callback for players who are already in the server,
	so a service that starts late never misses someone (a common Roblox race condition,
	especially in Studio Play Solo where the player can join before scripts run).
]]

local Players = game:GetService("Players")

local PlayerService = {
	LoadOrder = 1,
}

function PlayerService.OnPlayerAdded(callback: (Player) -> ()): RBXScriptConnection
	local connection = Players.PlayerAdded:Connect(callback)
	for _, player in Players:GetPlayers() do
		task.spawn(callback, player)
	end
	return connection
end

function PlayerService.OnPlayerRemoving(callback: (Player) -> ()): RBXScriptConnection
	return Players.PlayerRemoving:Connect(callback)
end

function PlayerService:Start()
	self.OnPlayerAdded(function(player)
		print(`[PlayerService] {player.Name} joined`)
	end)
	self.OnPlayerRemoving(function(player)
		print(`[PlayerService] {player.Name} left`)
	end)
end

return PlayerService

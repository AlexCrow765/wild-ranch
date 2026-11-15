--!strict
--[[
	PlayerData
	Shape of a player's saved data (current SchemaVersion). The client receives a
	read-only copy of its own data with this shape.

	When this shape changes: bump Schema.Version on the server, update Schema.Template,
	and add a migration step in Server/Data/Migrations.
]]

local Animal = require(script.Parent:WaitForChild("Animal"))

export type PlayerData = {
	SchemaVersion: number,
	Coins: number,
	Gems: number,
	Animals: { [string]: Animal.OwnedAnimal }, -- key = unique animal id
}

-- Types only; ModuleScripts must still return a value.
return {}

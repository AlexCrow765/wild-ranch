--!strict
--[[
	Schema
	Current save-data version and the template for brand-new players.

	To change the save shape:
	  1. Bump Version.
	  2. Update Template (new players start here).
	  3. Add a step in Migrations that upgrades a save from the previous version.
	  4. Update Shared/Types/PlayerData.
]]

local Schema = {}

Schema.Version = 1

-- Not frozen: ProfileStore deep-copies it into new profiles and Reconcile().
Schema.Template = {
	SchemaVersion = Schema.Version,
	-- OPEN QUESTION: starting coins/gems are not specified in the design doc; 0 until decided.
	Coins = 0,
	Gems = 0,
	Animals = {}, -- [uniqueId] = OwnedAnimal {Species, Stars, Variant, BiomeCaught, Level, Placed}
}

return Schema

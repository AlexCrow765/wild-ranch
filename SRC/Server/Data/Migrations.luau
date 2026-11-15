--!strict
--[[
	Migrations
	Upgrades old saves to the current Schema.Version, one version at a time.

	Steps[n] upgrades a save from version n to n + 1 by editing the table in place.
	The runner sets SchemaVersion after each step. Never edit or delete a step that
	has shipped: players may still have saves at that version.

	Example for a future v2 that adds a Journal:
	  [1] = function(data)
	      data.Journal = {}
	  end,
]]

local Schema = require(script.Parent:WaitForChild("Schema"))

local Steps: { [number]: (data: any) -> () } = {
	-- (none yet: version 1 is the first schema)
}

local Migrations = {}

-- Returns the version the save was at before migrating.
function Migrations.Run(data: any): number
	local original = if typeof(data.SchemaVersion) == "number" then data.SchemaVersion else 1
	local version = original

	while version < Schema.Version do
		local step = Steps[version]
		assert(step ~= nil, `missing migration step from v{version} to v{version + 1}`)
		step(data)
		version += 1
		data.SchemaVersion = version
	end

	data.SchemaVersion = version
	return original
end

return Migrations

--!strict
--[[
	DataService
	Loads, saves and replicates each player's profile (ProfileStore, session-locked).

	Rules for other services:
	  - Read with DataService.Get(player) or DataService.WaitForData(player).
	    Treat the returned table as READ-ONLY.
	  - Write ONLY through DataService.Update(player, function(data) ... end).
	    Update marks the data for replication so the client copy stays in sync.

	Load flow: start session -> refuse saves newer than this server -> migrate a copy ->
	Reconcile (fill new template keys) -> report invalid animals (never auto-deleted) -> ready.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent.Parent
local ProfileStore = require(Server:WaitForChild("Vendor"):WaitForChild("ProfileStore"))
local DataFolder = Server:WaitForChild("Data")
local Schema = require(DataFolder:WaitForChild("Schema"))
local Migrations = require(DataFolder:WaitForChild("Migrations"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Animal = require(Shared:WaitForChild("Types"):WaitForChild("Animal"))

local PlayerService = require(script.Parent:WaitForChild("PlayerService"))

local STORE_NAME = "PlayerData"
local WAIT_POLL_SECONDS = 0.1

local DataService = {
	LoadOrder = 10,
	ProfileLoaded = Signal.new(), -- (player: Player, data)
	ProfileReleased = Signal.new(), -- (player: Player)
}

local store: any
local profiles: { [Player]: any } = {}
local replicationQueued: { [Player]: boolean } = {}
local snapshotRemote: RemoteEvent

local function profileKey(player: Player): string
	return `Player_{player.UserId}`
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy :: any
end

local function sendSnapshot(player: Player)
	replicationQueued[player] = nil
	local profile = profiles[player]
	if profile and isInGame(player) then
		snapshotRemote:FireClient(player, profile.Data)
	end
end

local function queueReplication(player: Player)
	if not replicationQueued[player] then
		replicationQueued[player] = true
		-- Batches several Updates in the same frame into one send.
		task.defer(sendSnapshot, player)
	end
end

local function reportInvalidAnimals(player: Player, data: any)
	for id, record in data.Animals do
		local ok, reason = Animal.ValidateOwned(record)
		if not ok then
			-- Never delete player data automatically; surface it for investigation.
			warn(`[DataService] {player.Name} has an invalid animal {id}: {reason}`)
		end
	end
end

local function loadProfile(player: Player)
	local profile = store:StartSessionAsync(profileKey(player), {
		Cancel = function()
			return not isInGame(player)
		end,
	})

	if profile == nil then
		if isInGame(player) then
			player:Kick("Your data could not be loaded. Please rejoin.")
		end
		return
	end

	if not isInGame(player) then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association

	-- A save written by a newer version of the game: do not touch it.
	local savedVersion = profile.Data.SchemaVersion
	if typeof(savedVersion) == "number" and savedVersion > Schema.Version then
		warn(`[DataService] {player.Name} has save v{savedVersion}; this server only knows v{Schema.Version}`)
		profile:EndSession()
		player:Kick("This server is out of date. Please rejoin to join a newer server.")
		return
	end

	-- Migrate a copy, so a failing migration can never leave a half-upgraded save behind.
	local migrated = deepCopy(profile.Data)
	local ok, result = pcall(Migrations.Run, migrated)
	if not ok then
		warn(`[DataService] Migration failed for {player.Name}: {result}`)
		profile:EndSession()
		player:Kick("Your data could not be upgraded. Please rejoin later.")
		return
	end
	if result ~= Schema.Version then
		print(`[DataService] Migrated {player.Name} from v{result} to v{Schema.Version}`)
	end
	profile.Data = migrated
	profile:Reconcile()

	reportInvalidAnimals(player, profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		replicationQueued[player] = nil
		DataService.ProfileReleased:Fire(player)
		if isInGame(player) then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)

	profiles[player] = profile
	print(`[DataService] Loaded {player.Name} ({profileKey(player)}, store: {ProfileStore.DataStoreState})`)
	DataService.ProfileLoaded:Fire(player, profile.Data)
	sendSnapshot(player)
end

-- Live data table for a loaded player, or nil. READ-ONLY for callers.
function DataService.Get(player: Player): any
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Yields until the player's data is loaded. Returns nil if they leave first.
function DataService.WaitForData(player: Player): any
	while isInGame(player) do
		local data = DataService.Get(player)
		if data then
			return data
		end
		task.wait(WAIT_POLL_SECONDS)
	end
	return nil
end

-- The only way to change saved data. Returns (true, result of fn) or (false) if not loaded.
function DataService.Update<T>(player: Player, fn: (data: any) -> T): (boolean, T?)
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false, nil
	end
	local result = fn(profile.Data)
	queueReplication(player)
	return true, result
end

-- "NotReady" | "NoInternet" | "NoAccess" (Studio mock, nothing persists) | "Access"
function DataService.StoreState(): string
	return ProfileStore.DataStoreState
end

function DataService:Init()
	store = ProfileStore.New(STORE_NAME, Schema.Template)
	snapshotRemote = Remotes.Event("PlayerDataSnapshot")

	-- Lets a client fetch its own data on start-up (never anyone else's).
	Remotes.Function("GetPlayerData").OnServerInvoke = function(player: Player)
		return DataService.WaitForData(player)
	end
end

function DataService:Start()
	PlayerService.OnPlayerAdded(loadProfile)
	PlayerService.OnPlayerRemoving(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession()
		end
	end)
end

return DataService

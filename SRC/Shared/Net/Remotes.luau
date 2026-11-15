--!strict
--[[
	Remotes
	The single list of every RemoteEvent / RemoteFunction in the game.

	- The server creates them all at boot (Remotes.Setup in Server/Main).
	- The client waits for them by name.
	- Asking for a name that is not in Definitions errors immediately, so typos
	  are caught instead of silently waiting forever.

	Add remotes here as each system is built, e.g.
	  TamingInput = "Event",
	  RequestPlaceAnimal = "Function",

	SECURITY: the server must treat every argument coming from a client as untrusted
	and validate it (type, range, ownership, state) before acting on it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type Kind = "Event" | "UnreliableEvent" | "Function"

local Definitions: { [string]: Kind } = {
	-- Phase 1: data
	PlayerDataSnapshot = "Event", -- server -> client: full copy of the player's own data
	GetPlayerData = "Function", -- client -> server: fetch own data on start-up
}

local FOLDER_NAME = "Remotes"
local CLASS_BY_KIND: { [Kind]: string } = {
	Event = "RemoteEvent",
	UnreliableEvent = "UnreliableRemoteEvent",
	Function = "RemoteFunction",
}

local Remotes = {}

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name: string, expected: Kind): Instance
	local kind = Definitions[name]
	assert(kind ~= nil, `Remote "{name}" is not defined in Remotes.Definitions`)
	assert(kind == expected, `Remote "{name}" is a {kind}, not a {expected}`)

	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(CLASS_BY_KIND[kind])
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: Instance
	end
	return folder:WaitForChild(name)
end

-- Server only: create every defined remote up front so clients never wait on a missing one.
function Remotes.Setup()
	assert(RunService:IsServer(), "Remotes.Setup is server-only")
	for name, kind in Definitions do
		get(name, kind)
	end
end

function Remotes.Event(name: string): RemoteEvent
	return get(name, "Event") :: RemoteEvent
end

function Remotes.UnreliableEvent(name: string): UnreliableRemoteEvent
	return get(name, "UnreliableEvent") :: UnreliableRemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return get(name, "Function") :: RemoteFunction
end

return Remotes

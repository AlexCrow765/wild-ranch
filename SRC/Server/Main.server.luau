--!strict
--[[
	Server entry point. The only server Script; everything else is a ModuleScript
	in Services/, booted by the shared Loader (Init all -> Start all).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Util"):WaitForChild("Loader"))
local Remotes = require(Shared:WaitForChild("Net"):WaitForChild("Remotes"))

-- Remotes exist before any service or client asks for them.
Remotes.Setup()

Loader.Load(script.Parent:WaitForChild("Services"), "Server")

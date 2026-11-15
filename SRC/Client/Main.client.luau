--!strict
--[[
	Client entry point. The only LocalScript; everything else is a ModuleScript
	in Controllers/, booted by the shared Loader (Init all -> Start all).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Util"):WaitForChild("Loader"))

Loader.Load(script.Parent:WaitForChild("Controllers"), "Client")

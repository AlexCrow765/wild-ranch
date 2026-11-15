--!strict
--[[
	Loader
	Boots every ModuleScript in a folder (server Services or client Controllers).

	Each module is a plain table that may define:
	  LoadOrder: number?     lower runs first (default 100)
	  Init: (self) -> ()     setup only; do NOT call other modules here
	  Start: (self) -> ()    runs after every module's Init; may call other modules

	Modules reach each other with a normal require, e.g.
	  local DataService = require(script.Parent.DataService)
	Phase order: all Init calls (in LoadOrder) -> all Start calls (each in its own thread).
]]

local Loader = {}

type Entry = { name: string, module: any }

local DEFAULT_LOAD_ORDER = 100

function Loader.Load(folder: Instance, label: string): { [string]: any }
	local entries: { Entry } = {}

	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require, child)
			if ok then
				table.insert(entries, { name = child.Name, module = result })
			else
				warn(`[{label}] Failed to load {child.Name}: {result}`)
			end
		end
	end

	table.sort(entries, function(a: Entry, b: Entry)
		local orderA = a.module.LoadOrder or DEFAULT_LOAD_ORDER
		local orderB = b.module.LoadOrder or DEFAULT_LOAD_ORDER
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.name < b.name
	end)

	local loaded: { [string]: any } = {}
	for _, entry in entries do
		loaded[entry.name] = entry.module
	end

	for _, entry in entries do
		if typeof(entry.module.Init) == "function" then
			local ok, err = xpcall(entry.module.Init, debug.traceback, entry.module)
			if not ok then
				warn(`[{label}] {entry.name}:Init failed\n{err}`)
			end
		end
	end

	for _, entry in entries do
		if typeof(entry.module.Start) == "function" then
			task.spawn(function()
				local ok, err = xpcall(entry.module.Start, debug.traceback, entry.module)
				if not ok then
					warn(`[{label}] {entry.name}:Start failed\n{err}`)
				end
			end)
		end
	end

	print(`[{label}] Loaded {#entries} module(s)`)
	return loaded
end

return Loader

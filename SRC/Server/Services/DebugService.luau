--!strict
--[[
	DebugService  (Studio only - does nothing in live servers)

	Test commands for the server, run from the Studio command bar while playing
	(in "Clients and Servers" mode, use the command bar of the Server window):

	  print(game.ServerStorage.WildRanchDebug:Invoke("help"))
	  print(game.ServerStorage.WildRanchDebug:Invoke("report"))
	  print(game.ServerStorage.WildRanchDebug:Invoke("give Player1 TestCritter 3 Gold Plains"))
	  print(game.ServerStorage.WildRanchDebug:Invoke("coins Player1 500"))

	Commands go through a BindableFunction because the command bar has its own copy of
	every required module; invoking the bindable runs the command inside the game itself.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(script.Parent:WaitForChild("DataService"))
local AnimalService = require(script.Parent:WaitForChild("AnimalService"))
local CurrencyService = require(script.Parent:WaitForChild("CurrencyService"))
local RunSessionService = require(script.Parent:WaitForChild("RunSessionService"))

local DebugService = {
	LoadOrder = 1000,
}

local HELP = [[
WildRanchDebug commands:
  help
  test                                           run all automated tests (ServerStorage.Tests)
  report                                         all players' data + store state
  give <player> <species> <stars> <variant> <biome>
  remove <player> <animalId>
  place <player> <animalId> <true|false>
  level <player> <animalId> <level>
  coins <player> <amount>       (negative to spend)
  gems <player> <amount>        (negative to spend)
  runinfo                                        every player's run state, progress and stamina
  goto <player> <distance>      move a riding player to a forward distance (studs)
  speed <player> <studsPerSec|reset>   test-only riding speed (now and for later rides)
  mount <player>                diagnose the rider's mount: position vs rider, welds, anchoring]]

local function findPlayer(name: string?): Player?
	if name == nil then
		return nil
	end
	local player = Players:FindFirstChild(name)
	return if player and player:IsA("Player") then player else nil
end

local function describePlayer(player: Player): string
	local data = DataService.Get(player)
	if data == nil then
		return `{player.Name} (UserId {player.UserId}): data not loaded`
	end
	local lines = {
		`{player.Name} (UserId {player.UserId}) v{data.SchemaVersion}: {data.Coins} coins, {data.Gems} gems, {AnimalService.Count(player)} animals`,
	}
	for id, a in data.Animals do
		table.insert(
			lines,
			`  {id}  {a.Species} {a.Stars}* {a.Variant} from {a.BiomeCaught}, Lv {a.Level}, {if a.Placed then "in ranch" else "in inventory"}`
		)
	end
	return table.concat(lines, "\n")
end

local function changeCurrency(player: Player, currency: "Coins" | "Gems", amountText: string?): string
	local amount = tonumber(amountText)
	if amount == nil or amount == 0 then
		return "amount must be a non-zero whole number"
	end
	local ok = if amount > 0
		then CurrencyService.Add(player, currency, amount)
		else CurrencyService.Spend(player, currency, -amount)
	return if ok then `{currency}: {CurrencyService.Get(player, currency)}` else `failed to change {currency}`
end

local function run(commandLine: string): string
	local args = string.split(commandLine, " ")
	local command = string.lower(args[1] or "")

	if command == "" or command == "help" then
		return HELP
	elseif command == "test" then
		local tests = ServerStorage:FindFirstChild("Tests")
		local runner = tests and tests:FindFirstChild("TestRunner")
		if runner == nil or not runner:IsA("ModuleScript") then
			return "ServerStorage.Tests.TestRunner not found (is Rojo connected?)"
		end
		return (require :: any)(runner).Run()
	elseif command == "runinfo" then
		return RunSessionService.DebugInfo()
	elseif command == "report" then
		local lines = { `DataStore state: {DataService.StoreState()}` }
		for _, player in Players:GetPlayers() do
			table.insert(lines, describePlayer(player))
		end
		return table.concat(lines, "\n")
	end

	local player = findPlayer(args[2])
	if player == nil then
		return `no player named "{tostring(args[2])}"`
	end

	if command == "give" then
		local id, reason = AnimalService.Give(player, {
			Species = args[3],
			Stars = tonumber(args[4]) :: number,
			Variant = args[5] :: any,
			BiomeCaught = args[6],
		})
		return if id then `gave {player.Name} animal {id}` else `give failed: {reason}`
	elseif command == "remove" then
		return if AnimalService.Remove(player, args[3]) then "removed" else "no such animal"
	elseif command == "place" then
		local placed = args[4] == "true"
		return if AnimalService.SetPlaced(player, args[3], placed) then `Placed = {placed}` else "no such animal"
	elseif command == "level" then
		local ok, reason = AnimalService.SetLevel(player, args[3], tonumber(args[4]) :: number)
		return if ok then "level set" else `level failed: {reason}`
	elseif command == "goto" then
		local distance = tonumber(args[3])
		if distance == nil then
			return "distance must be a number"
		end
		local ok, reason = RunSessionService.DebugSetProgress(player, distance)
		return if ok then `moved {player.Name} to {distance} studs` else `goto failed: {reason}`
	elseif command == "mount" then
		local lines = {}
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root == nil or not root:IsA("BasePart") then
			return "no character root"
		end
		table.insert(lines, `root position {root.Position}  anchored={root.Anchored}`)
		if humanoid then
			table.insert(lines, `humanoid rig={humanoid.RigType.Name} hipHeight={humanoid.HipHeight}`)
		end
		local mount = character:FindFirstChild("TestMount")
		if mount == nil then
			table.insert(lines, "no TestMount in the character")
		else
			table.insert(lines, `mount class={mount.ClassName} RiderHipHeight attr={tostring(mount:GetAttribute("RiderHipHeight"))}`)
			if mount:IsA("Model") then
				table.insert(lines, `mount pivot {mount:GetPivot().Position}  distance from root {string.format("%.1f", (mount:GetPivot().Position - root.Position).Magnitude)}`)
				local seat = mount:FindFirstChild("Seat", true)
				if seat and seat:IsA("Attachment") then
					table.insert(lines, `seat world {seat.WorldPosition}  offset from root {seat.WorldPosition - root.Position}`)
					table.insert(lines, `seat parent {seat.Parent and seat.Parent.Name}  local Position {seat.Position}  Orientation {seat.Orientation}`)
				end
			end
			local parts, anchored, welds, activeWelds = 0, 0, 0, 0
			local descendants = mount:GetDescendants()
			if mount:IsA("BasePart") then
				table.insert(descendants, mount)
			end
			for _, d in descendants do
				if d:IsA("BasePart") then
					parts += 1
					if d.Anchored then
						anchored += 1
					end
					table.insert(lines, `  part {d.Name} at {d.Position} (dist {string.format("%.1f", (d.Position - root.Position).Magnitude)})`)
				elseif d:IsA("WeldConstraint") then
					welds += 1
					if d.Active then
						activeWelds += 1
					end
				elseif d:IsA("JointInstance") or d:IsA("Constraint") then
					table.insert(lines, `  other joint/constraint: {d.ClassName} {d:GetFullName()}`)
				end
			end
			table.insert(lines, `parts={parts} anchored={anchored} weldConstraints={welds} active={activeWelds}`)
		end
		for _, item in game:GetService("Workspace"):GetDescendants() do
			if item.Name == "TestHorse" and item:IsA("Model") then
				table.insert(lines, `NOTE: a TestHorse model is also in Workspace: {item:GetFullName()} at {item:GetPivot().Position}`)
			end
		end
		return table.concat(lines, "\n")
	elseif command == "speed" then
		local value = args[3]
		local speed = if value == "reset" then nil else tonumber(value)
		if value ~= "reset" and speed == nil then
			return 'speed must be a number of studs/s, or "reset"'
		end
		local ok, reason = RunSessionService.DebugSetSpeed(player, speed)
		if not ok then
			return `speed failed: {reason}`
		end
		return if speed then `{player.Name} rides at {speed} studs/s (test only)` else `{player.Name} back to the normal riding speed`
	elseif command == "coins" then
		return changeCurrency(player, "Coins", args[3])
	elseif command == "gems" then
		return changeCurrency(player, "Gems", args[3])
	end

	return `unknown command "{command}"\n{HELP}`
end

function DebugService:Init()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "WildRanchDebug"
	bindable.OnInvoke = function(commandLine: string)
		local ok, result = pcall(run, tostring(commandLine))
		return if ok then result else `error: {result}`
	end
	bindable.Parent = ServerStorage
	print('[DebugService] Ready: print(game.ServerStorage.WildRanchDebug:Invoke("help"))')
end

return DebugService

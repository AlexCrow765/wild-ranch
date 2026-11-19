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
  gems <player> <amount>        (negative to spend)]]

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

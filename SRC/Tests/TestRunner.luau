--!strict
--[[
	TestRunner
	Tiny test framework. Runs every ModuleScript in Specs/ (files named *.spec.luau).
	Lives in ServerStorage, so it never ships to players.

	Run in Studio while playing (Server command bar):
	  print(game.ServerStorage.WildRanchDebug:Invoke("test"))

	A spec module returns function(t) and uses:
	  t.test(name, fn)              one test
	  t.eq(actual, expected, msg?)  exact equality
	  t.near(actual, expected, tolerance, msg?)
	  t.truthy(value, msg?)
	  t.errors(fn, contains?)       fn must error (optionally with text containing `contains`)
]]

local TestRunner = {}

local function fail(message: string)
	error(message, 3)
end

local function makeApi(results: { passed: number, failed: { string } }, specName: string)
	local t = {}

	function t.test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			results.passed += 1
		else
			table.insert(results.failed, `{specName} > {name}: {err}`)
		end
	end

	function t.eq(actual: any, expected: any, msg: string?)
		if actual ~= expected then
			fail(`{msg or "eq"}: expected {tostring(expected)}, got {tostring(actual)}`)
		end
	end

	function t.near(actual: number, expected: number, tolerance: number, msg: string?)
		if typeof(actual) ~= "number" or math.abs(actual - expected) > tolerance then
			fail(`{msg or "near"}: expected {expected} +/- {tolerance}, got {tostring(actual)}`)
		end
	end

	function t.truthy(value: any, msg: string?)
		if not value then
			fail(msg or "expected a truthy value")
		end
	end

	function t.errors(fn: () -> (), contains: string?)
		local ok, err = pcall(fn)
		if ok then
			fail("expected an error, but none was raised")
		end
		if contains and not string.find(tostring(err), contains, 1, true) then
			fail(`error did not contain "{contains}": {tostring(err)}`)
		end
	end

	return t
end

function TestRunner.Run(): string
	local results = { passed = 0, failed = {} :: { string } }
	local started = os.clock()

	local specs = script.Parent:WaitForChild("Specs"):GetChildren()
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)

	for _, spec in specs do
		if spec:IsA("ModuleScript") then
			local ok, specFn = pcall(require, spec)
			if not ok or typeof(specFn) ~= "function" then
				table.insert(results.failed, `{spec.Name}: failed to load ({tostring(specFn)})`)
			else
				local ran, err = pcall(specFn, makeApi(results, spec.Name))
				if not ran then
					table.insert(results.failed, `{spec.Name}: crashed: {err}`)
				end
			end
		end
	end

	local lines = {
		`Tests: {results.passed} passed, {#results.failed} failed ({string.format("%.2f", os.clock() - started)}s)`,
	}
	for _, failure in results.failed do
		table.insert(lines, "  FAIL " .. failure)
	end
	return table.concat(lines, "\n")
end

return TestRunner

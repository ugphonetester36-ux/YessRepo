-- Check for table that is shared between executions.
if not shared then
	return warn("No shared, no script.")
end

loadstring("getfenv().LPH_NO_VIRTUALIZE = function(...) return ... end")()

if shared.AcProbe then
	shared.AcProbe.detach()
end

local AcProbe = { connections = {} }

-- Services.
local scriptContext = cloneref(game:GetService("ScriptContext"))
local playersService = cloneref(game:GetService("Players"))
local localPlayer = playersService.LocalPlayer

-- Constants.
local SIGNALS = {
	{ Name = "ScriptContext.Error", Signal = scriptContext.Error },
	{ Name = "game.DescendantAdded", Signal = game.DescendantAdded },
	{ Name = "LocalPlayer.Idled", Signal = localPlayer.Idled },
}

---Print the real ForeignState/Enabled flags for every connection on a signal,
---since those flags are the actual test, not whether a name could be resolved.
local function dumpConnections(label, signal)
	local ok, connections = pcall(getconnections, signal)
	if not ok then
		warn("[AcProbe] Could not read connections for " .. label)
		return
	end

	print(string.format("[AcProbe] %s has %d connection(s)", label, #connections))
	for index, connection in ipairs(connections) do
		print(string.format(
			"  #%d ForeignState=%s LuaConnection=%s Enabled=%s Function=%s",
			index,
			tostring(connection.ForeignState),
			tostring(connection.LuaConnection),
			tostring(connection.Enabled),
			connection.Function ~= nil and "known" or "hidden"
		))
	end
end

---Ask an Actor's Lua state to report back over a BindableEvent.
---@param actor Instance
local function probeActor(actor)
	local ok, id, event = pcall(create_comm_channel)
	if not ok then
		warn("[AcProbe] No comm channel support here.")
		return
	end

	local connection
	connection = event.Event:Connect(function(result)
		print("[AcProbe] Actor " .. actor:GetFullName() .. " reports: " .. tostring(result))
		connection:Disconnect()
	end)

	table.insert(AcProbe.connections, connection)

	local code = string.format([[
		local ok, scripts = pcall(getrunningscripts)
		local names = {}
		if ok then
			for i = 1, math.min(#scripts, 8) do
				table.insert(names, scripts[i].Name)
			end
		end
		local channel = get_comm_channel(%d)
		if channel then
			channel:Fire(string.format("%%d scripts, first few: %%s", ok and #scripts or -1, table.concat(names, ", ")))
		end
	]], id)

	pcall(run_on_actor, actor, code)
end

local function run()
	for _, entry in ipairs(SIGNALS) do
		dumpConnections(entry.Name, entry.Signal)
	end

	local actorsOk, actors = pcall(getactors)
	if actorsOk then
		print(string.format("[AcProbe] %d live actor(s)", #actors))
		for _, actor in ipairs(actors) do
			print("  " .. actor:GetFullName())
			probeActor(actor)
		end
	end

	local deletedOk, deleted = pcall(getdeletedactors)
	if deletedOk then
		print(string.format("[AcProbe] %d deleted-but-accessible actor(s)", #deleted))
		for _, actor in ipairs(deleted) do
			print("  " .. tostring(actor))
			probeActor(actor)
		end
	end

	local threadsOk, threads = pcall(getallthreads)
	if threadsOk then
		local foreign = 0
		for _, thread in ipairs(threads) do
			local isOursOk, isOurs = pcall(isourthread, thread)
			if isOursOk and not isOurs then
				foreign += 1
			end
		end

		print(string.format("[AcProbe] %d total threads, %d not ours", #threads, foreign))
	end
end

function AcProbe.detach()
	for _, connection in ipairs(AcProbe.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	shared.AcProbe = nil
end

shared.AcProbe = AcProbe
local ok, err = xpcall(run, debug.traceback)
if not ok then
	warn("[AcProbe] Error: " .. tostring(err))
end

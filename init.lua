--!strict
--@author: vynx777
--@description: [
--	Namespace-based networking layer built on top of RemoteEvent and RemoteFunction.
--	Routes all communication through a single remote per namespace via dispatch tables,
--	eliminating stacked connections. Exposes .on() .send() .push() per namespace.
--	Includes a built-in ServiceBridge for server-to-server communication via Networker.bridge
--]

-- Services:
local RunService = game:GetService("RunService")

-- Structure:
local Networker = {}

-- Variables:
local remotesFolder: Folder

-- Types:
export type Networker = typeof(Networker)

export type sendOptions = {
	TwoWay: boolean?,
}

export type SendBuilder = {
	Options: (options: sendOptions) -> (),
}

-- Diffrent Callback types so that the .on function is satisfied and doesnt return a TypeError
type ServerCallback = (player: Player, data: { any }?) -> any?
type ClientCallback = (data: { any }?) -> ()
type AnyCallback = ServerCallback | ClientCallback

-- >> SERVICE BRIDGE TYPES
-- kept here so they dont leak into the rest of the module
type BridgeCallback = (...any) -> any?
type ServiceRegistry = { [string]: { [string]: BridgeCallback } }

-- Initialization:
local found = script:FindFirstChild("_remotes")

-- found could be nil after the first check
if not found and RunService:IsServer() then
	local _remotesFolder = Instance.new("Folder")
	_remotesFolder.Name = "_remotes"
	_remotesFolder.Parent = script
	remotesFolder = _remotesFolder
else
	-- remotesFolder cannot be nil after WaitForChild, if nil then something went wrong
	remotesFolder = script:WaitForChild("_remotes") :: Folder
end

-- Functionality:
function Networker.set(namespace: string)
	local _networker = {}

	-- Dispatch tables
	local _serverEventCallbacks: { [string]: (player: Player, data: { any }?) -> () } = {}
	local _serverFnCallbacks: { [string]: (player: Player, data: { any }?) -> any? } = {}
	local _clientEventCallbacks: { [string]: (data: { any }?) -> () } = {}

	-- Remotes
	local NamespaceFolder: Folder
	local NamespaceEvent: RemoteEvent
	local NamespaceFunction: RemoteFunction

	-- Setup remotes
	if RunService:IsServer() then
		local existingFolder = remotesFolder:FindFirstChild(namespace)

		-- existingFolder could be nil
		if existingFolder and existingFolder:IsA("Folder") then
			NamespaceFolder = existingFolder
		else
			NamespaceFolder = Instance.new("Folder")
			NamespaceFolder.Name = namespace
			NamespaceFolder.Parent = remotesFolder
		end

		local existingEvent = NamespaceFolder:FindFirstChild("RemoteEvent")
		local existingFunc = NamespaceFolder:FindFirstChild("RemoteFunction")

		-- RemoteEvent and RemoteFunction could be nil
		if
			existingEvent
			and existingEvent:IsA("RemoteEvent")
			and existingFunc
			and existingFunc:IsA("RemoteFunction")
		then
			NamespaceEvent = existingEvent
			NamespaceFunction = existingFunc
		else
			NamespaceEvent, NamespaceFunction = Networker._createRemotes(NamespaceFolder)
		end

		-- REMOTE EVENT HANDLER
		NamespaceEvent.OnServerEvent:Connect(function(player: Player, actionName: string, data: { any }?)
			local fn = _serverEventCallbacks[actionName]
			if fn then
				local success, err = pcall(function()
					fn(player, data)
				end)

				if not success then
					error(`[Networker] '{namespace}:{actionName}' -> {err}`)
				end
			else
				warn(`[Networker] '{namespace}' received unhandled action: '{actionName}'`)
			end
		end)

		-- REMOTE FUNCTION HANDLER
		NamespaceFunction.OnServerInvoke = function(player: Player, actionName: string, data: { any }?): any?
			local fn = _serverFnCallbacks[actionName]
			if fn then
				local success, result = pcall(function()
					return fn(player, data)
				end)

				if not success then
					error(`[Networker] '{namespace}:{actionName}' -> {result}`)
				end

				return result
			else
				warn(`[Networker] '{namespace}' received unhandled invoke: '{actionName}'`)
				return nil
			end
		end
	else
		local folderResult = remotesFolder:WaitForChild(namespace, 5)
		assert(
			folderResult and folderResult:IsA("Folder"),
			`[Networker] Client timeout: Missing folder for namespace '{namespace}'`
		)
		NamespaceFolder = folderResult :: Folder

		local eventResult = NamespaceFolder:WaitForChild("RemoteEvent", 5)
		assert(
			eventResult and eventResult:IsA("RemoteEvent"),
			`[Networker] Client timeout: Missing RemoteEvent in '{namespace}'`
		)
		NamespaceEvent = eventResult :: RemoteEvent

		local funcResult = NamespaceFolder:WaitForChild("RemoteFunction", 5)
		assert(
			funcResult and funcResult:IsA("RemoteFunction"),
			`[Networker] Client timeout: Missing RemoteFunction in '{namespace}'`
		)
		NamespaceFunction = funcResult :: RemoteFunction

		-- REMOTE EVENT (CLIENT)
		NamespaceEvent.OnClientEvent:Connect(function(actionName: string, data: { any }?)
			local fn = _clientEventCallbacks[actionName]
			if fn then
				fn(data)
			else
				warn(`[Networker] '{namespace}' client received unhandled action: '{actionName}'`)
			end
		end)
	end

	-- exposed for external access if needed
	_networker._folder = NamespaceFolder
	_networker._event = NamespaceEvent
	_networker._function = NamespaceFunction

	-- Client to server communication [[ Client -> Server ]] can be TwoWay or OneWay, if TwoWay == true
	function _networker.send(actionName: string, data: { any }?, options: sendOptions?): any?
		assert(not RunService:IsServer(), "[Networker] .send() can only be called from the client")

		local twoWay: boolean = type(options) == "table" and options.TwoWay == true

		if twoWay then
			local success, result = pcall(function()
				return NamespaceFunction:InvokeServer(actionName, data)
			end)

			if success then
				return result
			else
				error(`[Networker] '{namespace}:{actionName}' -> {result}`)
			end
		end

		local success, err = pcall(function()
			NamespaceEvent:FireServer(actionName, data)
		end)

		if not success then
			error(`[Networker] '{namespace}:{actionName}' -> {err}`)
		end

		return nil
	end

	-- Server to Client communication [[ Server -> Client ]] cannot be TwoWay, always OneWay for safety and performance
	function _networker.push(actionName: string, target: Player | { Player } | "all", data: { any }?)
		assert(RunService:IsServer(), "[Networker] .push() can only be called from the server")

		if target == "all" then
			local success, err = pcall(function()
				NamespaceEvent:FireAllClients(actionName, data)
			end)

			if not success then
				error(`[Networker] '{namespace}:{actionName}' -> {err}`)
			end
		elseif typeof(target) == "Instance" and target:IsA("Player") then
			local success, err = pcall(function()
				NamespaceEvent:FireClient(target, actionName, data)
			end)

			if not success then
				error(`[Networker] '{namespace}:{actionName}' -> {err}`)
			end
		elseif type(target) == "table" then
			for _, player in target do
				local success, err = pcall(function()
					NamespaceEvent:FireClient(player, actionName, data)
				end)

				if not success then
					error(`[Networker] '{namespace}:{actionName}' -> {err}`)
				end
			end
		end
	end

	-- General Data reciving function, for both Client and Server
	function _networker.on(actionName: string, fn: AnyCallback, options: sendOptions?): nil
		local twoWay: boolean = type(options) == "table" and options.TwoWay == true

		if RunService:IsServer() then
			if twoWay then
				assert(
					not _serverFnCallbacks[actionName],
					`[Networker] '{namespace}:{actionName}' TwoWay handler already registered`
				)
				_serverFnCallbacks[actionName] = fn :: ServerCallback
			else
				assert(
					not _serverEventCallbacks[actionName],
					`[Networker] '{namespace}:{actionName}' handler already registered`
				)
				_serverEventCallbacks[actionName] = fn :: ServerCallback
			end
		else
			assert(
				not _clientEventCallbacks[actionName],
				`[Networker] '{namespace}:{actionName}' client handler already registered`
			)
			_clientEventCallbacks[actionName] = fn :: ClientCallback
		end

		return nil
	end

	return _networker
end

-- little helper function that is here to not make a mess creating remotes
function Networker._createRemotes(folder: Folder)
	local RemoteEvent: RemoteEvent, RemoteFunction: RemoteFunction =
		Instance.new("RemoteEvent"), Instance.new("RemoteFunction")

	RemoteEvent.Name = "RemoteEvent"
	RemoteFunction.Name = "RemoteFunction"
	RemoteEvent.Parent = folder
	RemoteFunction.Parent = folder

	return RemoteEvent, RemoteFunction
end

-- >> SERVICE BRIDGE
-- server-only communication layer between services
-- prevents cross-namespace client dependencies by keeping inter-service calls on the server
-- each service registers its handlers via .bridge.on(), other services call them via .bridge.fire() or .bridge.invoke()
do
	local _registry: ServiceRegistry = {}

	Networker.bridge = {}

	-- helper that returns the action handler or throws a clear error
	local function getHandler(serviceName: string, actionName: string): BridgeCallback
		local service = _registry[serviceName]
		assert(service, `[ServiceBridge] '{serviceName}' has no registered handlers`)

		local fn = service[actionName]
		assert(fn, `[ServiceBridge] '{serviceName}:{actionName}' handler not found`)

		return fn
	end

	-- register a handler for an action on a service
	-- duplicate registrations throw immediately so you catch naming conflicts early
	function Networker.bridge.on(serviceName: string, actionName: string, fn: BridgeCallback): nil
		assert(RunService:IsServer(), "[ServiceBridge] .on() can only be called from the server")

		if not _registry[serviceName] then
			_registry[serviceName] = {}
		end

		assert(
			not _registry[serviceName][actionName],
			`[ServiceBridge] '{serviceName}:{actionName}' handler already registered`
		)

		_registry[serviceName][actionName] = fn
		return nil
	end

	-- fire a one-way action on a service, no return value expected
	function Networker.bridge.fire(serviceName: string, actionName: string, ...: any): nil
		assert(RunService:IsServer(), "[ServiceBridge] .fire() can only be called from the server")

		local fn = getHandler(serviceName, actionName)
		local success, err = pcall(fn, ...)

		if not success then
			error(`[ServiceBridge] '{serviceName}:{actionName}' -> {err}`)
		end

		return nil
	end

	-- invoke a two-way action on a service and return its result
	-- use this when you need a response e.g. checking if inventory has space before adding an item
	function Networker.bridge.invoke(serviceName: string, actionName: string, ...: any): any?
		assert(RunService:IsServer(), "[ServiceBridge] .invoke() can only be called from the server")

		local fn = getHandler(serviceName, actionName)
		local success, result = pcall(fn, ...)

		if not success then
			error(`[ServiceBridge] '{serviceName}:{actionName}' -> {result}`)
		end

		return result
	end
end

return Networker :: Networker

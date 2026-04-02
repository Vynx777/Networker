--!strict
-- author: vynxz777

-- Services:

local RunService = game:GetService("RunService")

-- Packages:

local Promise = require(script.Parent.Packages.Promise)

-- Constants:

local REMOTES_FOLDER_NAME = "_remotes"
local INVOKE_CLIENT_TIMEOUT = 10

-- Variables:

local RemotesFolder: Folder
local InitializedClientNamespaces: { [string]: boolean } = {}
local InitializedServerNamespaces: { [string]: boolean } = {}

if RunService:IsServer() then
	local folder = script:FindFirstChild(REMOTES_FOLDER_NAME)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = script
	end

	RemotesFolder = folder
else
	RemotesFolder = script:WaitForChild(REMOTES_FOLDER_NAME) :: Folder
end

-- Structure:

local Networker = {
	client = {},
	server = {},
}

-- Functionality:

--@_mapMethods
--@private
local function _mapMethods(methods: { [any]: any }): { [string]: any }
	local mappedMethods: { [string]: any } = {}

	for key, method in pairs(methods) do
		if type(method) ~= "function" then
			continue
		end

		if type(key) == "string" then
			mappedMethods[key] = method
		else
			warn(`Networker: skipping non-string method key '{tostring(key)}' — only string keys are supported.`)
		end
	end

	return mappedMethods
end

--@_validateActionName
--@private
local function _validateActionName(actionName: any): boolean
	return type(actionName) == "string" and #actionName > 0
end

--@_getRemotes
--@private
local function _getRemotes(namespace: string, isServer: boolean): (Folder, RemoteEvent, RemoteFunction)
	local namespaceFolder: Folder

	if isServer then
		local existingFolder = RemotesFolder:FindFirstChild(namespace)

		if existingFolder then
			namespaceFolder = existingFolder :: Folder
		else
			namespaceFolder = Instance.new("Folder")
			namespaceFolder.Name = namespace
			namespaceFolder.Parent = RemotesFolder
		end

		local remoteEvent = namespaceFolder:FindFirstChild("Event") :: RemoteEvent
		if not remoteEvent then
			remoteEvent = Instance.new("RemoteEvent")
			remoteEvent.Name = "Event"
			remoteEvent.Parent = namespaceFolder
		end

		local remoteFunction = namespaceFolder:FindFirstChild("Function") :: RemoteFunction
		if not remoteFunction then
			remoteFunction = Instance.new("RemoteFunction")
			remoteFunction.Name = "Function"
			remoteFunction.Parent = namespaceFolder
		end

		return namespaceFolder, remoteEvent, remoteFunction
	else
		namespaceFolder = RemotesFolder:WaitForChild(namespace) :: Folder
		local remoteEvent = namespaceFolder:WaitForChild("Event") :: RemoteEvent
		local remoteFunction = namespaceFolder:WaitForChild("Function") :: RemoteFunction

		return namespaceFolder, remoteEvent, remoteFunction
	end
end

--@_bindHandlers
--@private
local function _bindHandlers(
	isServer: boolean,
	event: RemoteEvent,
	func: RemoteFunction,
	context: any,
	methods: MethodsConfig?,
	connections: { RBXScriptConnection }
)
	if not methods then
		return
	end

	if methods.Events then
		local mappedEvents = _mapMethods(methods.Events)

		if isServer then
			local conn = event.OnServerEvent:Connect(function(player: Player, actionName: any, ...: any)
				if not _validateActionName(actionName) then
					warn(`Networker: invalid actionName from {player.Name} — must be a non-empty string.`)
					return
				end

				if mappedEvents[actionName] then
					mappedEvents[actionName](context, player, ...)
				else
					warn(`Networker: unknown server Event '{actionName}' fired by {player.Name}.`)
				end
			end)
			table.insert(connections, conn)
		else
			local conn = event.OnClientEvent:Connect(function(actionName: any, ...: any)
				if not _validateActionName(actionName) then
					warn(`Networker: invalid actionName received on client — must be a non-empty string.`)
					return
				end

				if mappedEvents[actionName] then
					mappedEvents[actionName](context, ...)
				else
					warn(`Networker: unknown client Event '{actionName}'.`)
				end
			end)
			table.insert(connections, conn)
		end
	end

	if methods.Functions then
		local mappedFunctions = _mapMethods(methods.Functions)

		if isServer then
			func.OnServerInvoke = function(player: Player, actionName: any, ...: any): any
				if not _validateActionName(actionName) then
					warn(`Networker: invalid actionName from {player.Name} in Function invoke.`)
					return nil
				end

				if mappedFunctions[actionName] then
					local success, result = pcall(mappedFunctions[actionName], context, player, ...)
					if success then
						return result
					else
						warn(`Networker: server Function '{actionName}' error: {tostring(result)}`)
						return nil
					end
				else
					warn(`Networker: unknown server Function '{actionName}' invoked by {player.Name}.`)
					return nil
				end
			end
		else
			func.OnClientInvoke = function(actionName: any, ...: any): any
				if not _validateActionName(actionName) then
					warn(`Networker: invalid actionName received on client in Function invoke.`)
					return nil
				end

				if mappedFunctions[actionName] then
					local success, result = pcall(mappedFunctions[actionName], context, ...)
					if success then
						return result
					else
						warn(`Networker: client Function '{actionName}' error: {tostring(result)}`)
						return nil
					end
				else
					warn(`Networker: unknown client Function '{actionName}'.`)
					return nil
				end
			end
		end
	end
end

-- Client:

local NetworkerClient = Networker.client

--@NetworkerClient.new
--@public
--@return ClientInterface
function NetworkerClient.new(namespace: string, context: any, methods: MethodsConfig?): ClientInterface
	assert(not RunService:IsServer(), "Networker.client.new() can only be used on the client!")
	assert(type(namespace) == "string", "Namespace must be a string!")
	assert(type(context) == "table", "Context must be a table!")

	assert(not InitializedClientNamespaces[namespace], `Namespace '{namespace}' is already initialized on the client!`)
	InitializedClientNamespaces[namespace] = true

	local ClientInterface = {}
	local connections: { RBXScriptConnection } = {}

	local _, Event, Function = _getRemotes(namespace, false)

	_bindHandlers(false, Event, Function, context, methods, connections)

	function ClientInterface:FireServer(actionName: string, ...: any)
		assert(_validateActionName(actionName), "actionName must be a non-empty string!")
		Event:FireServer(actionName, ...)
	end

	function ClientInterface:InvokeServer(actionName: string, ...: any): any
		assert(_validateActionName(actionName), "actionName must be a non-empty string!")

		local args = table.pack(...)

		return Promise.new(function(resolve, reject)
			task.spawn(function()
				local success, result = pcall(function()
					return Function:InvokeServer(actionName, table.unpack(args, 1, args.n))
				end)

				if success then
					resolve(result)
				else
					reject(result)
				end
			end)
		end)
	end

	function ClientInterface:Destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		InitializedClientNamespaces[namespace] = nil
	end

	return ClientInterface :: ClientInterface
end

-- Server:

local NetworkerServer = Networker.server

--@NetworkerServer.new
--@public
--@return ServerInterface
function NetworkerServer.new(namespace: string, context: any, methods: MethodsConfig?): ServerInterface
	assert(RunService:IsServer(), "Networker.server.new() can only be used on the server!")
	assert(type(namespace) == "string", "Namespace must be a string!")
	assert(type(context) == "table", "Context must be a table!")

	assert(not InitializedServerNamespaces[namespace], `Namespace '{namespace}' is already initialized on the server!`)
	InitializedServerNamespaces[namespace] = true

	local ServerInterface = {}
	local connections: { RBXScriptConnection } = {}

	local namespaceFolder, Event, Function = _getRemotes(namespace, true)

	_bindHandlers(true, Event, Function, context, methods, connections)

	function ServerInterface:FireClient(player: Player, actionName: string, ...: any)
		assert(_validateActionName(actionName), "actionName must be a non-empty string!")
		Event:FireClient(player, actionName, ...)
	end

	function ServerInterface:FireAllClients(actionName: string, ...: any)
		assert(_validateActionName(actionName), "actionName must be a non-empty string!")
		Event:FireAllClients(actionName, ...)
	end

	function ServerInterface:InvokeClient(player: Player, actionName: string, ...: any): any
		assert(_validateActionName(actionName), "actionName must be a non-empty string!")

		local args = table.pack(...)

		return Promise.new(function(resolve, reject)
			local returned = false

			task.delay(INVOKE_CLIENT_TIMEOUT, function()
				if not returned then
					returned = true
					reject(
						`InvokeClient timed out after {INVOKE_CLIENT_TIMEOUT}s for action '{actionName}' on player '{player.Name}'`
					)
				end
			end)

			task.spawn(function()
				local success, result = pcall(function()
					return Function:InvokeClient(player, actionName, table.unpack(args, 1, args.n))
				end)

				if returned then
					return
				end

				returned = true

				if success then
					resolve(result)
				else
					reject(result)
				end
			end)
		end)
	end

	function ServerInterface:Destroy()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)

		Function.OnServerInvoke = function()
			return nil
		end

		namespaceFolder:Destroy()
		InitializedServerNamespaces[namespace] = nil
	end

	return ServerInterface :: ServerInterface
end

-- Types:

export type ClientInterface = {
	FireServer: (self: ClientInterface, actionName: string, ...any) -> (),
	InvokeServer: (self: ClientInterface, actionName: string, ...any) -> any,
	Destroy: (self: ClientInterface) -> (),
}

export type ServerInterface = {
	FireClient: (self: ServerInterface, player: Player, actionName: string, ...any) -> (),
	FireAllClients: (self: ServerInterface, actionName: string, ...any) -> (),
	InvokeClient: (self: ServerInterface, player: Player, actionName: string, ...any) -> any,
	Destroy: (self: ServerInterface) -> (),
}

export type MethodsConfig = {
	Events: { [string]: any }?,
	Functions: { [string]: any }?,
}

export type Networker = typeof(Networker)

return Networker :: Networker

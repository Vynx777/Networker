# Networker

A lightweight, namespace-based client–server networking module for Roblox, built on top of [Promise](https://eryn.io/roblox-lua-promise/). Wraps `RemoteEvent` and `RemoteFunction` into a clean, action-dispatched API with input validation, timeout protection, and full cleanup support.

---

## Features

- **Namespace isolation** — each feature area gets its own folder of remotes, keeping things organized and avoiding name collisions
- **Action dispatch** — a single remote pair per namespace routes to named handlers, no per-feature remote clutter
- **Promise-based invocations** — `InvokeServer` and `InvokeClient` return Promises instead of yielding raw threads
- **`InvokeClient` timeout** — server-to-client invocations reject automatically after a configurable timeout (default: 10s), preventing server thread hangs on disconnected clients
- **Input validation** — all `actionName` values from untrusted clients are validated before dispatch
- **Destroy support** — both interfaces expose a `:Destroy()` method for full cleanup of connections and remote instances

---

## Requirements

- [roblox-lua-promise](https://eryn.io/roblox-lua-promise/) available at `ReplicatedStorage.Packages.Promise`

---

## Installation

Place `Networker.luau` inside `ReplicatedStorage` (or wherever your shared modules live). Require it from both server and client scripts.

```lua
local Networker = require(game.ReplicatedStorage.Networker)
```

---

## Usage

### Server

```lua
-- ServerScriptService/ChatServer.server.lua
local Networker = require(game.ReplicatedStorage.Networker)

local ChatService = {}

local Net = Networker.server.new("Chat", ChatService, {
    Events = {
        onMessage = function(self, player, text)
            print(player.Name .. " says: " .. text)
            -- broadcast to all clients
            Net:FireAllClients("onMessage", player.Name, text)
        end,
    },
    Functions = {
        getHistory = function(self, player)
            return { "Hello!", "World!" } -- example history
        end,
    },
})
```

### Client

```lua
-- StarterPlayerScripts/ChatClient.client.lua
local Networker = require(game.ReplicatedStorage.Networker)

local ChatClient = {}

local Net = Networker.client.new("Chat", ChatClient, {
    Events = {
        onMessage = function(self, senderName, text)
            print("[Chat] " .. senderName .. ": " .. text)
        end,
    },
})

-- Fire an event to the server
Net:FireServer("onMessage", "Hey everyone!")

-- Invoke the server and handle the Promise
Net:InvokeServer("getHistory")
    :andThen(function(history)
        for _, msg in ipairs(history) do
            print("[History] " .. msg)
        end
    end)
    :catch(function(err)
        warn("Failed to fetch history:", err)
    end)
```

---

## API Reference

### `Networker.server.new(namespace, context, methods?)`

Creates a server-side interface for the given namespace. Must be called on the **server only**.

| Parameter   | Type            | Description                                      |
|-------------|-----------------|--------------------------------------------------|
| `namespace` | `string`        | Unique name for this remote group                |
| `context`   | `table`         | Passed as `self` to all handler functions        |
| `methods`   | `MethodsConfig?` | Table of `Events` and/or `Functions` to handle  |

Returns a `ServerInterface`.

---

### `Networker.client.new(namespace, context, methods?)`

Creates a client-side interface for the given namespace. Must be called on the **client only**.

| Parameter   | Type            | Description                                      |
|-------------|-----------------|--------------------------------------------------|
| `namespace` | `string`        | Must match the namespace used on the server      |
| `context`   | `table`         | Passed as `self` to all handler functions        |
| `methods`   | `MethodsConfig?` | Table of `Events` and/or `Functions` to handle  |

Returns a `ClientInterface`.

---

### `ServerInterface`

| Method | Description |
|--------|-------------|
| `:FireClient(player, actionName, ...)` | Fires a named event to a specific client |
| `:FireAllClients(actionName, ...)` | Fires a named event to all clients |
| `:InvokeClient(player, actionName, ...)` | Invokes a named function on a client; returns a Promise that rejects after `INVOKE_CLIENT_TIMEOUT` seconds |
| `:Destroy()` | Disconnects all handlers, removes remote instances, and frees the namespace |

---

### `ClientInterface`

| Method | Description |
|--------|-------------|
| `:FireServer(actionName, ...)` | Fires a named event to the server |
| `:InvokeServer(actionName, ...)` | Invokes a named function on the server; returns a Promise |
| `:Destroy()` | Disconnects all handlers and frees the namespace |

---

### `MethodsConfig`

```lua
type MethodsConfig = {
    Events: { [string]: (self: any, ...any) -> () }?,
    Functions: { [string]: (self: any, ...any) -> any }?,
}
```

All keys must be **strings**. Handler functions receive `context` as the first argument (`self`), followed by the player (server-side events/functions only), then any additional arguments.

---

## Configuration

At the top of `Networker.luau`:

```lua
local REMOTES_FOLDER_NAME = "_remotes"   -- folder name created under the module
local INVOKE_CLIENT_TIMEOUT = 10          -- seconds before InvokeClient rejects
```

---

## Notes

- Each namespace can only be initialized **once per side** (client or server). Attempting to initialize the same namespace twice will error.
- `actionName` values received from clients are validated — they must be non-empty strings. Invalid names are silently dropped with a warning.
- Numeric method keys in `MethodsConfig` are not supported and will be skipped with a warning. Use string keys only.
- `:InvokeClient()` should be used sparingly. Prefer `:FireClient()` + a client `:FireServer()` callback pattern for most server→client communication.
- Call `:Destroy()` when tearing down a namespace (e.g. at the end of a minigame round) to prevent connection leaks.

---

## License

MIT — see `LICENSE` for details.

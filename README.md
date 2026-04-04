# Networker
> Namespace-based networking layer for Roblox, built on top of `RemoteEvent` and `RemoteFunction`.

Instead of managing individual remotes per action, Networker routes all communication through a **single RemoteEvent and RemoteFunction per namespace** using internal dispatch tables — keeping your remote hierarchy clean and eliminating stacked connections.

---

## Installation

**Via Wally:**
```toml
[dependencies]
Networker = "vynx777/networker@1.0.0"
```

**Manual:**
Place the module in `ReplicatedStorage` and require it from any script.

---

## Core Concepts

Each namespace exposes three methods:

| Method | Side | Description |
|--------|------|-------------|
| `.on()` | Server / Client | Register a handler for an action |
| `.send()` | Client only | Send an action to the server |
| `.push()` | Server only | Send an action to one or more clients |

Communication is always **one namespace, one RemoteEvent, one RemoteFunction** — no matter how many actions you register.

---

## API Reference

### `Networker.set(namespace: string)`
Creates or retrieves a networker instance for a given namespace.
```luau
local Networker = require(ReplicatedStorage.Networker)
local shopNet = Networker.set("shop")
```

---

### `.on(actionName, fn, options?)`
Registers a handler for an incoming action.

```luau
-- Server: receives player + data
shopNet.on("buyItem", function(player: Player, data: { any }?)
    print(player.Name, "wants to buy", data.itemId)
end)

-- Server TwoWay: must return a value
shopNet.on("getItemPrice", function(player: Player, data: { any }?)
    return 100
end, { TwoWay = true })

-- Client: receives data only
shopNet.on("updateShop", function(data: { any }?)
    print("Shop updated:", data)
end)
```

> ⚠️ Registering the same `actionName` twice in the same namespace will throw an error.

---

### `.send(actionName, data?, options?)`
Sends an action from the **client to the server**.

```luau
-- One-way: fire and forget
shopNet.send("buyItem", { itemId = "pet_egg" })

-- Two-way: waits for server response
local price = shopNet.send("getItemPrice", { itemId = "pet_egg" }, { TwoWay = true })
print("Price is:", price)
```

---

### `.push(actionName, target, data?)`
Sends an action from the **server to one or more clients**.

```luau
-- Single player
shopNet.push("updateShop", player, { items = {} })

-- List of players
shopNet.push("updateShop", { player1, player2 }, { items = {} })

-- Everyone
shopNet.push("updateShop", "all", { items = {} })
```

---

## Usage Example

### Server
```luau
-- ServerScriptService/ShopServer.luau
local Networker = require(ReplicatedStorage.Networker)

local shopNet = Networker.set("shop")

local PRICES = {
    pet_egg = 100,
    speed_upgrade = 250,
}

-- Player wants to buy something
shopNet.on("buyItem", function(player: Player, data: { any }?)
    local itemId = data.itemId
    local price = PRICES[itemId]

    if not price then
        warn("Unknown item:", itemId)
        return
    end

    -- deduct coins, give item...

    -- notify the client
    shopNet.push("purchaseSuccess", player, { itemId = itemId })
end)

-- Player asks for price
shopNet.on("getItemPrice", function(player: Player, data: { any }?)
    return PRICES[data.itemId] or 0
end, { TwoWay = true })
```

### Client
```luau
-- StarterPlayerScripts/ShopClient.luau
local Networker = require(ReplicatedStorage.Networker)

local shopNet = Networker.set("shop")

-- Ask server for price before buying
local price = shopNet.send("getItemPrice", { itemId = "pet_egg" }, { TwoWay = true })
print("Pet Egg costs:", price)

-- Buy the item
shopNet.send("buyItem", { itemId = "pet_egg" })

-- Listen for confirmation
shopNet.on("purchaseSuccess", function(data: { any }?)
    print("Successfully bought:", data.itemId)
end)
```

---

## Action Naming Convention

| Pattern | Direction | Type | Example |
|---------|-----------|------|---------|
| `verbNoun` | Client → Server | One-way | `buyItem` `equipPet` `feedBrainrot` |
| `verbNoun` | Server → Client | One-way | `updateCoins` `syncInventory` |
| `getX` `checkX` `fetchX` | Client → Server | Two-way | `getItemPrice` `checkInventorySpace` |

---

## Architecture

```
Client                        Server
  │                             │
  │── shopNet.send("buyItem") ──►│
  │                             │── _serverEventCallbacks["buyItem"](player, data)
  │                             │
  │◄── shopNet.push("updateShop", player) ──│
  │── _clientEventCallbacks["updateShop"](data)
  │                             │
  │── shopNet.send("getPrice", _, {TwoWay=true}) ──►│
  │◄────────────── return 100 ──│
```

**Under the hood — one namespace, one remote:**
```
ReplicatedStorage/
  Networker/
    _remotes/
      shop/
        RemoteEvent      ← handles all one-way actions for "shop"
        RemoteFunction   ← handles all two-way actions for "shop"
      inventory/
        RemoteEvent
        RemoteFunction
```

---

## Server-to-Server Communication

Networker handles **client ↔ server** communication only. For server-to-server (service-to-service) communication, use a separate `ServiceBridge` module:

```luau
-- InventoryServer registers a handler
ServiceBridge.on("InventoryService", "addItem", function(player, itemId)
    -- add item to inventory
end)

-- ShopServer calls it after a purchase
ServiceBridge.fire("InventoryService", "addItem", player, "pet_egg")
```

> Each service communicates **only with its own client namespace**. Cross-namespace client communication is an anti-pattern — it creates hidden dependencies that are hard to debug.

---

## Error Handling

All remote calls are wrapped in `pcall`. Errors are propagated with full context:

```
[Networker] 'shop:buyItem' -> attempt to index nil value 'itemId'
```

Unhandled actions produce a warning instead of a silent failure:
```
[Networker] 'shop' received unhandled action: 'unknownAction'
```

---

## License
MIT — free to use in any Roblox project.

---

*Made by vynx777*
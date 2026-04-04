# Networker
> Namespace-based networking layer for Roblox, built on top of `RemoteEvent` and `RemoteFunction`.

Instead of managing individual remotes per action, Networker routes all communication through a **single RemoteEvent and RemoteFunction per namespace** using internal dispatch tables — keeping your remote hierarchy clean and eliminating stacked connections.

Includes a built-in **ServiceBridge** for server-to-server communication between services, without cross-namespace client dependencies.

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

For server-to-server communication, use the built-in **ServiceBridge** via `Networker.bridge`.

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

## ServiceBridge

ServiceBridge is a **server-only** communication layer between services. Instead of having clients listen to foreign namespaces, all inter-service communication stays on the server.

### Why it exists

```luau
-- ❌ Wrong: InventoryClient secretly listening to shop namespace
local shopNet = Networker.set("shop")
shopNet.on("itemBought", function(data) end)  -- hidden dependency

-- ✅ Correct: ShopServer talks directly to InventoryServer via bridge
Networker.bridge.fire("InventoryService", "addItem", player, itemId)
```

### `Networker.bridge.on(serviceName, actionName, fn)`
Registers a handler on a service. Other services can call it via `.fire()` or `.invoke()`.

```luau
Networker.bridge.on("InventoryService", "addItem", function(player: Player, itemId: string)
    -- add item to inventory
end)

Networker.bridge.on("InventoryService", "hasSpace", function(player: Player): boolean
    return #getInventory(player) < MAX_SLOTS
end)
```

### `Networker.bridge.fire(serviceName, actionName, ...)`
Calls a one-way action on a service. No return value expected.

```luau
Networker.bridge.fire("InventoryService", "addItem", player, "pet_egg")
```

### `Networker.bridge.invoke(serviceName, actionName, ...)`
Calls a two-way action on a service and waits for its return value.

```luau
local hasSpace = Networker.bridge.invoke("InventoryService", "hasSpace", player)
if hasSpace then
    Networker.bridge.fire("InventoryService", "addItem", player, "pet_egg")
end
```

> ⚠️ All bridge methods are server-only. Calling them from the client will throw an error.

---

## Full Example

### Server
```luau
-- ServerScriptService/ShopServer.luau
local Networker = require(ReplicatedStorage.Networker)

local shopNet = Networker.set("shop")

local PRICES = {
    pet_egg = 100,
    speed_upgrade = 250,
}

-- player asks for price
shopNet.on("getItemPrice", function(player: Player, data: { any }?)
    return PRICES[data.itemId] or 0
end, { TwoWay = true })

-- player wants to buy something
shopNet.on("buyItem", function(player: Player, data: { any }?)
    local itemId = data.itemId
    local price = PRICES[itemId]

    if not price then
        warn("Unknown item:", itemId)
        return
    end

    -- check inventory space before doing anything
    local hasSpace = Networker.bridge.invoke("InventoryService", "hasSpace", player)
    if not hasSpace then
        shopNet.push("purchaseFailed", player, { reason = "Inventory full" })
        return
    end

    -- tell InventoryServer to add the item
    Networker.bridge.fire("InventoryService", "addItem", player, itemId)

    -- tell EconomyServer to deduct coins
    Networker.bridge.fire("EconomyService", "deductCoins", player, price)

    -- notify the client
    shopNet.push("purchaseSuccess", player, { itemId = itemId })
end)
```

```luau
-- ServerScriptService/InventoryServer.luau
local Networker = require(ReplicatedStorage.Networker)

local inventoryNet = Networker.set("inventory")

-- register handlers for other services to call
Networker.bridge.on("InventoryService", "hasSpace", function(player: Player): boolean
    return #getInventory(player) < MAX_SLOTS
end)

Networker.bridge.on("InventoryService", "addItem", function(player: Player, itemId: string)
    addToInventory(player, itemId)

    -- notify only THIS service's own client
    inventoryNet.push("syncInventory", player, { slots = getInventory(player) })
end)
```

### Client
```luau
-- StarterPlayerScripts/ShopClient.luau
local Networker = require(ReplicatedStorage.Networker)

local shopNet = Networker.set("shop")

local price = shopNet.send("getItemPrice", { itemId = "pet_egg" }, { TwoWay = true })
print("Pet Egg costs:", price)

shopNet.send("buyItem", { itemId = "pet_egg" })

shopNet.on("purchaseSuccess", function(data: { any }?)
    print("Successfully bought:", data.itemId)
end)

shopNet.on("purchaseFailed", function(data: { any }?)
    print("Purchase failed:", data.reason)
end)
```

```luau
-- StarterPlayerScripts/InventoryClient.luau
local Networker = require(ReplicatedStorage.Networker)

local inventoryNet = Networker.set("inventory")

-- only ever listens to its own namespace
inventoryNet.on("syncInventory", function(data: { any }?)
    updateInventoryUI(data.slots)
end)
```

---

## Architecture

```
Client                          Server
  │                               │
  │── shopNet.send("buyItem") ───►│
  │                               │── ShopServer handles it
  │                               │       │
  │                               │   bridge.invoke("InventoryService", "hasSpace")
  │                               │       │
  │                               │   InventoryServer returns true/false
  │                               │       │
  │                               │   bridge.fire("InventoryService", "addItem")
  │                               │       │
  │                               │   InventoryServer adds item
  │                               │       │
  │◄── inventoryNet ("syncInventory") ────┘
  │◄── shopNet ("purchaseSuccess") ───────┘
```

**One namespace, one remote:**
```
ReplicatedStorage/
  Networker/
    _remotes/
      shop/
        RemoteEvent      ← all one-way actions for "shop"
        RemoteFunction   ← all two-way actions for "shop"
      inventory/
        RemoteEvent
        RemoteFunction
```

---

## Action Naming Convention

| Pattern | Direction | Type | Example |
|---------|-----------|------|---------|
| `verbNoun` | Client → Server | One-way | `buyItem` `equipPet` `feedBrainrot` |
| `verbNoun` | Server → Client | One-way | `updateCoins` `syncInventory` |
| `getX` `checkX` `fetchX` | Client → Server | Two-way | `getItemPrice` `checkInventorySpace` |
| `verbNoun` | bridge `.fire()` | One-way | `addItem` `deductCoins` |
| `hasX` `checkX` `getX` | bridge `.invoke()` | Two-way | `hasSpace` `getLevel` |

---

## Error Handling

All remote calls are wrapped in `pcall`. Errors propagate with full context:

```
[Networker] 'shop:buyItem' -> attempt to index nil value 'itemId'
[ServiceBridge] 'InventoryService:addItem' -> attempt to index nil value 'player'
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

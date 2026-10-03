# Cosmic Café

A Roblox incremental / tycoon game: run a café for aliens, from a street stall
to a black hole bistro. This repo is **all code and data**; maps are built in
Studio and found at runtime through CollectionService tags (see
[`docs/MAP_CONTRACT.md`](docs/MAP_CONTRACT.md)). On an empty baseplate the game
generates placeholder cafés, so it is always playable.

## Setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in the repo:
   ```sh
   rokit install        # rojo, selene, stylua, lune, luau-lsp (pinned in rokit.toml)
   ```
2. Install the Rojo Studio plugin (`rojo plugin install`, or from the Creator Store).
3. Serve the project and connect from Studio (Plugins → Rojo → Connect):
   ```sh
   rojo serve
   ```
   Rojo only syncs `ReplicatedStorage.Shared`, `ServerScriptService.Server` and
   `StarterPlayerScripts.Client`; your Workspace/map is never touched.
4. Press Play. Without *Game Settings → Security → Enable Studio Access to API
   Services*, saves use an in-memory store (a warning says so) and nothing persists.

Build a place file without Studio: `rojo build -o CosmicCafe.rbxl`.

### Checks (run before every commit)

```sh
./scripts/check.sh            # stylua --check, selene, luau-lsp strict typecheck, Lune tests
lune run tests/run            # just the tests
./scripts/typecheck.sh        # just the strict type check
lune run scripts/simulate     # pacing report (see below)
```

## Pacing simulator

`lune run scripts/simulate [hours] [--all]` plays the game with a greedy bot for
3 hours (default) using **the same `Progression`/`Stats` code as the server** and
prints every unlock, income snapshots, the longest dry spell and a target table:

```
[PASS] First sale < 30s                       0:00:10
[PASS] Upgrade every 20-40s in first 5 min    16 goals (115 +1 buys), avg gap 19s, longest 47s
[PASS] First staff hire ~2 min                0:01:47
[PASS] World 2 at 30-60 min                   0:33:38
[PASS] First Franchise at 1.5-2h              1:37:31 for 15 Star Chefs
[PASS] Second run ~2x faster (World 2)        0:33:38 vs 0:13:43 = 2.5x
[PASS] Second run ~2x faster (Franchise)      1:37:31 vs 0:53:10 = 1.8x
```

The bot's assumptions (manual efficiency, average tip streak, how long it waits
for a payback, when it franchises) are in `Economy.sim`. `tests/Pacing.spec.luau`
fails if a change pushes the game outside the targets.

"Upgrade" in the cadence target means a *goal* the next-unlock bar points at: a
new dish, a hire, a world, a x2 milestone or every 10th dish level. With 1.07
cost growth single +1 level buys are much more frequent than that (115 in the
first 5 minutes) — that's the normal feel of the curve.

## Architecture

```
src/shared  -> ReplicatedStorage.Shared   (config + pure logic, used by server, client and Lune)
  Config/     Worlds, Dishes (+milestones, ingredients, recipes), Customers, Staff,
              Economy (every tuning number), Franchise tree, Monetization stubs,
              Map (tags + placeholder layout), Sounds, DataTemplate (save shape)
  Util/       BigNum (1.2K ... 1Ce, mantissa/exponent past 1e308), Formula (pure math),
              Stats (derived numbers from a save), Progression (every state change as
              a pure function), Validate, RateLimiter, Signal, TableUtil
  Net.luau    every RemoteEvent + its rate limit
  Types.luau  Profile / Context types
src/server  -> ServerScriptService.Server
  init.server.luau   creates remotes, init()+start() services in order, then loads players
  Services/          Data, Monetization, State, World, Economy, Codex, Cafe, Staff,
                     Offline, Daily, Prestige
  Mechanics/         per-world rules (Basic, Weather, FishOrders; Conveyor/TimeDilation stubs)
src/client  -> StarterPlayerScripts.Client
  Controllers/       State, Effects (toasts, coin pops, sounds, number tween), HUD, Popup,
                     Shop, Staff, Worlds (+weather visuals), Codex (+Lab), Daily, Franchise,
                     Store, WorldObjects (station/customer billboards)
  UI/                Theme, Builder, Window, Scale
tests/              Lune tests (lib/Loader.luau runs the Roblox-style modules from disk)
scripts/            simulate.luau (+lib/PacingSim.luau), check.sh, typecheck.sh
```

### How a frame of gameplay flows

1. **Server-authoritative.** The client only sends intents over `Net` remotes
   (`BuyDish`, `Hire`, `Travel`, ...). `Net.onServerEvent` rate-limits each remote
   per player; handlers validate every argument (`Util/Validate`) and then call a
   pure `Progression` function that checks the rules (money, unlocks, slots).
2. **Cafe loop** (`CafeService`, 10 Hz): stations cook into trays (tap the
   station's ProximityPrompt, or a Barista auto-cooks); aliens walk in, order a
   dish and wait; serving (tap them, or a Waiter) sells everything ready of that
   dish × species tip × your manual tip streak (up to 2.5x).
3. **Economy** (`EconomyService`, 1 Hz): Manager-run worlds earn in the
   background, Auto-Buy buys the best-payback level, play time and the offline
   timestamp tick.
4. **Replication** (`StateService`): the owner gets their whole save + Context
   (passes, weather). The client runs the same `Stats` module for every number it
   shows, so costs/rates in the UI always match the server.
5. **Saving** (`DataService`): ProfileStore-style session lock inside
   `UpdateAsync` (retry, then steal stale locks), lock verified on every save,
   staggered autosave, `BindToClose` flush, NaN/inf sanitizing, template
   reconcile for new fields.

### Systems

| System | Where | Notes |
| --- | --- | --- |
| Cost / income | `Formula.cost`, `Stats.dishValue` | cost = base × growth^level (1.07 in worlds 1-2, 1.12-1.15 from world 3). Value per serving = baseIncome × level. Milestones at 25/50/100/200 double cook speed. |
| Automation | `Stats` + `CafeService` | Barista (auto-cook) → Waiter (auto-serve) → World Manager (world runs while you're elsewhere) → Auto-Buy (Franchise tree) → Regional Director (offline from every world). |
| Staff | `StaffService`, `Config/Staff` | Common → Rare → Epic → Legendary → Cosmic; crates; fuse 3 identical into the next rarity. Rarity multiplies speed. |
| Customers | `Config/Customers` | 20 species with rarities and tips; 1/500 Golden Alien (50x tip + server announcement); daily Food Critic. |
| Recipes | `CodexService`, Lab window | combine 2-3 ingredients; discoveries give permanent bonuses; first on the server gets a badge. |
| Offline | `OfflineService` | 2h cap, +2/+4/+4h from the tree (12h max), +4h pass; 50% efficiency. |
| Franchise | `PrestigeService` | Star Chefs = floor(sqrt(lifetime / 6e7)); +6% income each; spend them on the tree. Keeps codex, staff, recipes. |
| Retention | `DailyService`, HUD | login streak (48h grace), daily critic, always-visible next-unlock bar, welcome-back popup. |
| Worlds | `WorldService`, `Mechanics/` | Street Stall (basic), Cloud City (server-wide weather rushes: rain → hot dishes 3x, sun → cold dishes 3x). Worlds 3-5 are config stubs. |
| Monetization | `Config/Monetization`, `MonetizationService` | 2x Money, Auto-Serve, +Offline time, VIP decor — ids are 0 (stubs). No world is ever sold. |

### A note on "income growth ~1.10"

A per-level *multiplicative* income growth (1.10) above the cost growth (1.07)
would make every level cheaper relative to what it earns, so the economy runs
away. Income per level is therefore linear (`Economy.incomeLevelGrowth = 1.0`,
still a knob), and the "income growth" of the design is carried by the per-dish
ratios (each dish ~15x the cost, ~9x the income and 2x the cook time of the
previous one) and by milestones.

## How to add content

### A dish

1. Add an entry to the `list` in `src/shared/Config/Dishes.luau` (`id`, `world`,
   `baseCost`, `baseIncome`, `cookTime`, `tags`).
2. Add its id to the world's `dishes` list in `Config/Worlds.luau` (order = menu order).
3. Optional: a `Station` with `Dish = "<id>"` in your plots (otherwise generated).
4. `lune run scripts/simulate` and `lune run tests/run` (the config tests check ids).

### A customer species

1. Add an entry to `src/shared/Config/Customers.luau` (`rarity` is one of
   `Customers.rarityOrder`; `tipMultiplier` multiplies the dish value).
2. Add its id to a world's `customers` list. Legendary+ serves are announced.
   `tests/Config.spec.luau` currently expects 20 species — update it if you add more.

### A recipe

Add to `recipes` in `Config/Dishes.luau` with 2-3 ingredient ids and a bonus
(`{ dish = "...", valueMultiplier = 1.5 }` or `{ globalIncome = 0.05 }`).
New ingredients go in `Dishes.ingredients` (`world` = where it unlocks).

### A world

1. Add the world to `Config/Worlds.luau` (`index`, `unlockCost`, `costGrowth`,
   `priceScale`, `dishes`, `customers`, `mechanic`, `enabled = true`) and to
   `Worlds.order`.
2. Add its dishes and customers as above.
3. If it needs new behavior, create `src/server/Mechanics/<Name>.luau` with
   `orderWeight(dishId, ctx)` and `serveMultiplier(ordered, served)` and register
   it in `Mechanics/init.luau`; set the world's `mechanic` to that name. World-wide
   timed events (like weather) live in `WorldService`.
4. Build its area with `CafePlot (World=<id>)` plots, portals and gates — or let
   the game generate placeholders at `Map.placeholder.worldOrigin + worldSpacing * (index - 1)`.
5. Re-run the simulator; `Economy.sim` assumptions apply to every world.

Worlds 3-5 (Underwater, Moon Base, Black Hole) are already in the config with
`enabled = false`; Underwater's `FishOrders` mechanic is written but needs a
"serve a different dish" UI before the world is turned on.

### Monetization

Fill in `gamePassId`/`priceRobux` in `Config/Monetization.luau`. Badges
(`FirstDiscovery`, `GoldenAlien`, `FirstFranchise`) are awarded when their id
is non-zero. `Monetization.studioGrantsAll = true` grants every pass in Studio
for testing.

## Tooling notes

- Shared modules use instance requires (`require(script.Parent.X)`); the Lune
  loader in `tests/lib/Loader.luau` fakes `script` over the filesystem, so the
  same files run in Roblox and in tests.
- `selene` uses the `roblox` std (generated on first run; needs network).
- `scripts/typecheck.sh` downloads the Roblox type definitions for luau-lsp once
  into `~/.cache/cosmic-cafe`.

# Map contract

The code never finds map objects by name or path. Everything is discovered
through **CollectionService tags** and **Attributes**, so you can build, move,
rename and regroup the map freely in Studio. Anything missing is generated as a
simple placeholder at runtime, so an empty baseplate is still fully playable.

Tag names and placeholder sizes live in `src/shared/Config/Map.luau`.

> Add tags with Studio's **Tag Editor** (View → Tag Editor) or the Properties
> panel's *Tags* section. Add attributes in the Properties panel → *Attributes* → `+`.

## Tags

| Tag | Put it on | Required attributes | Optional attributes | Notes |
| --- | --- | --- | --- | --- |
| `CafePlot` | A `BasePart` (the floor) or a `Model` | `World` (string): a world id, e.g. `StreetStall` | `PlotId` (string) | One player's cafe in that world. Build one per player slot (= your server's max players); when every plot of a world is taken, extra plots are generated in a row next to the first one. The plot's **top surface** (a part) or **pivot** (a model) is the origin; **+Z (LookVector reversed) is the front** where customers come from. |
| `Station` | A `BasePart` or `Model` | `Dish` (string): a dish id, e.g. `Coffee` | `PlotId` | A cooking station. Gets a "Cook" ProximityPrompt and a billboard. One per dish per plot; missing ones are generated in a row at the back of the plot. |
| `Counter` | A `BasePart` or `Model` | – | `PlotId` | Fallback customer spots when a plot has no tables. Generated if missing. |
| `Table` | A `BasePart` or `Model` | – | `PlotId` | Each table is one customer spot; customers stand on its front side. Generated (6) if a plot has none. |
| `CustomerSpawn` | A `BasePart` (can be invisible) | – | `PlotId` | Where customers appear and leave to. Generated in front of the plot if missing. |
| `WorldPortal` | A `BasePart` or `Model` | `Target` (string): world id to travel to | – | Touching it travels to your plot in `Target` (if unlocked; otherwise shows the price). If no portal targets a world, a placeholder portal to it is generated in every world. |
| `UnlockGate` | A `BasePart` or `Model` (e.g. a door/barrier) | `World` (string): the world it guards | – | Gets an "Unlock" ProximityPrompt. Once *you* own the world it becomes non-collidable and see-through **for you only** (client side). Optional; none are generated. |

### How loose objects find their plot

`Station`, `Counter`, `Table` and `CustomerSpawn` belong to a plot by, in order:

1. being a **descendant** of the `CafePlot` model, or
2. having the same **`PlotId`** attribute as the plot, or
3. being the **nearest** plot within `Map.plotRadius` (150 studs). Stations
   only match plots of their dish's world.

The easiest setup is to group each cafe into a `Model`, tag the model
`CafePlot`, and put everything inside it.

## Ids

World ids (`Config/Worlds.luau`): `StreetStall`, `CloudCity`, `Underwater`,
`MoonBase`, `BlackHole` (worlds 3-5 are "coming soon" stubs).

Dish ids (`Config/Dishes.luau`):

| World | Dishes |
| --- | --- |
| `StreetStall` | `Coffee`, `Donut`, `HotDog`, `Pancakes`, `Burger` |
| `CloudCity` | `HotCocoa`, `BerrySmoothie`, `CloudTea`, `RainbowSundae`, `StormSoup` |
| `Underwater` | `KelpRoll`, `SeaFoamLatte`, `CoralCake` |
| `MoonBase` | `CraterCheese`, `MoonPie`, `RocketFries` |
| `BlackHole` | `QuantumNoodles`, `SingularitySoda`, `EventHorizonPie` |

## Attributes the game writes at runtime (don't set these yourself)

| On | Attribute | Meaning |
| --- | --- | --- |
| `CafePlot` | `OwnerUserId`, `OwnerName` | Who owns the plot this session (client draws the "<name>'s Cafe" sign). |
| `Station` part | `Level`, `Ready`, `TrayCapacity`, `Cooking`, `CookEnd`, `CookTime`, `Auto`, `OwnerUserId` | Read by the client billboard. |
| customer `Model` (tag `CafeCustomer`) | `Species`, `Order`, `Golden`, `Critic`, `Arrived`, `PatienceEnd`, `Leaving`, `OwnerUserId` | Read by the client order bubble. |
| `Workspace` | `Weather_<WorldId>`, `WeatherEnds_<WorldId>` | Current weather rush (`""` when calm). |

## Generated objects

Placeholders go into `Workspace.CosmicCafeGenerated`; customers into
`Workspace.CosmicCafeCustomers`. Generated plots for a world with no hand-built
plot are placed at `Map.placeholder.worldOrigin + worldSpacing * (worldIndex - 1)`,
so each world gets its own area. Tweak sizes/offsets in `Config/Map.luau`.

## Checklist for a new world area

1. Build the area. Tag each cafe floor `CafePlot` and set `World`.
2. Optionally add `Station`s (`Dish`), `Table`s, a `Counter`, a `CustomerSpawn`
   inside each plot model.
3. Add `WorldPortal`s (`Target`) between areas and an `UnlockGate` (`World`) if
   you want a physical barrier.
4. Press Play: missing pieces show up as colored placeholder blocks with labels.

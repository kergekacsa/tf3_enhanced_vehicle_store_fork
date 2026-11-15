# Enhanced Vehicle Store (private fork)

A private fork of the Transport Fever 3 mod [Enhanced Vehicle Store](https://mod.io/g/transportfever3/m/enhanced-vehicle-store). The fork is for personal use and is not published. The terms are in `CONTEXT.md`.

## Start point

The first commit of this repository is the original, version 1.3 (revision 4, mod.io item 6429112), without changes. `git diff <first commit>` shows every difference from the original.

## Differences from the original

| Area | Original | Fork |
|---|---|---|
| Mod ID and folder | `ethan_vehicle_helper_next` | `kacsa_enhanced_vehicle_store` |
| Saved settings key | `ethan_vehicle_helper` | `kacsa_enhanced_vehicle_store` |
| Weight column | Shown, hidden on airports | Removed. A Length column takes its place, hidden on airports |
| Power column | Shown | Removed |
| TE column | Shown | Removed |
| 0–top column | Road, water and air depots | Also the Multiple units tab |
| Noise, Pollution, Comfort | Only in the details | Three thin columns with an icon header and a grade from A to E. The tooltip of a grade shows the value of the vehicle and its rating in percent |
| Cargo filter | A vehicle shows when it carries any ticked type | A vehicle shows when it carries every ticked type |
| Cargo chips for groups | One chip, All cargo: vehicles that carry every cargo type | Two chips. Any cargo: vehicles that carry at least one cargo type. All cargo: vehicles that carry every cargo type |
| Bars of the computed numbers | From the lowest to the highest value shown | From zero to the highest value shown. Where lower is better, the bar is the lowest value shown as a share of the value |
| Window size | The game's fixed size for the kind of store: 1715 wide, 745 to 960 high | A share of the screen at every depot: 75 % of its width, but never narrower than the game's 1715, and 88 % of its height |
| Modify of several trains at once | The game's store | The fork's store, when all the trains have the same cars in the same order. The one train in the train panel stands for each of them, and every train keeps its own cars. Trains with different cars open the game's store |
| Click on a vehicle of the train panel | Nothing | Opens the details of that vehicle. A second click closes them |
| Specialization of a vehicle | Not shown | The game's coloured bubble before the vehicle name in the listing table, and in the details |
| Range filters | None | A Ranges panel with a From and a To slider for every column except the name |

Weight, power and tractive effort stay in the details of a vehicle. The engine filter still shows a vehicle that has any ticked engine type.

## Range filters

The Filters chip at the right end of the filter row opens the Ranges panel. The chip shows how many limits apply on the tab, and it is highlighted while at least one applies.

- A slider stops only at values that a listed vehicle has. A slider at its end sets no limit on that side.
- A vehicle with a dash in a column stays in the list, whatever the limit of that column.
- A limit on a column that a tab does not show is ignored on that tab.
- Each depot keeps its limits while the game runs. Clear ranges and Clear filters remove them.

## Use

The fork and the original replace the same store window. Only one of them MUST be active in a game.

## Known limits

- While a store window shows the buyer, the game logs the warning "Preserved props id ... of an instance of VehicleStoreWindowContent - this usually means a recipe was called but not attached to the tree" many times per second. The game builds its own store content for the window, and the buyer takes its place, so that content stays unused. The original has the same warning. With `debugMode = true` in the game's `settings.lua`, the warning also shows on the screen.
- Modify of several trains with different cars opens the game's store. A different livery of the same model counts as a different car.

## Tests

Run from this folder:

```sh
lua55 tests/core_test.lua
```

The test covers the grade letters, the rule of the cargo filter, the specializations of a vehicle, the comparison of the cars of several trains, and the limits and steps of the range filters in `vh_core.lua`. The listing table itself runs only inside the game.

## Updates of the original

mod.io updates only the original. A new version reaches the fork through a merge by hand: commit the new files on a branch from the first commit, then merge that branch.

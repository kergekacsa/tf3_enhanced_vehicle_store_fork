# Enhanced Vehicle Store (private fork)

A private fork of the Transport Fever 3 mod Enhanced Vehicle Store. The mod replaces the content of the store window that a depot opens for buying vehicles.

## Language

**Listing table**:
The table of the store with one row per vehicle and one column per value.
_Avoid_: Summary row, list, grid

**Details**:
The panel that opens for one vehicle of the listing table and shows every value of it.
_Avoid_: Info, popup

**Grade**:
The rating of the game for the noise, pollution or comfort of a vehicle, written as a letter. A is Very Good and E is Very Poor, on the ranges of the game for the carrier and the year.
_Avoid_: Score, rank, class

**Cargo filter**:
The row of chips that limits the listing table to vehicles that carry every ticked cargo type.
_Avoid_: Cargo search, cargo picker

**All cargo**:
The chip of the cargo filter for vehicles that carry every freight type.
_Avoid_: Universal, mixed cargo

**Any cargo**:
The chip of the cargo filter for vehicles that carry at least one freight type.
_Avoid_: Freight, cargo vehicles

**Range filter**:
The filter of one column of the listing table that keeps the vehicles whose value lies inside a limit.
_Avoid_: Column filter, slider filter

**Limit**:
The lowest and the highest value that a range filter allows. Either end can be open.
_Avoid_: Range, bounds, threshold

**Step**:
One value that a slider of a range filter can stop at. It is a value that a listed vehicle has.
_Avoid_: Tick, notch

**Original**:
The mod of the author on mod.io, mod ID `ethan_vehicle_helper_next`, from which this fork starts.
_Avoid_: Upstream, base mod

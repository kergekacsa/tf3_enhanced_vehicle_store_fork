-- Tests of the rules in vh_core.lua that need no game: the grade letters and the cargo filter.
-- Run from the folder kacsa_enhanced_vehicle_store_dev: lua55 tests/core_test.lua

local core = dofile("../kacsa_enhanced_vehicle_store/content/vehicle_helper_next/vh_core.lua")

local failures = 0
local function check(name, got, want)
	if got ~= want then
		failures = failures + 1
		print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
	end
end

-- grade: the game's five rating steps, each limit belongs to the better letter
for _, case in ipairs({
	{ 0, "E" }, { 0.19, "E" },
	{ 0.2, "D" }, { 0.39, "D" },
	{ 0.4, "C" }, { 0.59, "C" },
	{ 0.6, "B" }, { 0.79, "B" },
	{ 0.8, "A" }, { 1, "A" },
}) do
	check("grade(" .. case[1] .. ")", core.grade(case[1]), case[2])
end

-- carriesAll: every picked type, not any of them
local ALL, ANY = "all", "any"
local COAL, ORE, PASSENGERS = 1, 2, 3
local coalOnly = { [COAL] = 10 }
local coalAndOre = { [COAL] = 10, [ORE] = 10 }
local noCoal = { [COAL] = 0, [ORE] = 10 }
-- which group chips a vehicle matches: All cargo (every freight type), Any cargo (some freight)
local plain = { [ALL] = false, [ANY] = true }
local universal = { [ALL] = true, [ANY] = true }
local noFreight = { [ALL] = false, [ANY] = false }

check("one picked type, carried", core.carriesAll(coalOnly, { [COAL] = true }, plain), true)
check("one picked type, not carried", core.carriesAll(coalOnly, { [ORE] = true }, plain), false)
check("two picked types, both carried", core.carriesAll(coalAndOre, { [COAL] = true, [ORE] = true }, plain), true)
check("two picked types, one carried", core.carriesAll(coalOnly, { [COAL] = true, [ORE] = true }, plain), false)
check("a capacity of zero is not carried", core.carriesAll(noCoal, { [COAL] = true }, plain), false)
check("no capacities at all", core.carriesAll(nil, { [COAL] = true }, plain), false)
check("no groups at all", core.carriesAll(coalOnly, { [COAL] = true }, nil), true)
check("nothing picked", core.carriesAll(coalOnly, {}, plain), true)
check("All cargo picked, universal vehicle", core.carriesAll(coalAndOre, { [ALL] = true }, universal), true)
check("All cargo picked, plain vehicle", core.carriesAll(coalAndOre, { [ALL] = true }, plain), false)
check("Any cargo picked, plain vehicle", core.carriesAll(coalOnly, { [ANY] = true }, plain), true)
check("Any cargo picked, vehicle without freight", core.carriesAll({ [PASSENGERS] = 20 }, { [ANY] = true }, noFreight), false)
check("All cargo and passengers, universal without passengers",
	core.carriesAll(coalAndOre, { [ALL] = true, [PASSENGERS] = true }, universal), false)
check("All cargo and passengers, universal with passengers",
	core.carriesAll({ [COAL] = 10, [PASSENGERS] = 20 }, { [ALL] = true, [PASSENGERS] = true }, universal), true)
check("Any cargo and passengers, freight and passengers",
	core.carriesAll({ [COAL] = 10, [PASSENGERS] = 20 }, { [ANY] = true, [PASSENGERS] = true }, plain), true)

-- specializations: the cargo classes without any-cargo and passengers, each once
local function joined(list) return table.concat(list, ",") end
check("no classes", joined(core.specializations(nil)), "")
check("only plain classes", joined(core.specializations({ "UNIVERSAL", "PASSENGERS" })), "")
check("one specialization", joined(core.specializations({ "BULK" })), "BULK")
check("a specialization next to plain classes", joined(core.specializations({ "PASSENGERS", "BULK", "UNIVERSAL" })), "BULK")
check("the same class twice", joined(core.specializations({ "BULK", "LIQUID", "BULK" })), "BULK,LIQUID")

-- narrowScreen: by the ratio of width to height, unknown counts as narrow
check("1920 x 1080", core.narrowScreen(1920, 1080), true)
check("2560 x 1440", core.narrowScreen(2560, 1440), true)
check("3840 x 2160", core.narrowScreen(3840, 2160), true)
check("1920 x 1200", core.narrowScreen(1920, 1200), true)
check("2560 x 1080", core.narrowScreen(2560, 1080), false)
check("3440 x 1440", core.narrowScreen(3440, 1440), false)
check("5120 x 1440", core.narrowScreen(5120, 1440), false)
check("unknown size", core.narrowScreen(nil, nil), true)
check("height of zero", core.narrowScreen(1920, 0), true)

-- hasEngine: a train needs power or thrust
check("an empty train", core.hasEngine(nil), false)
check("only wagons", core.hasEngine({ power = 0, thrust = 0 }), false)
check("no values at all", core.hasEngine({}), false)
check("a locomotive", core.hasEngine({ power = 3000, thrust = 0 }), true)
check("thrust only", core.hasEngine({ thrust = 50 }), true)

-- sameLists: every list like the first one, value by value
check("one list", core.sameLists({ { "a", "b" } }), true)
check("two equal lists", core.sameLists({ { "a", "b" }, { "a", "b" } }), true)
check("another order", core.sameLists({ { "a", "b" }, { "b", "a" } }), false)
check("a longer list", core.sameLists({ { "a", "b" }, { "a", "b", "b" } }), false)
check("a shorter list", core.sameLists({ { "a", "b" }, { "a" } }), false)
check("the third list differs", core.sameLists({ { "a" }, { "a" }, { "b" } }), false)

-- gradeIndex: the place of the letter in GRADES, worst first
check("gradeIndex(0)", core.gradeIndex(0), 1)
check("gradeIndex(0.6)", core.gradeIndex(0.6), 4)
check("gradeIndex(1)", core.gradeIndex(1), 5)
check("GRADES[gradeIndex(0.6)]", core.GRADES[core.gradeIndex(0.6)], "B")

-- inLimit: the ends count as inside, a missing end is no limit
check("inside both ends", core.inLimit(5, { from = 1, to = 9 }), true)
check("on the lower end", core.inLimit(1, { from = 1, to = 9 }), true)
check("on the upper end", core.inLimit(9, { from = 1, to = 9 }), true)
check("below the lower end", core.inLimit(0, { from = 1, to = 9 }), false)
check("above the upper end", core.inLimit(10, { from = 1, to = 9 }), false)
check("only a lower end", core.inLimit(1000, { from = 1 }), true)
check("only an upper end", core.inLimit(-1000, { to = 9 }), true)

-- steps: one step per shown text, lowest first
local function whole(v) return tostring(math.floor(v)) end
local steps = core.steps({ 3.5, 1, 2.2, 3.1, 1, 2.9 }, whole)
check("steps count", #steps, 3)
check("step 1 label", steps[1].label, "1")
check("step 2 lowest", steps[2].lo, 2.2)
check("step 2 highest", steps[2].hi, 2.9)
check("step 3 lowest", steps[3].lo, 3.1)
check("step 3 highest", steps[3].hi, 3.5)
check("no values, no steps", #core.steps({}, whole), 0)

-- fromIndex / toIndex: where the sliders stand for a limit
check("no lower limit", core.fromIndex(steps, nil), 1)
check("lower limit on a step", core.fromIndex(steps, 2.2), 2)
check("lower limit between two steps", core.fromIndex(steps, 3), 3)
check("lower limit above every step", core.fromIndex(steps, 99), 3)
check("no upper limit", core.toIndex(steps, nil), 3)
check("upper limit on a step", core.toIndex(steps, 2.9), 2)
check("upper limit between two steps", core.toIndex(steps, 3), 2)
check("upper limit below every step", core.toIndex(steps, 0), 1)

-- limitOf: slider places to a limit, and back
check("both sliders at their ends", core.limitOf(steps, 1, 3), nil)
check("From above To", core.limitOf(steps, 3, 2), nil)
local lower = core.limitOf(steps, 2, 3)
check("only From moved: from", lower.from, 2.2)
check("only From moved: to", lower.to, nil)
local upper = core.limitOf(steps, 1, 2)
check("only To moved: from", upper.from, nil)
check("only To moved: to", upper.to, 2.9)
local one = core.limitOf(steps, 2, 2)
check("one step: from", one.from, 2.2)
check("one step: to", one.to, 2.9)
check("one step keeps its values", core.inLimit(2.5, one), true)
check("one step drops the others", core.inLimit(3.1, one), false)
check("From comes back to its place", core.fromIndex(steps, one.from), 2)
check("To comes back to its place", core.toIndex(steps, one.to), 2)

-- percent: 0 to 1 as 0 to 100, one decimal only when needed
check("percent(0)", core.percent(0), "0")
check("percent(0.45)", core.percent(0.45), "45")
check("percent(0.725)", core.percent(0.725), "72.5")
check("percent(0.7251)", core.percent(0.7251), "72.5")
check("percent(1)", core.percent(1), "100")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("all passed")

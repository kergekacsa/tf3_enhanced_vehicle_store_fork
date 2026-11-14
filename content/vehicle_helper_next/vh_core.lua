-- Enhanced Vehicle Store v1.1: shared core.
-- Settings (kept between games in the app config), the four numbers, and text formatting.
-- Loaded with require(...) by vh_hook.script.lua and vh_buyer.lua, so both share one copy.
--
-- Physics constants are the game's own (::/gui/line_vehicle_mgmt/vehicle_util.tl,
-- getPowerRatingTextAndToolTip): g = 3.27, 95 % tractive effort limit, slope step 3.75 %.
-- Units as in VehicleStoreUtil.VehicleData: t, kW, kN, m/s, money per year.

local M = {}

M.TAG = "[EnhancedStore] "
M.VERSION = "1.3-kacsa1"
M.MOD_ID = "kacsa_enhanced_vehicle_store"

local G = 3.27
local LIMIT = 0.95
local STEP = 0.0375

---------------------------------------------------------------------------------------------------
-- logging
---------------------------------------------------------------------------------------------------
function M.log(msg)
	if debugPrint then debugPrint(M.TAG .. tostring(msg)) end
end

---------------------------------------------------------------------------------------------------
-- settings
---------------------------------------------------------------------------------------------------
M.SLOPES = {
	{ name = "Gentle", value = STEP / 2 },
	{ name = "Medium", value = STEP },
	{ name = "High", value = STEP * 2 },
}
M.TRAIN_WEIGHTS = { "Loaded", "Empty" }

M.DEFAULTS = {
	slope = 2,          -- index into SLOPES
	buyer = true,       -- the Enhanced Vehicle Store buyer instead of the game's store (Buy mode)
	trainWeight = 1,    -- index into TRAIN_WEIGHTS: train numbers with cargo (1) or empty (2)
	groupLiveries = true, -- buyer: one row per model instead of one per livery
	pictures = true,    -- buyer: vehicle pictures in the table and the train
}

-- settings without a switch in the buyer (always the default when the game starts)
M.NO_SWITCH = { "buyer" }

local SETTINGS_KEY = "kacsa_enhanced_vehicle_store"
local current = nil
M.settingsVersion = 0

local function sanitize(t)
	local s = {}
	for k, v in pairs(M.DEFAULTS) do s[k] = v end
	if type(t) == "table" then
		if type(t.slope) == "number" and M.SLOPES[t.slope] then s.slope = t.slope end
		if type(t.trainWeight) == "number" and M.TRAIN_WEIGHTS[t.trainWeight] then s.trainWeight = t.trainWeight end
		for _, k in ipairs({ "buyer", "groupLiveries", "pictures" }) do
			if type(t[k]) == "boolean" then s[k] = t[k] end
		end
	end
	return s
end
M.sanitize = sanitize

function M.copySettings(s)
	local c = {}
	for k, v in pairs(s) do c[k] = v end
	return c
end

local function copyTable(t)
	local ok, table_util = pcall(function() return ug_require "::/scripts/table_util.tl" end)
	if ok and table_util and table_util.copy then
		return table_util.copy(t)
	end
	local c = {}
	if t then for k, v in pairs(t) do c[k] = v end end
	return c
end

function M.loadSettings()
	local ok, res = pcall(function()
		local cfg = api.type.AppConfig.new(api.util.getAppConfig())
		local state = cfg.mainMenuState
		local s = sanitize(state and state[SETTINGS_KEY])
		-- these have no switch any more (the settings window was removed): a value saved by an
		-- older version must not keep a part of the mod switched off for good
		for _, k in ipairs(M.NO_SWITCH) do s[k] = M.DEFAULTS[k] end
		return s
	end)
	if ok then return res end
	M.log("could not read the settings, using defaults: " .. tostring(res))
	return sanitize(nil)
end

function M.settings()
	if current == nil then
		current = M.loadSettings()
	end
	return current
end

-- saves into AppConfig.mainMenuState (the game keeps it in settings.lua), the same way the
-- game's new-game page stores its own choices
function M.saveSettings(s)
	current = sanitize(s)
	M.settingsVersion = M.settingsVersion + 1
	local ok, err = pcall(function()
		local cfg = api.type.AppConfig.new(api.util.getAppConfig())
		local t = copyTable(cfg.mainMenuState)
		t[SETTINGS_KEY] = {
			v = 1,
			slope = current.slope,
			buyer = current.buyer,
			trainWeight = current.trainWeight,
			groupLiveries = current.groupLiveries,
			pictures = current.pictures,
		}
		cfg.mainMenuState = t
		api.util.setAppConfig(cfg, false)
	end)
	if not ok then
		M.log("could not save the settings (they still apply until the game is closed): " .. tostring(err))
	end
	return ok
end

function M.slopeValue(s) return M.SLOPES[s.slope].value end
function M.slopeName(s) return M.SLOPES[s.slope].name end
function M.emptyTrains(s) return s.trainWeight == 2 end
-- the weight used for a train's numbers: with cargo, or empty (setting)
function M.trainWeightOf(d, s)
	if d == nil then return 0 end
	return (d.weight or 0) + (M.emptyTrains(s) and 0 or (d.weightMaxPayload or 0))
end

---------------------------------------------------------------------------------------------------
-- calculation (no game calls)
---------------------------------------------------------------------------------------------------
local function force(P, TE, v)
	if TE <= 0 then return 0 end
	if v <= P / TE then return TE end
	return P / v
end

-- seconds to reach vmax from standstill against a constant resistance R (Simpson's rule)
function M.timeToSpeed(W, P, TE, R, vmax)
	if vmax <= 0 then return 0 end
	local n = 200
	local h = vmax / n
	local f = function(v) return W / (force(P, TE, v) - R) end
	local s = f(0) + f(vmax)
	for i = 1, n - 1 do
		s = s + ((i % 2 == 1) and 4 or 2) * f(i * h)
	end
	return s * h / 3
end

-- heaviest train (t) that can still start on the slope and keep vRef (m/s) up it
function M.pullLimit(P, TE, vRef, slope, fr)
	local k = G * slope
	return math.min((LIMIT * TE - fr) / k, (LIMIT * P / vRef - fr) / k)
end

-- whole train: W loaded weight (t), P kW, TE kN, top m/s, fr summed rolling friction (kN)
function M.performance(W, P, TE, top, fr, slope)
	if not (W and P and TE and top and fr) then return nil end
	if W <= 0 or TE <= 0 or P <= 0 or top <= 0 or top == math.huge then return nil end
	local r = {}
	r.startAccel = (TE - fr) / W
	if fr < LIMIT * TE then
		local vmax = math.min(top, LIMIT * P / math.max(fr, 1e-9))
		r.flatTop = vmax
		r.flatTime = M.timeToSpeed(W, P, TE, fr, vmax)
	end
	r.maxWeight = M.pullLimit(P, TE, top / 2, slope, fr)
	r.spare = r.maxWeight - W
	return r
end

function M.perCargo(d)
	if d == nil then return nil end
	local cap = d.totalCapacity or 0
	if cap <= 0 then return nil end
	return { price = (d.price or 0) / cap, upkeep = (d.runningCosts or 0) / cap, capacity = cap }
end

-- one vehicle (or multiple unit) in the store list:
--   pricePerCargo, upkeepPerCargo   when it carries something
--   accel (m/s², the vehicle on its own, loaded or empty as set), selfTime (s to top speed),
--   pull (t a locomotive can haul on the chosen slope), loadingSpeed (the game's multiplier),
--   powerPerWeight (kW/t, ships only: loaded or empty as set)
-- The train builder shows a train's real acceleration; a list never assumes a load behind it.
function M.vehicleMetrics(d, s)
	local r = {}
	if d == nil then return r end
	local cap = d.totalCapacity or 0
	if cap > 0 then
		r.pricePerCargo = (d.price or 0) / cap
		r.upkeepPerCargo = (d.runningCosts or 0) / cap
	end
	local TE, P, top = d.tractiveEffort or 0, d.power or 0, d.speed
	if TE > 0 and P > 0 and top and top > 0 and top < math.huge then
		local own = (d.weight or 0) + (d.weightMaxPayload or 0)
		local fr = (d.rollingFriction and d.rollingFriction > 0) and d.rollingFriction or 0.02
		r.pull = math.max(M.pullLimit(P, TE, top / 2, M.slopeValue(s), fr) - own, 0)
	end
	-- the vehicle on its own: acceleration from a stop and the time to its top speed
	local self = M.selfPerformance(d, s)
	if self then
		r.accel = self.accel
		r.selfTime = self.time
	end
	if (d.loadingSpeed or 0) > 0 and cap > 0 then r.loadingSpeed = d.loadingSpeed end
	-- ships: power but no tractive effort or thrust in the store's data (the game works out a
	-- ship's pushing force from its propeller inside the engine); power per tonne compares them
	if (d.power or 0) > 0 and (d.tractiveEffort or 0) <= 0 and (d.thrust or 0) <= 0 then
		local W = M.trainWeightOf(d, s)
		if W > 0 then r.powerPerWeight = d.power / W end
	end
	return r
end

-- acceleration (m/s²) and seconds to top speed of one vehicle by itself, on the flat:
-- * tractive effort and power (rail, road): the game's force model, F = min(TE, P / v)
-- * thrust only (planes, ships): a constant thrust over the mass, no drag (an estimate)
function M.selfPerformance(d, s)
	if d == nil then return nil end
	local top = d.speed
	if not top or top <= 0 or top == math.huge then return nil end
	local W = M.trainWeightOf(d, s)
	if W <= 0 then return nil end
	local TE, P = d.tractiveEffort or 0, d.power or 0
	if TE > 0 and P > 0 then
		local fr = (d.rollingFriction and d.rollingFriction > 0) and d.rollingFriction or 0.02
		local perf = M.performance(W, P, TE, top, fr, M.slopeValue(s))
		if perf == nil then return nil end
		return { accel = math.max(perf.startAccel, 0), time = perf.flatTime, top = perf.flatTop or top, model = "force" }
	end
	local thrust = d.thrust or 0
	if thrust > 0 then
		local a = thrust / W
		return { accel = a, time = top / a, top = top, model = "thrust" }
	end
	return nil
end

-- heaviest load (t) a locomotive can start and keep at half its top speed on a slope (0..1)
function M.pullOn(d, slope)
	local TE, P, top = d.tractiveEffort or 0, d.power or 0, d.speed
	if TE <= 0 or P <= 0 or not top or top <= 0 or top == math.huge then return nil end
	local own = (d.weight or 0) + (d.weightMaxPayload or 0)
	local fr = (d.rollingFriction and d.rollingFriction > 0) and d.rollingFriction or 0.02
	return math.max(M.pullLimit(P, TE, top / 2, slope, fr) - own, 0)
end

---------------------------------------------------------------------------------------------------
-- grades and the cargo filter (no game calls)
---------------------------------------------------------------------------------------------------
-- the letters from worst to best; a score below GRADE_LIMITS[i] gets GRADES[i]. The limits are
-- the game's own five rating steps (vehicle_store_util.goodnessToTextString: Very Poor, Poor,
-- Mediocre, Good, Very Good)
M.GRADES = { "E", "D", "C", "B", "A" }
local GRADE_LIMITS = { 0.2, 0.4, 0.6, 0.8 }

-- the place of a score from 0 (worst) to 1 (best) in GRADES
function M.gradeIndex(score)
	for i, limit in ipairs(GRADE_LIMITS) do
		if score < limit then return i end
	end
	return #M.GRADES
end

-- the letter of a score from 0 (worst) to 1 (best)
function M.grade(score) return M.GRADES[M.gradeIndex(score)] end

-- true when a vehicle matches every picked chip of the cargo filter.
-- capacities: cargo type id -> amount (VehicleData.allCargoTypes); picked: set of chip keys.
-- A key is a cargo type id, or a key of `groups`: chip key -> whether this vehicle matches
-- that chip (the chips that stand for more than one cargo type)
function M.carriesAll(capacities, picked, groups)
	for id, _ in pairs(picked) do
		local inGroup = groups and groups[id]
		if inGroup ~= nil then
			if not inGroup then return false end
		elseif ((capacities and capacities[id]) or 0) <= 0 then
			return false
		end
	end
	return true
end

-- true when every list has the same values in the same order as the first one
function M.sameLists(lists)
	local first = lists[1]
	for k = 2, #lists do
		local other = lists[k]
		if #other ~= #first then return false end
		for i, v in ipairs(first) do
			if other[i] ~= v then return false end
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- range filters (no game calls)
---------------------------------------------------------------------------------------------------
-- A limit is { from = number or nil, to = number or nil }; nil means no limit on that side.
-- The steps of a column are the values its sliders stop at, lowest first: one step per text
-- that the listed values are shown as, { label = text, lo = lowest value, hi = highest value
-- with that text }.

-- true when a value is inside a limit (its ends count as inside)
function M.inLimit(value, limit)
	return (limit.from == nil or value >= limit.from) and (limit.to == nil or value <= limit.to)
end

-- the steps of a list of values; format(value) gives the text of a value and never gives a
-- lower value a text that a higher value had before it
function M.steps(values, format)
	local sorted = {}
	for i, v in ipairs(values) do sorted[i] = v end
	table.sort(sorted)
	local steps = {}
	for _, v in ipairs(sorted) do
		local label = format(v)
		local last = steps[#steps]
		if last and last.label == label then
			last.hi = v
		else
			steps[#steps + 1] = { label = label, lo = v, hi = v }
		end
	end
	return steps
end

-- where the From slider stands for a lower limit: the first step that reaches it (the first
-- step when there is no limit, the last when no step reaches it)
function M.fromIndex(steps, from)
	if from == nil then return 1 end
	for i, step in ipairs(steps) do
		if step.hi >= from then return i end
	end
	return #steps
end

-- where the To slider stands for an upper limit: the last step that stays under it (the last
-- step when there is no limit, the first when no step stays under it)
function M.toIndex(steps, to)
	if to == nil then return #steps end
	for i = #steps, 1, -1 do
		if steps[i].lo <= to then return i end
	end
	return 1
end

-- the limit of two slider places, From never above To; a slider at its end sets no limit on
-- that side, and the result is nil when neither side has one
function M.limitOf(steps, fromIndex, toIndex)
	if fromIndex > toIndex then return nil end
	local from = fromIndex > 1 and steps[fromIndex].lo or nil
	local to = toIndex < #steps and steps[toIndex].hi or nil
	if from == nil and to == nil then return nil end
	return { from = from, to = to }
end

---------------------------------------------------------------------------------------------------
-- formatting
---------------------------------------------------------------------------------------------------
local function round(x) return math.floor(x + 0.5) end

function M.int(n)
	local s = tostring(round(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

function M.money(n)
	if api and api.util and api.util.formatMoney then
		return api.util.formatMoney(round(n))
	end
	return "$" .. M.int(n)
end

function M.speed(v)
	if api and api.util and api.util.formatSpeed then
		return api.util.formatSpeed(v)
	end
	return M.int(v * 3.6) .. " km/h"
end

function M.seconds(s)
	local total = round(s)
	local m = math.floor(total / 60)
	local sec = total % 60
	if m > 0 then return string.format("%d:%02d", m, sec) end
	return string.format("%d s", sec)
end

function M.accel(a) return string.format("%.2f m/s\194\178", a) end

-- a share from 0 to 1 as a number from 0 to 100, with one decimal only when it has one
function M.percent(x)
	local tenths = round(x * 1000)
	if tenths % 10 == 0 then return string.format("%d", math.floor(tenths / 10)) end
	return string.format("%.1f", tenths / 10)
end

local DOT = " \194\183 "
M.DOT = DOT

return M

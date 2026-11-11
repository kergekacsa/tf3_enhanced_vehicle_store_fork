-- Enhanced Vehicle Store v1.3 (folder ethan_vehicle_helper_next): the buyer.
--
-- When a depot's Buy button opens the game's vehicle store, the store window shows this buyer
-- instead of the game's content:
--   top:     tabs (All / Locomotives / Wagons / Multiple units), search, count, Settings, Classic store
--   filters: engine types, Affordable, cargo types, Clear filters
--   settings (folds open): slope (trains only), loaded weights, variations, pictures
--   table:   one sortable row per vehicle; columns that mean nothing on a tab are hidden; the
--            numbers this mod adds have small bars (fuller = better among the vehicles shown).
--            Click anywhere on a row for its details; an arrow marks models with more variations:
--            liveries and versions (the game's variant groups, also multiple-unit versions from
--            mods). With "Variations: every variation" each has its own row, and no arrow or picker
--   details: picture, every number in sections, variations picker, color, description
--   train:   the vehicles you added, as tiles like the game's cart (hover: turn around, take off,
--            drag to move; runs of the same wagon stack, with x for the stack and - for one),
--            a grid of totals, Buy / Fill / Clear
-- Replace and Modify (the vehicle manager's buttons) open it too (1.2): Replace builds the
-- vehicle the old ones become, Modify starts with the train's own cars (Modify of several
-- vehicles at once keeps the game's store). "Classic store" switches the window to the game's
-- store, and an "Enhanced Store" button in a slim bar above that store switches it back.
--
-- How it plugs in (no debug library needed):
-- * ReplaceRecipe(vehicle_store_window.VehicleStoreWindow, passThrough): the official replacement
--   API. passThrough remembers the window's params, decides once per window (buyer or the game's
--   store) and draws the game's own window (react.CallOriginalRecipe), so every store window stays
--   the game's: size, title bar, close button, and switching to Classic store, Replace or Modify.
-- * The game's builtins (Window, BoxLayout, ToggleButton...) are never replaced for the whole game
--   (1.0 to 1.2 did, and windows other mods register later crashed the game, see the end of
--   install). vehicle_store_util.acceptsMultiVehicle is wrapped instead: the store window's body
--   calls it just before its builtin.Window, and only then, for that one call, builtin.Window is
--   a one-shot function that sets the content: VhBuyer for a buyer window, the game's content
--   under an "Enhanced Store" bar for a Classic store window. (The game still builds its own
--   content first; it logs a warning that it wasn't used.)
-- * Buying uses vehicle_react_util.HandleVehicleChanges with the same arguments as the store
--   (TransportVehicleConfig from vehicle_util.makePart), and fires the same mission events.
-- * The vehicles come from params.vehiclesStaticData (prepared by the store's entry point) and are
--   filtered with the store's own vehicle_store_util.vehicleFilter and handle*Carrier tab rules.
--
-- Every recipe here returns a layout (the game's "Recipe child must be a layout" rule), and every
-- builtin gets only parameter names the game itself uses for it (unknown names are errors).
-- Loaded with require(...) by vh_hook.script.lua; install() is called from doReplace.

local M = {}

local STORE_WINDOW_ID = "vehiclestore.window"

-- remembered between store openings for this game session
local ui = {
	tab = {},            -- carrier -> tab index
	filtersByDepot = {}, -- depot -> { cargo = {id = true}, engines = {type = true}, affordable }
	showSettings = false,
	sortKey = "year",
	sortAscending = true,
	colors = {},         -- "m<id>" / "u<id>" -> color picked in the details (like the store's own map)
}
M._ui = ui -- for tests

-- key of a model or multiple unit (their ids are separate lists in the game)
local function kindKey(multipleUnit, id) return (multipleUnit and "u" or "m") .. tostring(id) end

-- a color the game can use: nil for none or the "reset" color (-1, -1, -1)
local function usableColor(c)
	if c == nil then return nil end
	local ok, good = pcall(function() return c.x ~= nil and c.x >= 0 and c.y >= 0 and c.z >= 0 end)
	if ok and good then return c end
	return nil
end
local function colorKey(c)
	c = usableColor(c)
	if c == nil then return "" end
	return string.format("%.3f,%.3f,%.3f", c.x, c.y, c.z)
end

-- the filters of one depot (each depot keeps its own while the game runs)
local function depotFilters(store)
	local key = tostring(store.depot) .. "/" .. tostring(store.carrier)
	local f = ui.filtersByDepot[key]
	if f == nil then
		f = { cargo = {}, engines = {}, affordable = false }
		ui.filtersByDepot[key] = f
	end
	return f
end

function M.install(core, react, builtin, replacementApi, metricsFor)
	if core._buyerInstalled then return "already installed" end
	if replacementApi == nil or type(replacementApi.ReplaceRecipe) ~= "function" then
		return "no ReplaceRecipe in this game version, skipped"
	end
	local vsw = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_window.tl"
	local vsu = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl"
	local vu = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl"
	local vru = ug_require "::/gui/line_vehicle_mgmt/vehicle_react_util.tl"
	local okCargo, cargo_util = pcall(function() return ug_require "::/gui/main/cargo_util.tl" end)
	local okEru, engine_react_util = pcall(function() return ug_require "::/gui/main/engine_react_util.tl" end)
	if not okCargo then cargo_util = nil end
	if not okEru then engine_react_util = nil end

	local needed = {
		{ vsw, "VehicleStoreWindow", "vehicle_store_window" },
		{ vsu, "vehicleFilter", "vehicle_store_util" },
		{ vsu, "acceptsMultiVehicle", "vehicle_store_util" },
		{ vsu, "collectVehicleData", "vehicle_store_util" },
		{ vsu, "makeSingleVehicle", "vehicle_store_util" },
		{ vsu, "makeMultipleVehicles", "vehicle_store_util" },
		{ vu, "makePart", "vehicle_util" },
		{ vru, "HandleVehicleChanges", "vehicle_react_util" },
		{ builtin, "Window", "builtin" },
		{ builtin, "DataTable", "builtin" },
		{ builtin, "ColumnDesc", "builtin" },
		{ builtin, "ToggleButton", "builtin" },
		{ builtin, "ProgressBar", "builtin" },
		{ react, "CallOriginalRecipe", "react" },
	}
	for _, n in ipairs(needed) do
		if type(n[1]) ~= "table" or type(n[1][n[2]]) ~= "function" then
			return n[3] .. "." .. n[2] .. " not found (renamed by a patch?), skipped"
		end
	end

	local Orientation = builtin.type.Orientation
	local H, V = Orientation.Horizontal, Orientation.Vertical
	local DOT = core.DOT
	local DASH = "\226\128\147"
	local TIMES = " \195\151"

	-- log the first few errors (each different place once), so one bad cell can't flood the log
	local logged, loggedCount = {}, 0
	local function fail(where, err)
		if logged[where] or loggedCount >= 8 then return end
		logged[where] = true
		loggedCount = loggedCount + 1
		core.log("buyer: error in " .. where .. ": " .. tostring(err))
	end

	-------------------------------------------------------------------------------------------
	-- controller. The game's store gets controller input in VehicleStoreWindowContent, the part
	-- the buyer replaces: it takes focus when it opens and the d-pad moves the focus
	-- (IA_NAV_* with react.iaFocusTraversal). Without that nothing had focus and the d-pad did
	-- nothing (an Xbox player, 5 Oct). The buyer does the same, focuses its table (like the game's
	-- statistics tables), and gives the train's tiles the game's controller moves.
	-------------------------------------------------------------------------------------------
	-- the game's own test (its store checks it every frame: the mode follows the last device used)
	local function padMode()
		local ok, yes = pcall(function() return api.util.getInputMode() == api.type["enum"].InputMode.Gamepad end)
		return ok and yes == true
	end
	local canIA = type(react.useInputAction) == "function" and type(react.iaFocusTraversal) == "function"
		and type(react.iaHandler) == "function"
	-- the first few controller events go to the log (to see in stdout.txt what the game sent)
	local padLogs = 0
	local function padLog(msg)
		if padLogs >= 12 then return end
		padLogs = padLogs + 1
		core.log("controller: " .. msg)
	end
	M._padMode = padMode -- for tests

	-------------------------------------------------------------------------------------------
	-- small helpers
	-------------------------------------------------------------------------------------------
	local function text(t, class)
		return builtin.TextView{ meta = { class = class }, text = t }
	end
	-- children lists here may have gaps (an optional item written as `x or nil` in the middle);
	-- the game reads children in order, so the gaps are closed before they get there
	local function compact(list)
		if list == nil then return nil end
		local maxIndex = 0
		for k, _ in pairs(list) do if type(k) == "number" and k > maxIndex then maxIndex = k end end
		local out = {}
		for i = 1, maxIndex do if list[i] ~= nil then out[#out + 1] = list[i] end end
		return out
	end
	local function box(orientation, children, class)
		return builtin.BoxLayout{ meta = class and { class = class } or nil, orientation = orientation, children = compact(children) }
	end
	-- a panel with the game's card look (see vh_store.css.lua)
	local function card(orientation, children, class)
		return builtin.Component{
			meta = { class = "vh-card" .. (class and (", " .. class) or "") },
			layout = box(orientation, children, class and (class .. "-box") or nil),
		}
	end
	-- boxes hand spare room to their children; a spacer at the end takes it, so the rest stays packed
	local function spacer()
		return builtin.Component{ meta = { class = "vh-spacer" } }
	end
	local function vspacer()
		return builtin.Component{ meta = { class = "vh-vspacer" } }
	end
	local function button(label, tooltip, onClick, class, enabled)
		return builtin.Button{
			meta = { tooltip = tooltip, class = class or "vh-button", enabled = enabled ~= false },
			content = builtin.TextView{ text = label },
			onClick = onClick,
		}
	end
	local function toggle(content, on, onChange, tooltip, class)
		return builtin.ToggleButton{
			meta = { tooltip = tooltip, class = class or "vh-chip" },
			content = content,
			value = on and 1 or 0,
			onValueChange = function(value) onChange(value == 1) end,
		}
	end
	local function image(path, class, flipped)
		return builtin.ImageView{
			meta = { class = class },
			path = path,
			flippedHorizontally = flipped and true or nil,
			scaling = builtin.type.ImageViewScaling and builtin.type.ImageViewScaling.AutoFit or nil,
		}
	end

	-- picture `index` of a vehicle (a multiple unit has one per car), turned around if `reversed`,
	-- painted with `color` the way the store does it (the game's VehicleImage with the blend mask)
	local function vehiclePicture(es, index, reversed, color, class)
		local file = es.icons and es.icons[index]
		if file == nil or file == "" then return nil end
		local flipped = (es.iconOrientations and es.iconOrientations[index]) and true or false
		if reversed then flipped = not flipped end
		local c = usableColor(color)
		local blend = c and es.iconsBlend and es.iconsBlend[index] or nil
		if blend and blend ~= "" and type(vru.VehicleImage) == "function" then
			return box(H, {
				vru.VehicleImage{
					meta = { class = class },
					fileName = file,
					cblendFileName = blend,
					name = es.name,
					flippedHorizontally = flipped,
					color = c,
				},
			}, class and (class .. "-box") or nil)
		end
		return image(file, class, flipped)
	end
	-- all pictures of a vehicle in a row; reversed: last car first, each one turned
	local function vehiclePictures(es, reversed, color, class, max)
		local out = {}
		local count = #(es.icons or {})
		local n = math.min(count, max or 99)
		local from, to, step = 1, n, 1
		-- turned around, the last car is in front: count down from it
		if reversed then from, to, step = count, count - n + 1, -1 end
		for i = from, to, step do
			local p = vehiclePicture(es, i, reversed, color, class)
			if p then out[#out + 1] = p end
		end
		return out
	end

	-- a window onto `content` that cuts off what doesn't fit (the store's list names do the same
	-- with a ScrollArea). mouseTransparent: clicks go to the row button underneath
	local function clip(content, class, orientation, scrollable)
		local P = builtin.type.ScrollBarPolicy
		local horizontal = P and P.AlwaysOff or nil
		if scrollable and P and P.AsNeeded then horizontal = P.AsNeeded end
		return builtin.ScrollArea{
			meta = { class = class, mouseTransparent = not scrollable },
			content = builtin.Component{ layout = box(orientation or H, content, class .. "-box") },
			horizontalPolicy = horizontal,
			verticalPolicy = P and P.AlwaysOff or nil,
			disableGamepadNavigation = true, -- the d-pad moves the focus, it doesn't scroll these
		}
	end

	local ICON = "::/gui/line_vehicle_mgmt/icons/"
	local ARROW_DOWN = "::/gui/entity_window/design/collapse_down.tga"
	local ARROW_UP = "::/gui/entity_window/design/collapse_up.tga"
	local REVERSE_ICON = ICON .. "symbol_arrows_left_right_12.tga"

	local function fmt(fn, v)
		local ok, r = pcall(fn, v)
		if ok and type(r) == "string" then return r end
		return core.int(v)
	end
	local function money(v) return core.money(v) end
	local function speed(v) return core.speed(v) end
	local function power(v) return fmt(api.util.formatPower, v) end
	local function force(v) return fmt(api.util.formatForce, v) end
	-- power per tonne with one decimal, in the player's unit (kW or hp): the game's formatter
	-- rounds to whole units, so it formats ten times the value and the decimal point goes back in
	local function powerPerTonne(v)
		local str = power(math.floor(v * 10 + 0.5))
		local num, unit = str:match("^([%d,%.]+)%s*(.-)$")
		local n = num and tonumber((num:gsub(",", "")))
		if n == nil then return str .. "/t" end
		return string.format("%.1f %s/t", n / 10, unit)
	end
	local function weight(v) return api.util.formatWeight and fmt(api.util.formatWeight, v) or (core.int(v) .. " t") end
	-- train lengths in ft or m (the game's formatter switches to miles / km for long trains)
	local function trainLength(v)
		local s = api.util.formatLength and fmt(api.util.formatLength, v) or ""
		if s:find("mi", 1, true) or s:find("ft", 1, true) then return core.int(v * 3.28084) .. " ft" end
		return core.int(v) .. " m"
	end

	local function currentYear()
		local ok, y = pcall(function()
			local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
			return api.engine.util.getCalendarDate(gameTime.gameTime).year
		end)
		if ok and type(y) == "number" then return y end
		return 3000
	end

	local function balance()
		local ok, b = pcall(function() return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer()) end)
		if ok then return b end -- nil: unlimited money
		return nil
	end

	local function missionEvent(name, param)
		local ok, r = pcall(function() return api.gui.fireGuiScriptEvent("vehicleStore", name, param) end)
		if ok and type(r) == "string" and r ~= "" then return r end
		return nil
	end

	local function cargoInfo(id)
		local ok, c = pcall(function() return api.res.cargoTypeRep.get(id) end)
		if ok and c then return { name = c.name or tostring(id), icon = c.icon } end
		return { name = tostring(id) }
	end
	local passengerId = nil
	pcall(function() passengerId = cargo_util and cargo_util.getPassengerCargoTypeId() end)
	-- the cargo filter's "All cargo" (the game's mixed-cargo button): vehicles for any cargo
	local ALL_CARGO = "all"
	-- vehicles for any cargo (the game's cargo class UNIVERSAL, as its store checks it)
	local function hasCargoClass(d, cls)
		if type(d.cargoClasses) ~= "table" then return false end
		for _, c in ipairs(d.cargoClasses) do if c == cls then return true end end
		return false
	end
	local function carriesPassengers(d)
		return passengerId ~= nil and ((d.allCargoTypes or {})[passengerId] or 0) > 0
	end
	-- the number of freight cargo types in the game (passengers not counted), looked up once
	local freightTypes = nil
	local function freightTypeCount()
		if freightTypes == nil then
			freightTypes = 0
			pcall(function()
				local n = 0
				for id, _ in pairs(api.res.cargoTypeRep.getAll()) do if id ~= passengerId then n = n + 1 end end
				freightTypes = n
			end)
		end
		return freightTypes
	end
	-- a vehicle for any cargo: the game's class UNIVERSAL, or (data without classes) every
	-- freight type the game has
	local function forAnyCargo(d)
		if hasCargoClass(d, "UNIVERSAL") then return true end
		local all = freightTypeCount()
		if all < 2 then return false end
		local n = 0
		for id, amount in pairs(d.allCargoTypes or {}) do
			if id ~= passengerId and amount and amount > 0 then n = n + 1 end
		end
		return n >= all
	end
	function M._resetFreightCount() freightTypes = nil end -- for tests


	local ENGINE_NAMES = { HORSE = "Horse", STEAM = "Steam", DIESEL = "Diesel", ELECTRIC = "Electric" }
	local ENGINE_ORDER = { "HORSE", "STEAM", "DIESEL", "ELECTRIC" }
	local function engineEnum()
		local out = {}
		pcall(function()
			for _, key in ipairs(ENGINE_ORDER) do
				local v = api.type["enum"].VehicleEngineType[key]
				if v ~= nil then out[#out + 1] = { key = key, value = v, name = ENGINE_NAMES[key] } end
			end
		end)
		return out
	end

	-------------------------------------------------------------------------------------------
	-- tabs, using the store's own carrier rules
	-------------------------------------------------------------------------------------------
	local function carrierEnum(name)
		local ok, v = pcall(function() return api.type["enum"].Carrier[name] end)
		if ok then return v end
		return nil
	end

	local function tabsFor(carrier)
		local tabs = { { id = "all", label = "All" } }
		if carrier ~= nil and carrier == carrierEnum("RAIL") then
			tabs[#tabs + 1] = { id = "locomotive", label = "Locomotives" }
			tabs[#tabs + 1] = { id = "waggon", label = "Wagons" }
			tabs[#tabs + 1] = { id = "multiple_unit", label = "Multiple units" }
		elseif carrier ~= nil and carrier == carrierEnum("TRAM") then
			tabs[#tabs + 1] = { id = "railcar", label = "Railcars" }
			tabs[#tabs + 1] = { id = "locomotive", label = "Locomotives" }
			tabs[#tabs + 1] = { id = "waggon", label = "Wagons" }
		end
		return tabs
	end

	local function makeFilter(store, tabs, tabIndex)
		local okVf, vehicleFilter = pcall(function() return store.gameCtx.filters:get().vehicleFilter end)
		local filter = {
			carrier = store.carrier,
			transportModes = store.transportModes,
			text = "",
			cargoFilters = {},
			engines = {},
			multipleUnits = true,
			singleVehicles = true,
			vehicleFilter = okVf and vehicleFilter or nil,
			filterTags = store.filterTags,
		}
		local id2index = {}
		for i, t in ipairs(tabs) do id2index[t.id] = i end
		local index = tabs[tabIndex] and tabs[tabIndex].id ~= "all" and tabIndex or -1
		if store.carrier ~= nil and store.carrier == carrierEnum("RAIL") and type(vsu.handleRailCarrier) == "function" then
			return vsu.handleRailCarrier(filter, id2index, index)
		elseif store.carrier ~= nil and store.carrier == carrierEnum("TRAM") and type(vsu.handleTramCarrier) == "function" then
			return vsu.handleTramCarrier(filter, id2index, index)
		elseif type(vsu.handleDefaultCarrier) == "function" then
			return vsu.handleDefaultCarrier(filter)
		end
		return filter
	end

	-------------------------------------------------------------------------------------------
	-- names and liveries
	-------------------------------------------------------------------------------------------
	-- path -> element static, per store data table (built once per store opening)
	local lastIndexSource, lastIndex = nil, nil
	local function pathIndex(data)
		if data ~= lastIndexSource then
			local idx = {}
			for _, es in pairs(data) do if es.path then idx[es.path] = es end end
			lastIndexSource, lastIndex = data, idx
		end
		return lastIndex
	end

	-- the store's variant groups (vehiclesStaticData.variantGroup2muAndVariants): parent path ->
	-- its liveries, and the versions of a multiple unit (mods add some with other cars).
	-- Turned around here: vehicle -> the path of its group.
	local lastVariantSource, lastParentOf = false, nil
	local function variantIndex(store)
		local vsd = store and store.vehiclesStaticData
		local src = vsd and vsd.variantGroup2muAndVariants
		if src ~= lastVariantSource then
			local parentOf = {}
			if type(src) == "table" then
				for path, list in pairs(src) do
					for _, v in ipairs(list) do
						if v.id ~= nil then parentOf[kindKey(v.multipleUnit, v.id)] = path end
					end
				end
			end
			lastVariantSource, lastParentOf = src, parentOf
		end
		return lastParentOf or {}
	end

	-- the group (a parent path) a vehicle belongs to, or nil when it has no liveries or versions
	local function groupKeyOf(es, parentOf)
		local p = parentOf and parentOf[kindKey(es.multipleUnit, es.repId)]
		if p then return p end
		if (es.variantCount or 0) > 0 then return es.path end
		-- without the store's map: a model's own group (a multiple unit's is one of its cars')
		if not es.multipleUnit then
			local g = es.vehicleData and es.vehicleData.variantGroup
			if type(g) == "string" and g ~= "" then return g end
		end
		return nil
	end

	-- the model name and, for a livery, the livery name (versions of a multiple unit keep their own)
	local function namesOf(es, index, parentOf)
		if not es.multipleUnit then
			local g = groupKeyOf(es, parentOf)
			if g and g ~= es.path and index and index[g] and index[g].name ~= es.name then
				return index[g].name, es.name
			end
		end
		return es.name, nil
	end

	local function searchMatches(es, index, parentOf, search)
		if search == nil or search == "" then return true end
		local needle = string.lower(search)
		local model, livery = namesOf(es, index, parentOf)
		return string.find(string.lower(model or ""), needle, 1, true) ~= nil
			or (livery ~= nil and string.find(string.lower(livery), needle, 1, true) ~= nil)
	end

	local function filterParamsNow()
		return { year = currentYear(), anyCargoFilterSet = false, passengerCargoTypeId = passengerId }
	end

	-- the vehicles to show, plus which cargo and engine types they have (for the filter chips)
	local function availableElements(store, filter, opts, s)
		local filterParams = filterParamsNow()
		local data = store.vehiclesStaticData and store.vehiclesStaticData.repId2elementStatic or {}
		local index = pathIndex(data)
		local parentOf = variantIndex(store)
		local funds = opts.affordable and balance() or nil
		-- a filter shows only what matches it: an engine type hides unpowered vehicles, a cargo
		-- type hides vehicles that carry nothing. Tabs where a filter can't apply ignore it
		-- (cargo on Locomotives, engines on Wagons); it stays set for the other tabs.
		local anyCargo = opts.applyCargo ~= false and next(opts.cargo) ~= nil
		local anyEngine = opts.applyEngines ~= false and next(opts.engines) ~= nil
		local presentCargo, presentEngines = {}, {}
		local list = {}
		-- rows the tab would have without our filters (liveries grouped the same way), and how
		-- many liveries / versions of each group the tab has (for the arrow and the picker)
		local total, totalGroups, groupCount = 0, {}, {}
		for key, es in pairs(data) do
			if not es.variantGroupOnly then
				local ok, pass = pcall(vsu.vehicleFilter, es, filterParams, filter)
				local g = (ok and pass) and groupKeyOf(es, parentOf) or nil
				if g then groupCount[g] = (groupCount[g] or 0) + 1 end
				if ok and pass then
					local gl = s.groupLiveries and g or nil
					if gl == nil then total = total + 1
					elseif not totalGroups[gl] then totalGroups[gl] = true; total = total + 1 end
				end
				if ok and pass and searchMatches(es, index, parentOf, opts.search) then
					local d = es.vehicleData
					for id, amount in pairs(d.allCargoTypes or {}) do
						if amount and amount > 0 then presentCargo[id] = true end
					end
					local universal = forAnyCargo(d)
					if universal then presentCargo[ALL_CARGO] = true end
					for t, on in pairs(es.engineTypes or {}) do if on then presentEngines[t] = true end end
					local keep = true
					if anyCargo then
						keep = false
						for id, _ in pairs(opts.cargo) do
							if id == ALL_CARGO then
								if universal then keep = true; break end
							elseif d.allCargoTypes and (d.allCargoTypes[id] or 0) > 0 then keep = true; break end
						end
					end
					if keep and anyEngine then
						keep = false
						for t, _ in pairs(opts.engines) do
							if es.engineTypes and es.engineTypes[t] then keep = true; break end
						end
					end
					if keep and funds ~= nil and (d.price or 0) > funds then keep = false end
					-- key: the vehicle's key in the store's data; the table's row key (must stay the
					-- same vehicle while the table lives, the game's DataTable keeps rows by key)
					if keep then list[#list + 1] = { key = key, static = es, dynamic = { liveries = 1, group = g } } end
				end
			end
		end

		-- one row per model: keep the model itself (or its first livery) and count the others
		if s.groupLiveries then
			local byGroup, grouped = {}, {}
			for _, e in ipairs(list) do
				local key = e.dynamic.group
				if key == nil then
					grouped[#grouped + 1] = e
				else
					local first = byGroup[key]
					if first == nil then
						byGroup[key] = e
						grouped[#grouped + 1] = e
					else
						first.dynamic.liveries = first.dynamic.liveries + 1
						local better = (e.static.path == key) or (first.static.path ~= key and (e.static.repId or 0) < (first.static.repId or 0))
						if better then first.static, first.key = e.static, e.key end
					end
				end
			end
			list = grouped
		end

		for _, e in ipairs(list) do
			local model, livery = namesOf(e.static, index, parentOf)
			e.dynamic.model = model
			e.dynamic.livery = livery
			-- with every variation in its own row there is nothing more to pick: no arrow, no picker
			e.dynamic.options = (s.groupLiveries and e.dynamic.group) and groupCount[e.dynamic.group] or 1
		end
		table.sort(list, function(a, b)
			local ya, yb = a.static.vehicleData.yearFrom or 0, b.static.vehicleData.yearFrom or 0
			if ya ~= yb then return ya < yb end
			return tostring(a.dynamic.model) < tostring(b.dynamic.model)
		end)
		return list, presentCargo, presentEngines, total
	end

	-- the liveries / versions of a vehicle's group the tab has (the vehicle itself included), for
	-- the picker in the details: the model itself first, then by name
	local function optionsOf(store, es, filter)
		local data = store.vehiclesStaticData and store.vehiclesStaticData.repId2elementStatic or {}
		local parentOf = variantIndex(store)
		local g = groupKeyOf(es, parentOf)
		if g == nil then return {}, nil end
		local filterParams = filterParamsNow()
		local out = {}
		for key, other in pairs(data) do
			if not other.variantGroupOnly and (other.multipleUnit and true or false) == (es.multipleUnit and true or false) and groupKeyOf(other, parentOf) == g then
				local ok, pass = pcall(vsu.vehicleFilter, other, filterParams, filter)
				if (ok and pass) or other == es then out[#out + 1] = { key = key, es = other } end
			end
		end
		table.sort(out, function(a, b)
			local pa, pb = a.es.path == g, b.es.path == g
			if pa ~= pb then return pa end
			local na, nb = tostring(a.es.name), tostring(b.es.name)
			if na ~= nb then return na < nb end
			return (a.es.repId or 0) < (b.es.repId or 0)
		end)
		return out, g
	end

	-------------------------------------------------------------------------------------------
	-- trains: numbers and buying
	-------------------------------------------------------------------------------------------
	local function vehiclesOf(es)
		if es.multipleUnit then
			return vsu.makeMultipleVehicles(api.res.multipleUnitRep.get(es.repId))
		end
		return { vsu.makeSingleVehicle(api.res.modelRep.get(es.repId)) }
	end

	-- a train is a list of items: { es = element static, reversed = turned around, color = Vec3f }
	-- own: a car the vehicle being modified already has (Modify): its parts as the game gave them
	-- (they keep their age and value; the game's cart keeps them too), see modifyPlan
	local function trainItem(es, reversed, color, own)
		return { es = es, reversed = reversed and true or false, color = usableColor(color), own = own }
	end

	-------------------------------------------------------------------------------------------
	-- Replace and Modify (the vehicle manager's buttons open the store for vehicles that exist)
	-- The game's store (vehicle_store_window VehicleStoreWindowContent / VehicleCart):
	--  Replace: every vehicle in store.vehicleEntities becomes the one picked (one change each,
	--   vehicleEntity = the old one); the price is the new one's times their number, less what
	--   the old ones are worth now (getDepreciatedValue).
	--  Modify: the cart starts with the vehicle's own cars (their parts from its
	--   TRANSPORT_VEHICLE config, so kept cars keep their age); the change has the vehicle's
	--   entity; the price is new cars at their price plus kept cars at what they are worth
	--   (getPartPrice), less what the vehicle is worth now.
	-- The buyer does Modify for one train; several at once go to the game's store (each keeps
	-- its own cars there, the buyer has one train).
	-------------------------------------------------------------------------------------------
	local rv = {}
	function rv.mode(store)
		local m = store and store.vehicleStoreMode
		if m == "Replace" or m == "Modify" then return m end
		return "Buy"
	end
	-- the vehicles the window is for that still exist
	function rv.entities(store)
		local out = {}
		for _, e in ipairs((store and store.vehicleEntities) or {}) do
			local ok, yes = pcall(function() return api.engine.entityExists(e) end)
			if ok and yes then out[#out + 1] = e end
		end
		return out
	end
	-- what the game pays for them now
	function rv.resale(list)
		local sum = 0
		for _, e in ipairs(list) do
			local ok, v = pcall(function() return api.engine.util.vehicle.getDepreciatedValue(e) end)
			if ok and type(v) == "number" then sum = sum + v end
		end
		return sum
	end
	function rv.partValue(p)
		local ok, v = pcall(function() return api.engine.util.vehicle.getPartPrice(p) end)
		return (ok and type(v) == "number") and v or 0
	end
	function rv.name(entity)
		local ok, n = pcall(function() return api.engine.getComponent(entity, api.type.ComponentType.NAME).name end)
		return (ok and type(n) == "string" and n ~= "") and n or nil
	end
	-- the element static of a model (not a multiple unit) by its model id
	function rv.modelEs(data, id)
		local es = data[id]
		if es and not es.multipleUnit and es.repId == id then return es end
		for _, o in pairs(data) do
			if not o.multipleUnit and o.repId == id and not o.variantGroupOnly then return o end
		end
		return nil
	end
	-- a multiple unit's cars as bought turned around? (partsOf: last car first, each one turned).
	-- Every car is compared: a unit of the same cars only differs in which way they face. One that
	-- matches neither way counts as not turned (its parts are kept as they are either way; this
	-- only decides which way its picture faces and what turning it does)
	function rv.muReversed(es, parts)
		local mu = api.res.multipleUnitRep.get(es.repId)
		local cars = mu and mu.vehicles or {}
		local n = #cars
		if n == 0 or n ~= #parts then return false end
		local function matches(turned)
			for k = 1, n do
				local car = turned and cars[n - k + 1] or cars[k]
				local p = parts[k].part
				local rev = p.reversed and true or false
				local want = not car.forward          -- (makePart: reversed = not forward)
				if turned then want = not want end    -- (turned: each car the other way)
				if p.modelId ~= api.res.modelRep.find(car.name) or rev ~= want then return false end
			end
			return true
		end
		if matches(false) then return false end
		return matches(true)
	end
	-- the train to start Modify with: the vehicle's cars as train items (each keeps its parts),
	-- or nil and why (then the game's store opens)
	function rv.modifyPlan(store)
		local list = store.vehicleEntities
		if type(list) ~= "table" or #list ~= 1 then return nil, "more than one vehicle" end
		if not vsu.acceptsMultiVehicle(store.carrier) then return nil, "not a train or tram" end
		local entity = list[1]
		local tv = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
		local cfg = tv and tv.transportVehicleConfig
		if cfg == nil then return nil, "no vehicle config" end
		local data = store.vehiclesStaticData and store.vehiclesStaticData.repId2elementStatic or {}
		local index = pathIndex(data)
		local vehicles, groups, muNames = cfg.vehicles or {}, cfg.vehicleGroups or {}, cfg.muFileNames or {}
		local nGroups = #groups
		if nGroups == 0 then
			-- (no groups: every part is a vehicle of its own)
			groups = {}
			for i = 1, #vehicles do groups[i] = 1 end
			nGroups = #groups
		end
		local items, from = {}, 1
		for i = 1, nGroups do
			local n = groups[i]
			local mu = muNames[i] or ""
			local parts, rev = {}, {}
			for j = from, from + n - 1 do
				local p = vehicles[j]
				if p == nil then return nil, "config shorter than its groups" end
				parts[#parts + 1] = p
				rev[#rev + 1] = p.part.reversed and true or false
			end
			from = from + n
			local es, reversed
			if mu ~= "" then
				es = index[mu]
				if es == nil or not es.multipleUnit then return nil, "unknown multiple unit " .. tostring(mu) end
				reversed = rv.muReversed(es, parts)
			else
				if n ~= 1 then return nil, "a group of " .. tostring(n) .. " without a multiple unit" end
				es = rv.modelEs(data, parts[1].part.modelId)
				if es == nil then return nil, "unknown model " .. tostring(parts[1].part.modelId) end
				reversed = rev[1]
			end
			items[#items + 1] = trainItem(es, reversed, parts[1].part.color, { parts = parts, rev = rev, reversed = reversed, mu = mu })
		end
		if #items == 0 then return nil, "no cars" end
		return items
	end
	-- the plans of the Modify windows opened (by their params, like `choice` below)
	rv.plans = {}
	function rv.planFor(store)
		local p = rv.plans[store]
		if p == nil then
			local ok, items, why = pcall(rv.modifyPlan, store)
			if not ok then why = items; items = nil end
			if items == nil then core.log("modify: the game's store (" .. tostring(why) .. ")") end
			p = items or false
			rv.plans[store] = p
		end
		return p or nil
	end
	-- can the buyer do what this store window is for?
	function rv.supported(store)
		local m = store and store.vehicleStoreMode
		if m == "Modify" then return rv.planFor(store) ~= nil end
		return m == "Buy" or m == "Replace"
	end
	M._rv = rv -- for tests

	-- VehicleData of the whole train, the same way the store sums up its cart
	local function trainData(entries)
		local all = {}
		for _, it in ipairs(entries) do
			for _, v in ipairs(vehiclesOf(it.es)) do all[#all + 1] = v end
		end
		if #all == 0 then return nil end
		return vsu.collectVehicleData(all)
	end

	-- the parts to buy, like the store's cart: a multiple unit gives one part per car; turned
	-- around, its cars come last-first and each one is turned (the cart's own Reverse does that)
	local function partsOf(entries)
		local parts, groups, muFiles, quantity = {}, {}, {}, {}
		for _, it in ipairs(entries) do
			local es = it.es
			local color = usableColor(it.color)
			if it.own then
				-- a car the vehicle already has (Modify): its own parts, in the order and the way
				-- round of the train (turned: last part first, each one turned, like the game's
				-- cart). The way round is set from the part's own, so doing it again changes nothing
				local o = it.own
				local flip = (it.reversed and true or false) ~= (o.reversed and true or false)
				local n = #o.parts
				for k = 1, n do
					local idx = flip and (n - k + 1) or k
					local p = o.parts[idx]
					if flip then p.part.reversed = not o.rev[idx] else p.part.reversed = o.rev[idx] end
					parts[#parts + 1] = p
				end
				groups[#groups + 1] = n
				muFiles[#muFiles + 1] = o.mu or ""
			elseif es.multipleUnit then
				local mu = api.res.multipleUnitRep.get(es.repId)
				local cars = {}
				for _, v in ipairs(mu.vehicles) do cars[#cars + 1] = v end
				local from, to, step = 1, #cars, 1
				if it.reversed then from, to, step = #cars, 1, -1 end
				for i = from, to, step do
					local v = cars[i]
					local id = api.res.modelRep.find(v.name)
					local forward = v.forward
					if it.reversed then forward = not forward end
					parts[#parts + 1] = vu.makePart(id, forward, color)
					quantity[id] = (quantity[id] or 0) + 1
				end
				groups[#groups + 1] = #cars
				muFiles[#muFiles + 1] = es.path
			else
				parts[#parts + 1] = vu.makePart(es.repId, not it.reversed, color)
				quantity[es.repId] = (quantity[es.repId] or 0) + 1
				groups[#groups + 1] = 1
				muFiles[#muFiles + 1] = ""
			end
		end
		return parts, groups, muFiles, quantity
	end

	-- buys `entries` as one vehicle (a train for rail and tram, a single vehicle otherwise)
	local function buy(store, entries, single, onDone)
		local parts, groups, muFiles, quantity = partsOf(entries)
		if #parts == 0 then return false, "Nothing to buy" end
		local config = api.type.TransportVehicleConfig.new()
		config.vehicles = parts
		config.vehicleGroups = groups
		config.muFileNames = single and {} or muFiles
		-- Buy: one new vehicle; Replace: each old one gets this config; Modify: the vehicle itself
		local changes = {}
		local mode = rv.mode(store)
		if mode == "Buy" then
			changes[1] = { vehicleEntity = -1, config = config }
		else
			for _, e in ipairs(rv.entities(store)) do
				changes[#changes + 1] = { vehicleEntity = e, config = config }
				if mode == "Modify" then break end
			end
			if #changes == 0 then return false, "the vehicles are gone" end
		end
		-- (missions count new parts only: kept cars aren't bought again, like the game's cart)
		local missionError = missionEvent("mission.buyVehicle", { modelId2quantity = quantity, actuallyBuy = false })
		if missionError then return false, missionError end
		missionEvent("mission.vehiclesBought", { modelId2quantity = quantity })
		missionEvent("mission.buyVehicle", { modelId2quantity = quantity, actuallyBuy = true })
		local protected = nil
		pcall(function() protected = store.gameCtx.filters:get().protectedEntities end)
		vru.HandleVehicleChanges(
			changes,
			protected or {},
			function(vehicleEntity)
				if vehicleEntity < 0 and store.depot == nil then
					return api.engine.util.vehicle.findBestLineAndDepotForVehicle(-vehicleEntity - 1)
				end
				return { -1, store.depot }
			end,
			store.getFirstStopToSendTo,
			function(result)
				if store.buyCallback then
					local ok, err = pcall(store.buyCallback, result)
					if not ok then fail("the store's buy callback", err) end
				end
				if onDone then onDone(true) end
			end,
			function(reason)
				if onDone then onDone(false, reason) end
			end
		)
		if store.onAccepted then store.onAccepted(changes) end
		return true
	end

	-- the train's Buy button for the window's mode: its cost (what the money goes down by), label
	-- and tooltip
	function rv.trainButton(store, entries, d)
		local mode = rv.mode(store)
		local price = d and d.price or 0
		if mode == "Replace" then
			local list = rv.entities(store)
			local resale = rv.resale(list)
			local cost = price * #list - resale
			local label = #entries == 0 and "Replace" or ((#list == 1 and "Replace for " or ("Replace " .. core.int(#list) .. " for ")) .. money(cost))
			return cost, label, (#list == 1 and "The vehicle becomes this train: " or ("Each of the " .. core.int(#list) .. " vehicles becomes this train: " .. core.int(#list) .. TIMES .. " "))
				.. money(price) .. ", less " .. money(resale) .. " for " .. (#list == 1 and "the old one" or "the old ones") .. " (what they are worth now)"
		elseif mode == "Modify" then
			local new, kept = {}, 0
			for _, it in ipairs(entries) do
				if it.own then
					for _, p in ipairs(it.own.parts) do kept = kept + rv.partValue(p) end
				else
					new[#new + 1] = it
				end
			end
			local okN, dn = pcall(trainData, new)
			local newPrice = (okN and dn and dn.price) or 0
			local resale = rv.resale(rv.entities(store))
			local cost = newPrice + kept - resale
			local label = #entries == 0 and "Modify" or (cost >= 0 and ("Modify for " .. money(cost)) or ("Modify (" .. money(-cost) .. " back)"))
			return cost, label, "New cars " .. money(newPrice) .. " + the cars it keeps " .. money(kept)
				.. " (what they are worth now), less " .. money(resale) .. " for the train as it is"
		end
		return price, #entries > 0 and ("Buy for " .. money(price)) or "Buy", "Buy this train; it starts in the depot"
	end
	-- one vehicle (road, water, air): Replace gives each old vehicle this one
	function rv.singleCost(store, price)
		local list = rv.entities(store)
		local resale = rv.resale(list)
		return price * #list - resale, #list, resale
	end

	-- how many more of wagon `it` the train can take before the pull limit (slope and weight setting)
	local function fillCount(d, it, s)
		if d == nil or it == nil then return 0 end
		local w = it.es.vehicleData
		local wagonW = core.trainWeightOf(w, s)
		if wagonW <= 0 then return 0 end
		local wagonFr = (w.rollingFriction and w.rollingFriction > 0) and w.rollingFriction or 0.02
		local W = core.trainWeightOf(d, s)
		local fr = d.rollingFriction or 0
		local top = math.min(d.speed or 0, (w.speed and w.speed > 0) and w.speed or math.huge)
		if (d.tractiveEffort or 0) <= 0 or (d.power or 0) <= 0 or top <= 0 or top == math.huge then return 0 end
		local n = 0
		while n < 200 do
			local limit = core.pullLimit(d.power, d.tractiveEffort, top / 2, core.slopeValue(s), fr + wagonFr)
			if W + wagonW > limit then break end
			W, fr, n = W + wagonW, fr + wagonFr, n + 1
		end
		return n
	end

	-------------------------------------------------------------------------------------------
	-- table cells (each returns a layout, or nil for an empty cell like the game's cells)
	-------------------------------------------------------------------------------------------
	local function cellElem(params)
		local up = params.userParam
		local byKey = up and up.byKey
		return byKey and byKey[params.rowKey], up
	end

	local function guarded(name, fn)
		return function(params)
			local ok, node = pcall(fn, params)
			if ok then return node end
			fail("cell " .. name, node)
			return nil
		end
	end

	-- is this row's details card open? Cells keep the userParam they were made with (the game's
	-- DataTable), so they read the open row from a ref every frame (the way the game's docs say)
	-- (second value, controller only: the row has the focus, lit across all its cells)
	local function useOpen(up, key)
		if up == nil or up.openRef == nil or type(react.onStep) ~= "function" then return false, false end
		local function look()
			local v = (up.openRef:get() == key) and 1 or 0
			local f = up.focusRowRef and up.focusRowRef:get()
			if type(f) == "table" and (f.name == key or f.add == key) then v = v + 2 end
			return v
		end
		local st = react.useState(look())
		-- a plain step callback (lighter than useStepState: one comparison per cell and frame)
		react.onStep(function()
			local now = look()
			if now ~= st:old() then st:set(now) end
		end)
		local v = st:old() or 0
		return v % 2 == 1, v >= 2
	end
	-- controller: a row takes the focus in two places only, its name (A: details) and its + Add /
	-- Buy (A: add or buy), so left / right go straight from one to the other instead of through
	-- every number (Ethan, 5 Oct); while either has the focus the whole row is lit as one box
	-- Each stop keeps its own entry (which: "name" or "add"): moving from + Add back to the name,
	-- the name gets the focus before + Add loses it, and one shared entry was cleared by that, so
	-- only the name stayed lit (Ethan, 5 Oct)
	local function rowAttention(up, key, which)
		if not (up and up.pad and up.focusRowRef) then return nil end
		return function(v)
			local f = up.focusRowRef:get()
			local n = { name = type(f) == "table" and f.name or nil, add = type(f) == "table" and f.add or nil }
			if v then n[which] = key elseif n[which] == key then n[which] = nil end
			up.focusRowRef:set(n)
		end
	end

	-- every cell of a row is a see-through button that opens the vehicle's details, so a click
	-- anywhere on the row works (empty cells too); no frame on hover or click, and the row whose
	-- details are open is tinted across all its cells
	-- controller: LB / RB on a row sort by the column before / after (the headers can't be clicked)
	local function rowSortKeys(up)
		if not (up and up.pad and canIA and up.sortStep) then return end
		react.useInputAction("IA_TABLEFT", react.iaHandler(function() up.sortStep(-1) end, nil, "Sort by the column before"))
		react.useInputAction("IA_TABRIGHT", react.iaHandler(function() up.sortStep(1) end, nil, "Sort by the next column"))
	end

	-- (stop: the name cell, where a controller's focus stops; lit: see useOpen)
	local function rowCell(params, up, children, orientation, extraClass, open, tooltip, lit, stop)
		local key = params.rowKey
		if open == nil then open, lit = useOpen(up, key) end
		-- the cell's own recipe fills its table cell (CSS), so the tint covers the whole row
		if type(react.setStyleClasses) == "function" then react.setStyleClasses("vh-cell-recipe") end
		local pad = up and up.pad
		return box(H, {
			builtin.Button{
				-- controller: vh-pad on the name (the game shows the focus as :hover, which these
				-- see-through buttons otherwise hide), vh-row-lit on the rest of the focused row,
				-- and the numbers take no focus
				meta = { class = "vh-row-button" .. (open and ", vh-row-open" or "") .. ((pad and stop) and ", vh-pad" or "")
						.. ((pad and lit) and ", vh-row-lit" or ""),
					tooltip = tooltip,
					disableFocusableRecursive = (pad and not stop) and true or nil,
					onAttention = stop and rowAttention(up, key, "name") or nil },
				content = box(orientation or V, children, "vh-cell-inner" .. (extraClass and (", " .. extraClass) or "")),
				onClick = function() if up and up.select then up.select(key) end end,
			},
		}, "vh-cell")
	end

	-- the numbers in the table use the game's table font (its own table writes them in
	-- font-scale-annotation, a size smaller than the text elsewhere): at 1920 x 1080 the store
	-- window can't get wider than about 1110, and in the body size "220 km/h", "5,920 kW" and
	-- "1.01 m/s²" were cut off (Ethan's screenshots, 4 Oct)
	local CELL_TEXT, METRIC_TEXT = "vh-cell-text, font-scale-annotation", "vh-metric-text, font-scale-annotation"
	local function textCell(key, getText)
		return react.RegisterRecipe("VhBuyerCell_" .. key, guarded(key, function(params)
			local elem, up = cellElem(params)
			if elem == nil then return nil end
			-- getText may also give the full value, shown as the tooltip when the cell has a short one
			local t, full = getText(elem.static, metricsFor(elem.static.vehicleData))
			-- an empty cell shows a dash (an empty button got no size, so the row's tint had holes)
			return rowCell(params, up, { t ~= nil and text(t, CELL_TEXT) or text(DASH, CELL_TEXT .. ", vh-cell-empty") },
				nil, nil, nil, (full ~= nil and full ~= t) and full or nil)
		end))
	end

	-- min / max of one of our numbers over the rows shown, for the bars
	local function rangeOf(up, key)
		up.ranges = up.ranges or {}
		local r = up.ranges[key]
		if r == nil then
			r = {}
			for _, e in ipairs(up.elements) do
				local v = metricsFor(e.static.vehicleData)[key]
				if v then
					if r.min == nil or v < r.min then r.min = v end
					if r.max == nil or v > r.max then r.max = v end
				end
			end
			up.ranges[key] = r
		end
		return r
	end

	local function metricCell(key, format, lowerIsBetter)
		return react.RegisterRecipe("VhBuyerCell_" .. key, guarded(key, function(params)
			local elem, up = cellElem(params)
			if elem == nil then return nil end
			local v = metricsFor(elem.static.vehicleData)[key]
			if v == nil then return rowCell(params, up, { text(DASH, METRIC_TEXT .. ", vh-cell-empty") }) end
			local r = rangeOf(up, key)
			local x = 1
			if r.min and r.max and r.max > r.min then
				x = (v - r.min) / (r.max - r.min)
				if lowerIsBetter then x = 1 - x end
			end
			local shown, full = format(v)
			-- the bar spans its column, less a gap (a fixed 64 px bar was as wide as the narrower
			-- columns, so the bars of two columns ran into each other, Ethan 5 Oct)
			return rowCell(params, up, {
				text(shown, METRIC_TEXT),
				builtin.ProgressBar{ meta = { class = "vh-metric-bar" }, value = math.max(0.04, math.min(1, x)) },
			}, nil, "vh-metric-inner", nil, (full ~= nil and full ~= shown) and full or nil)
		end))
	end

	-- the table's short numbers, so 14 columns fit (the details and the train show them in full,
	-- and a short cell shows the full value as its tooltip), three digits: 12.1k from 10,000,
	-- 157k from 100,000, 6.70M from a million, 63.3M from ten million, 120M from a hundred million
	local function shortNumber(n)
		local a = math.abs(n)
		-- rounded first, then the unit picked, so 999,600 reads 1.00M (not 1000k) and 99,960
		-- reads 100k (not 100.0k)
		if a >= 99950000 then return string.format("%dM", math.floor(n / 1e6 + 0.5)) end
		if a >= 9995000 then return string.format("%.1fM", n / 1e6) end
		if a >= 999500 then return string.format("%.2fM", n / 1e6) end
		if a >= 99950 then return string.format("%dk", math.floor(n / 1000 + 0.5)) end
		if a >= 1e4 then return string.format("%.1fk", n / 1000) end
		return nil
	end
	-- money with the game's own currency sign, short from 100,000 on ($791k, $6.70M)
	local function shortMoney(v)
		local full = money(v)
		if math.abs(v) < 1e5 then return full, full end
		local prefix = full:match("^([^%d]*)") or ""
		local suffix = full:match("%d([^%d]*)$") or ""
		return prefix .. shortNumber(v) .. suffix, full
	end
	-- a number with its unit from the game's formatter ("157,366 lbf"), short from 10,000 on;
	-- left as it is when the number isn't written with commas (another language's separators)
	local function shortUnit(str)
		if type(str) ~= "string" then return str, str end
		local num, unit = str:match("^([%d,]+)(.*)$")
		if num == nil or not num:find(",", 1, true) or unit:find("^[%.%d]") then return str, str end
		local n = tonumber((num:gsub(",", "")))
		local short = n and shortNumber(n)
		if short == nil then return str, str end
		return short .. unit, str
	end

	local function cargoSummary(d)
		if forAnyCargo(d) then
			return carriesPassengers(d) and "Passengers, all cargo" or "All cargo"
		end
		local names = {}
		for id, amount in pairs(d.allCargoTypes or {}) do
			if amount and amount > 0 then names[#names + 1] = cargoInfo(id).name end
		end
		table.sort(names)
		if #names == 0 then return nil end
		if #names > 3 then return core.int(#names) .. " cargo types" end
		return table.concat(names, ", ")
	end

	local function engineSummary(es)
		local names = {}
		for _, e in ipairs(engineEnum()) do
			if es.engineTypes and es.engineTypes[e.value] then names[#names + 1] = e.name end
		end
		return #names > 0 and table.concat(names, "/") or nil
	end

	local NameCell = react.RegisterRecipe("VhBuyerCell_name", guarded("name", function(params)
		local elem, up = cellElem(params)
		if elem == nil then return nil end
		local open, lit = useOpen(up, params.rowKey)
		rowSortKeys(up)
		local es, dyn = elem.static, elem.dynamic or {}
		local sub = {}
		if dyn.livery then sub[#sub + 1] = dyn.livery end
		local options = math.max(dyn.options or 1, dyn.liveries or 1)
		if options > 1 then sub[#sub + 1] = core.int(options) .. " variations" end
		if es.multipleUnit then sub[#sub + 1] = core.int(#(es.icons or {})) .. "-car unit" end
		local engines = es.hasEngine and engineSummary(es) or nil
		if engines then sub[#sub + 1] = engines end
		local cargo = cargoSummary(es.vehicleData)
		if cargo then sub[#sub + 1] = cargo end
		if es.vehicleData.isReversible then sub[#sub + 1] = "Reversible" end
		local children = {}
		if up.pictures then
			-- a fixed-size window: long trains show their front, and names line up
			children[#children + 1] = clip(vehiclePictures(es, false, nil, "vh-icon", 4), "vh-icons-clip")
		end
		-- the note line starts with the game's arrow when there are more liveries or versions
		-- (pick one in the details), so it stays visible however narrow the column is
		local subRow = {}
		if options > 1 then subRow[#subRow + 1] = image(open and ARROW_UP or ARROW_DOWN, "vh-arrow") end
		if #sub > 0 then subRow[#subRow + 1] = text(table.concat(sub, DOT), "vh-sub, font-scale-annotation") end
		-- light rail gets a tag next to the name (like the store's), where it can't be cut off
		local nameLine = text(dyn.model or es.name, "vh-name" .. (open and ", vh-name-open" or ""))
		if es.vehicleData.isLightrail then
			nameLine = box(H, { builtin.TextView{ meta = { class = "vh-tag, font-scale-annotation", tooltip = "Light rail: runs on tram and rail tracks" }, text = "Light rail" }, nameLine }, "vh-name-line")
		end
		children[#children + 1] = clip({
			nameLine,
			#subRow > 0 and box(H, subRow, "vh-sub-row") or nil,
		}, "vh-name-clip", V)
		return rowCell(params, up, children, H, "vh-name-inner", open, nil, lit, true)
	end))

	local AddCell = react.RegisterRecipe("VhBuyerCell_add", guarded("add", function(params)
		local elem, up = cellElem(params)
		if elem == nil or up == nil then return nil end
		local open, lit = useOpen(up, params.rowKey)
		rowSortKeys(up)
		if type(react.setStyleClasses) == "function" then react.setStyleClasses("vh-cell-recipe") end
		local es = elem.static
		local label, tip, onClick
		if up.single and up.replace then
			-- Replace (one vehicle each): the old ones get this one, like the game's Replace button
			local r = up.replace
			local price = es.vehicleData.price or 0
			label, onClick = "Replace", function() up.buyNow(es) end
			tip = (r.count == 1 and "Replace the vehicle with this one: " or ("Replace the " .. core.int(r.count) .. " vehicles with this one: " .. core.int(r.count) .. TIMES .. " "))
				.. money(price) .. ", less " .. money(r.resale) .. " for the old " .. (r.count == 1 and "one" or "ones") .. " = " .. money(price * r.count - r.resale)
		elseif up.single then
			label, tip, onClick = "Buy", "Buy one now for " .. money(es.vehicleData.price), function() up.buyNow(es) end
		else
			label, tip, onClick = "+ Add", "Add to the train", function() up.add(es) end
		end
		-- (the row's second controller stop: it lights the row too)
		local b = builtin.Button{
			meta = { tooltip = tip, class = "vh-button, vh-add", onAttention = rowAttention(up, params.rowKey, "add") },
			content = builtin.TextView{ text = label },
			onClick = onClick,
		}
		-- a panel behind the button, tinted with the rest of the row when its details are open
		return box(V, {
			builtin.Component{ meta = { class = "vh-add-bg" .. (open and ", vh-row-open" or "") .. ((up.pad and lit) and ", vh-row-lit" or "") },
				layout = box(V, { b }, "vh-add-box") },
		}, "vh-cell")
	end))

	local cells = {
		year = textCell("year", function(es) return tostring(es.vehicleData.yearFrom or "") end),
		capacity = textCell("capacity", function(es) return (es.vehicleData.totalCapacity or 0) > 0 and core.int(es.vehicleData.totalCapacity) or nil end),
		speed = textCell("speed", function(es) return speed(es.vehicleData.speed) end),
		power = textCell("power", function(es) if (es.vehicleData.power or 0) > 0 then return shortUnit(power(es.vehicleData.power)) end end),
		te = textCell("te", function(es) if (es.vehicleData.tractiveEffort or 0) > 0 then return shortUnit(force(es.vehicleData.tractiveEffort)) end end),
		weight = textCell("weight", function(es) return weight(es.vehicleData.weight or 0) end),
		price = textCell("price", function(es) return shortMoney(es.vehicleData.price or 0) end),
		upkeep = textCell("upkeep", function(es) local short, full = shortMoney(es.vehicleData.runningCosts or 0); return short, full .. "/yr" end),
		pricePerCargo = metricCell("pricePerCargo", function(v) return shortMoney(v) end, true),
		upkeepPerCargo = metricCell("upkeepPerCargo", function(v) local short, full = shortMoney(v); return short, full .. "/yr" end, true),
		accel = metricCell("accel", function(v) return core.accel(v) end, false),
		pull = metricCell("pull", function(v) return core.int(v) .. " t" end, false),
		selfTime = metricCell("selfTime", function(v) return core.seconds(v) end, true),
		loading = metricCell("loadingSpeed", function(v) return string.format("%.1f\195\151", v) end, false),
		thrust = textCell("thrust", function(es) if (es.vehicleData.thrust or 0) > 0 then return shortUnit(force(es.vehicleData.thrust)) end end),
		powerPerWeight = metricCell("powerPerWeight", function(v) return powerPerTonne(v) end, false),
	}

	-- all columns. `hide`: tabs (and "single" = road/water/air) where a column means nothing;
	-- `only`: the column is shown only there; `has`: the column is hidden when no vehicle in the
	-- list has a value for it
	local COLUMNS = {
		{ key = "name", name = "Vehicle", tooltip = "Model; livery, engine, cargo and other notes below. Click anywhere on a row for its details; an arrow means more variations (pick one in the details)", recipe = NameCell, weight = 9,
			compare = function(e) return tostring(e.dynamic.model or e.static.name) end },
		-- (a year needs about 50 px: weight 2 cut the last digit with a road depot's extra columns)
		{ key = "year", name = "Year", tooltip = "Available from", recipe = cells.year, weight = 2.6,
			compare = function(e) return e.static.vehicleData.yearFrom or 0 end },
		{ key = "capacity", name = "Cap.", tooltip = "Capacity", recipe = cells.capacity, weight = 2.2, hide = { locomotive = true },
			has = function(es) return (es.vehicleData.totalCapacity or 0) > 0 end,
			compare = function(e) return e.static.vehicleData.totalCapacity or 0 end },
		{ key = "speed", name = "Speed", tooltip = "Top speed", recipe = cells.speed, weight = 3.3,
			compare = function(e) return e.static.vehicleData.speed or 0 end },
		{ key = "power", name = "Power", tooltip = "Power", recipe = cells.power, weight = 3.3, hide = { waggon = true },
			has = function(es) return (es.vehicleData.power or 0) > 0 end,
			compare = function(e) return e.static.vehicleData.power or 0 end },
		{ key = "te", name = "TE", tooltip = "Tractive effort", recipe = cells.te, weight = 3.6, hide = { waggon = true },
			has = function(es) return (es.vehicleData.tractiveEffort or 0) > 0 end,
			compare = function(e) return e.static.vehicleData.tractiveEffort or 0 end },
		{ key = "thrust", name = "Thrust", tooltip = "Thrust", recipe = cells.thrust, weight = 3.3, only = { single = true },
			has = function(es) return (es.vehicleData.thrust or 0) > 0 end,
			compare = function(e) return e.static.vehicleData.thrust or 0 end },
		-- planes and helicopters have no cargo weight in their data: the weight isn't worth a column
		{ key = "weight", name = "Weight", tooltip = "Empty weight", recipe = cells.weight, weight = 3.1, hide = { AIR = true },
			compare = function(e) return e.static.vehicleData.weight or 0 end },
		{ key = "price", name = "Price", tooltip = "Purchase price (short: k = thousand, M = million; hover a cell for the full price)", recipe = cells.price, weight = 3.2,
			compare = function(e) return e.static.vehicleData.price or 0 end },
		{ key = "upkeep", name = "Upkeep", tooltip = "Yearly running costs (short: k = thousand, M = million; hover a cell for the full amount)", recipe = cells.upkeep, weight = 3.2,
			compare = function(e) return e.static.vehicleData.runningCosts or 0 end },
		{ key = "loading", name = "Loading", tooltip = "Loading speed: how fast cargo gets on and off, the game's multiplier (Enhanced Store)", recipe = cells.loading, weight = 3.2, hide = { locomotive = true, railAll = true },
			has = function(es, m) return m.loadingSpeed ~= nil end,
			compare = function(e, m) return m.loadingSpeed or -1 end },
		{ key = "pricePerCargo", name = "$/cargo", tooltip = "Price per unit of capacity (Enhanced Store)", recipe = cells.pricePerCargo, weight = 3.1, hide = { locomotive = true },
			has = function(es, m) return m.pricePerCargo ~= nil end,
			compare = function(e, m) return m.pricePerCargo or 1e15 end },
		{ key = "upkeepPerCargo", name = "Upk./cargo", tooltip = "Upkeep per cargo: yearly running costs per unit of capacity (Enhanced Store)", recipe = cells.upkeepPerCargo, weight = 4.2, hide = { locomotive = true },
			has = function(es, m) return m.upkeepPerCargo ~= nil end,
			compare = function(e, m) return m.upkeepPerCargo or 1e15 end },
		{ key = "accel", name = "Accel.", tooltip = "Acceleration from a stop on its own, loaded (or empty, see Settings); your train's real acceleration shows in the train panel (Enhanced Store)", recipe = cells.accel, weight = 3.6, hide = { waggon = true },
			has = function(es, m) return m.accel ~= nil end,
			compare = function(e, m) return m.accel or -1 end },
		{ key = "pull", name = "Pull", tooltip = "Heaviest load it can start and haul at half its top speed on the slope set in Settings (Enhanced Store)", recipe = cells.pull, weight = 2.8, hide = { waggon = true, single = true },
			has = function(es, m) return m.pull ~= nil end,
			compare = function(e, m) return m.pull or -1 end },
		{ key = "selfTime", name = "0\226\128\147top", tooltip = "Seconds from a stop to its top speed, on the flat (Enhanced Store)", recipe = cells.selfTime, weight = 2.6, only = { single = true },
			has = function(es, m) return m.selfTime ~= nil end,
			compare = function(e, m) return m.selfTime or 1e15 end },
		-- ships: the game works out a ship's pushing force inside the engine (from its propeller),
		-- so no m/s²; power per tonne compares how quickly they get going
		{ key = "powerPerWeight", name = "Power/t", tooltip = "Power per tonne, loaded (or empty, see Settings): more gets a ship up to speed quicker (Enhanced Store)", recipe = cells.powerPerWeight, weight = 3, only = { WATER = true },
			has = function(es, m) return m.powerPerWeight ~= nil end,
			compare = function(e, m) return m.powerPerWeight or -1 end },
		{ key = "add", name = " ", recipe = AddCell, weight = 3.8,
			compare = function(e) return e.static.vehicleData.price or 0 end },
	}

	-- kind: the depot's carrier by name ("AIR", "WATER", ...), for columns of one kind only
	local function visibleColumns(tabId, single, elements, kind)
		local out = {}
		for _, c in ipairs(COLUMNS) do
			local hidden = c.hide and (c.hide[tabId] or (single and c.hide.single) or (c.hide.railAll and tabId == "all" and not single)
				or (kind ~= nil and c.hide[kind]))
			if c.only and not (c.only[tabId] or (single and c.only.single) or (kind ~= nil and c.only[kind])) then hidden = true end
			if not hidden and c.has then
				hidden = true
				for _, e in ipairs(elements) do
					local ok, yes = pcall(c.has, e.static, metricsFor(e.static.vehicleData))
					if ok and yes then hidden = false; break end
				end
			end
			if not hidden then out[#out + 1] = c end
		end
		return out
	end

	-- a column's sort value for a row, never the same for two rows: ties go by the rows' own order
	-- (year, then name: e.rank). So the table's order is exactly ours, in both directions, and the
	-- buyer knows which row the table shows first (to scroll there after a sort or a filter)
	local function sortValue(col, e)
		local ok, v = pcall(col.compare, e, metricsFor(e.static.vehicleData))
		local rank = e.rank or 0
		if col.key == "name" then
			return (ok and v ~= nil and tostring(v) or "") .. "\1" .. string.format("%06d", rank)
		end
		v = (ok and type(v) == "number") and v or 0
		return v + rank * math.max(math.abs(v), 1) * 1e-12
	end
	M._sortValue = sortValue
	local sortLogs = 0 -- the first few header sorts are logged (to check the order in game)
	M._resetSortLogs = function() sortLogs = 0 end -- for tests
	-- the row keys in the order the table shows them with this column and direction
	local function sortedKeys(keys, byKey, col, ascending)
		local out, value = {}, {}
		for i, k in ipairs(keys) do
			out[i] = k
			value[k] = byKey[k] and sortValue(col, byKey[k]) or 0
		end
		if col == nil or col.compare == nil then return out end
		table.sort(out, function(a, b)
			local va, vb = value[a], value[b]
			if type(va) ~= type(vb) then return tostring(a) < tostring(b) end
			if va == vb then return tostring(a) < tostring(b) end
			if ascending then return va < vb end
			return va > vb
		end)
		return out
	end

	local function columnNodes(cols, byKey)
		local nodes = {}
		for _, c in ipairs(cols) do
			nodes[#nodes + 1] = builtin.ColumnDesc{
				name = c.name,
				tooltip = c.tooltip,
				recipe = c.recipe,
				headerStyleClass = c.key ~= "name" and "centered" or nil,
				weight = c.weight,
				getCompareValue = function(rowKey)
					local e = byKey[rowKey]
					if e == nil then return 0 end
					return sortValue(c, e)
				end,
			}
		end
		return nodes
	end

	-------------------------------------------------------------------------------------------
	-- the train panel
	-------------------------------------------------------------------------------------------
	-- only vehicles where the way round matters get a reverse button: locomotives, multiple units,
	-- railcars (they have an engine and a front) and cab cars (reversible); a plain wagon is the
	-- same either way
	local function canTurn(es)
		return (es.hasEngine and true or false) or (es.vehicleData and es.vehicleData.isReversible == true)
	end

	-- runs of the same vehicle, the same way round and the same color, shown as one tile; a
	-- vehicle that can be turned around (locomotive, multiple unit, cab car) always gets a tile of
	-- its own, so each one can be turned and moved by itself
	local function groupEntries(entries)
		local groups = {}
		for i, it in ipairs(entries) do
			local last = groups[#groups]
			if last and not canTurn(it.es) and last.it.es.repId == it.es.repId and last.it.es.multipleUnit == it.es.multipleUnit
				and last.it.reversed == it.reversed and colorKey(last.it.color) == colorKey(it.color) then
				last.count = last.count + 1
				last.last = i
			else
				groups[#groups + 1] = { it = it, es = it.es, count = 1, first = i, last = i }
			end
		end
		return groups
	end

	-- the train, like the game's cart (vehicle_store_window VehicleCartVehicle / VehicleCartDnd):
	-- a tile per vehicle (a stack for runs of the same wagon); hovering one shows the game's
	-- buttons, turn around top left and take off top right, and the grip; drag a tile onto the
	-- left or right half of another to move it there (that half lights up, with a bar on its
	-- edge). A stack has its x for the whole stack top left and - (one wagon) top right, where a
	-- single vehicle's x is. Drags use the game's own drag-and-drop type with a mark of ours, so
	-- only our tiles take them.
	local DND_RES = "::/gui/line_vehicle_mgmt/dnd_train_composition.res"
	local DND_MARK = 7077
	local CLOSE_ICON = ICON .. "close.tga"
	local GRIP_ICON = ICON .. "drag_horizontal_20.tga"
	local function moveButton(content, onClick, tooltip)
		return builtin.Button{
			meta = { tooltip = tooltip, class = "vh-move-button" },
			content = content,
			onClick = function()
				local ok, err = pcall(onClick)
				if not ok then fail("a train button", err) end
			end,
		}
	end
	local function iconContent(path)
		return builtin.ImageView{ meta = { class = "vh-move-icon" }, path = path,
			scaling = builtin.type.ImageViewScaling and builtin.type.ImageViewScaling.AutoFit or nil }
	end

	-- the vehicles a drag carries (first, last), or nil when it isn't one of ours
	local function dragged(ctx)
		local item = ctx.getItems()[1]
		local data = item and item.data
		if data == nil or data.vehicleIndex ~= DND_MARK or type(data.partIndex) ~= "number" then return nil end
		return math.floor(data.partIndex / 100000), data.partIndex % 100000
	end

	-- one half of a tile: where a dragged tile is dropped (Left: before it, Right: after it)
	local VhCartDnd = react.RegisterRecipe("VhCartDnd", function(p)
		if type(react.onDragAndDrop) == "function" then
			react.onDragAndDrop({
				grab = function()
					local ok, item = pcall(function()
						-- first and last vehicle of the tile in one number (a plain payload, like the game's)
						return api.gui.DataTransferItem.new(DND_RES, { vehicleIndex = DND_MARK, partIndex = p.first * 100000 + p.last })
					end)
					if not ok then fail("dragging a vehicle", item); return nil end
					if p.setGrabbed then p.setGrabbed(true) end
					return { item }
				end,
				filter = function(typeName, data)
					if typeName ~= DND_RES or data == nil then return false end
					local ok, mark = pcall(function() return data.vehicleIndex end)
					return ok and mark == DND_MARK
				end,
				drop = function(ctx)
					local ok, err = pcall(function()
						local first, last = dragged(ctx)
						if first then p.onMove(first, last, p.side == "Left" and p.first or (p.last + 1)) end
					end)
					if not ok then fail("moving a vehicle", err) end
					if p.setSide then p.setSide(nil) end
					return ok
				end,
				enter = function(ctx)
					-- the bar only where dropping moves something (not on the dragged tile itself
					-- or the halves next to it)
					local ok, show = pcall(function()
						if not ctx.anyMatch() then return false end
						local first, last = dragged(ctx)
						local before = p.side == "Left" and p.first or (p.last + 1)
						return first ~= nil and (before < first or before > last + 1)
					end)
					if ok and show and p.setSide then p.setSide(p.side) end
					return false
				end,
				exit = function()
					if p.setSide then p.setSide(nil) end
					return false
				end,
			})
		end
		-- the half a drop goes to is lit while a tile is dragged over it (with the bar on its edge)
		return builtin.BoxLayout{ meta = { class = "vh-cart-dnd-box" }, children = { builtin.Button{
			meta = { class = "vh-cart-dnd-button" .. (p.active and ", vh-cart-dnd-on" or "") }, content = builtin.BoxLayout{} } } }
	end)

	-- a tile: p.es, p.reversed, p.color, p.count, p.first, p.last, p.turnable, p.pictures,
	-- p.onReverse, p.onRemove (the whole tile), p.onRemoveOne (a stack), p.onMove(first, last, before)
	-- With a controller (p.pad): p.onMoveLeft / p.onMoveRight (nil at the ends), p.focusRef (the
	-- vehicle number whose tile takes the focus next: after a move the tile is somewhere else) and
	-- p.carryRef (a move happened while the button was held: the next tile is held too)
	local VhCartPart = react.RegisterRecipe("VhCartPart", guarded("train tile", function(p)
		local hover = react.useState(false)
		local side = react.useState(nil)
		local grabbed = react.useState(false)
		local hold = react.useState(false)
		if p.pad and canIA then
			-- the game's moves for its own train: hold IA_OPTION2, then left / right move the tile,
			-- IA_TABLEFT turns it around, IA_TABRIGHT takes it (one of a stack) off
			if type(react.iaHandlerExtended) == "function" then
				react.useInputAction("IA_OPTION2", react.iaHandlerExtended(function(data)
					local ok, err = pcall(function()
						local S = api.gui.inputAction.InvokeData.Status
						if data.status == S.Triggered then
							hold:set(true)
							padLog("hold on " .. tostring(p.es.name))
						elseif data.status == S.EndReleased or data.status == S.EndAborted then
							hold:set(false)
						end
					end)
					if not ok then fail("controller hold", err) end
				end))
			end
			if hold:old() then
				if p.onMoveLeft then react.useInputAction("IA_NAV_LEFT", react.iaHandler(p.onMoveLeft, nil, "Move left")) end
				if p.onMoveRight then react.useInputAction("IA_NAV_RIGHT", react.iaHandler(p.onMoveRight, nil, "Move right")) end
				if p.turnable then react.useInputAction("IA_TABLEFT", react.iaHandler(p.onReverse, nil, "Turn around")) end
				react.useInputAction("IA_TABRIGHT", react.iaHandler(p.count > 1 and p.onRemoveOne or p.onRemove, nil,
					p.count > 1 and "Take one off" or "Take it off"))
			end
		end
		-- after a move the tile that now has the vehicle takes the focus, still held (the button is
		-- still down: p.carryRef). (Set up in both modes: the game's hooks may count on the same
		-- calls in every render.)
		if type(react.useSelfRef) == "function" and type(react.onStep) == "function" then
			local selfRef = react.useSelfRef()
			react.onStep(function()
				if not (p.pad and p.focusRef) then return end
				local target = p.focusRef:get()
				if target ~= nil and target >= p.first and target <= p.last then
					local node = selfRef:get()
					if node then
						pcall(function() node:focus() end)
						p.focusRef:set(nil)
						if p.carryRef and p.carryRef:get() then
							p.carryRef:set(false)
							hold:set(true)
						end
					end
				end
			end)
		end
		if type(react.onMouseEvent) == "function" then
			react.onMouseEvent(function(evt)
				pcall(function()
					if evt.type == api.gui.mouse.Event.Type.Released then grabbed:set(false) end
				end)
				return false
			end)
		end
		local es = p.es
		local content = {}
		if p.pictures then
			-- the pictures face the way the vehicle will run, in its color
			for _, pic in ipairs(vehiclePictures(es, p.reversed, p.color, "vh-part-icon", 3)) do content[#content + 1] = pic end
		else
			content[#content + 1] = text(es.name, "vh-cart-name")
		end
		if p.count > 1 then content[#content + 1] = text(TIMES .. core.int(p.count), "vh-cart-count") end

		local float = {
			builtin.FloatingLayoutChild{ h = 0.5, v = 0.5,
				item = builtin.BoxLayout{ meta = { class = "vh-cart-pictures", mouseTransparent = true }, orientation = H, children = content } },
		}
		if not p.pad then
			-- the two halves that take a dropped tile (and start dragging this one); not with a
			-- controller (like the game's train): they are buttons, and the focus would stop on them
			float[#float + 1] = builtin.FloatingLayoutChild{ h = -1, v = -1,
				item = builtin.Component{ meta = { class = "vh-cart-dnd" }, layout = builtin.BoxLayout{ orientation = H, children = {
					VhCartDnd{ side = "Left", first = p.first, last = p.last, onMove = p.onMove, active = side:old() == "Left",
						setSide = function(v) side:set(v) end, setGrabbed = function(v) grabbed:set(v) end },
					VhCartDnd{ side = "Right", first = p.first, last = p.last, onMove = p.onMove, active = side:old() == "Right",
						setSide = function(v) side:set(v) end, setGrabbed = function(v) grabbed:set(v) end },
				} } } }
		end
		-- where a dragged tile would go: a bar on that side
		if side:old() == "Left" or side:old() == "Right" then
			float[#float + 1] = builtin.FloatingLayoutChild{ h = side:old() == "Left" and 0 or 1, v = 0.5,
				item = builtin.Component{ meta = { class = "vh-cart-guide", mouseTransparent = true } } }
		end
		-- (with a controller the focus lights the tile and the buttons stay away: the moves above)
		if hover:old() and not p.pad then
			-- a stack: the x for all of it on the left and - (one) on the right, where a single
			-- vehicle has its x, so a click there never takes the whole stack off (Ethan, 4 Oct)
			if p.turnable then
				float[#float + 1] = builtin.FloatingLayoutChild{ h = 0, v = 0,
					item = moveButton(iconContent(REVERSE_ICON), p.onReverse, p.reversed and "Turn back around" or "Turn around (reverse)") }
			elseif p.count > 1 then
				float[#float + 1] = builtin.FloatingLayoutChild{ h = 0, v = 0,
					item = moveButton(iconContent(CLOSE_ICON), p.onRemove, "Take all " .. core.int(p.count) .. " off the train") }
			end
			if p.count > 1 and not p.turnable then
				float[#float + 1] = builtin.FloatingLayoutChild{ h = 1, v = 0,
					item = moveButton(text("\226\136\146", "vh-move-text"), p.onRemoveOne, "Take one off") }
			else
				float[#float + 1] = builtin.FloatingLayoutChild{ h = 1, v = 0,
					item = moveButton(iconContent(CLOSE_ICON), p.onRemove, "Take it off the train") }
			end
			float[#float + 1] = builtin.FloatingLayoutChild{ h = 0.5, v = 1,
				item = builtin.ImageView{ meta = { class = "vh-cart-grip", mouseTransparent = true }, path = GRIP_ICON } }
		end
		local tip = es.name .. (p.count > 1 and (TIMES .. core.int(p.count)) or "") .. (p.reversed and " (turned around)" or "")
			.. (p.pad and "" or ". Hover for its buttons, drag to move it.")
		return builtin.BoxLayout{ meta = { class = "vh-cart-part-box" }, children = { builtin.Component{
			meta = {
				class = "vh-cart-part" .. (grabbed:old() and ", vh-cart-grabbed" or "") .. (hover:old() and ", vh-cart-hover" or "")
					.. (hold:old() and ", vh-cart-hold" or ""),
				tooltip = tip,
				onMouseOver = function(v) hover:set(v and true or false) end,
				-- a controller's focus counts as hover (the game calls both "attention")
				onAttention = p.pad and function(v) hover:set(v and true or false); if not v then hold:set(false) end end or nil,
				forceFocusable = p.pad and true or nil,
			},
			layout = builtin.FloatingLayout{ children = float },
		} } }
	end))

	local function stat(label, value, class, tooltip)
		return box(V, {
			text(label, "vh-stat-label, font-scale-annotation"),
			builtin.TextView{ meta = { class = "vh-stat-value, font-scale-body" .. (class and (", " .. class) or ""), tooltip = tooltip }, text = value },
		}, "vh-stat")
	end

	-- the totals of the train, as label/value pairs laid out in columns of two
	local function statGrid(items, perColumn, class)
		local columns, col = {}, nil
		for i, it in ipairs(items) do
			if (i - 1) % perColumn == 0 then col = {}; columns[#columns + 1] = col end
			col[#col + 1] = stat(it[1], it[2], it[3], it[4])
		end
		local nodes = {}
		for _, c in ipairs(columns) do nodes[#nodes + 1] = box(V, c, "vh-stat-col") end
		nodes[#nodes + 1] = spacer()
		return box(H, nodes, class or "vh-stats")
	end

	local loggedNoLoad = {}
	local function trainStats(entries, d, s)
		if d == nil then
			-- an empty train: the same grid with dashes, so the panel keeps its shape
			local items = {}
			for _, label in ipairs({ "Price", "Upkeep", "Capacity", "Price/cargo", "Upkeep/cargo", "Length", "Top speed", "Weight", "Cargo weight", "Acceleration", "Spare pull" }) do
				items[#items + 1] = { label, DASH, "vh-muted-value" }
			end
			return statGrid(items, 2)
		end
		local W = core.trainWeightOf(d, s)
		local perf = core.performance(W, d.power, d.tractiveEffort, d.speed, d.rollingFriction or 0, core.slopeValue(s))
		local cargo = core.perCargo(d)
		local items = {
			{ "Price", money(d.price or 0) },
			{ "Upkeep", money(d.runningCosts or 0) .. "/yr" },
			{ "Capacity", (d.totalCapacity or 0) > 0 and core.int(d.totalCapacity) or "\226\128\147" },
			{ "Price/cargo", cargo and money(cargo.price) or DASH },
			{ "Upkeep/cargo", cargo and (money(cargo.upkeep) .. "/yr") or DASH },
			{ "Length", trainLength(d.length or 0) },
			{ "Top speed", speed(d.speed or 0) },
			{ core.emptyTrains(s) and "Weight (empty)" or "Weight (loaded)", weight(W) },
		}
		-- what the cargo adds, so the Loaded weights setting shows what it does. Some vehicles (often
		-- from mods) have no cargo weight in their data: then the game itself runs them loaded at
		-- their empty weight, and loaded and empty come out the same
		if (d.totalCapacity or 0) > 0 then
			local payload = d.weightMaxPayload or 0
			local noLoad, seen = {}, {}
			for _, it in ipairs(entries) do
				local vd = it.es.vehicleData
				if (vd.totalCapacity or 0) > 0 and (vd.weightMaxPayload or 0) <= 0 and not seen[it.es.name] then
					seen[it.es.name] = true
					noLoad[#noLoad + 1] = it.es.name
				end
			end
			local names = table.concat(noLoad, ", ")
			if #noLoad > 0 and not loggedNoLoad[names] then
				loggedNoLoad[names] = true
				core.log("no cargo weight in the game's data (weightMaxPayload 0) for: " .. names)
			end
			if payload <= 0 then
				items[#items + 1] = { "Cargo weight", "none in data", "vh-warn",
					"The game's data for " .. names .. " has no cargo weight, so the train weighs the same loaded or empty (in the game too)" }
			elseif core.emptyTrains(s) then
				items[#items + 1] = { "Cargo weight (off)", "+" .. weight(payload), "vh-muted-value", "Not counted: Loaded weights is off in Settings" }
			else
				items[#items + 1] = { "Cargo weight", "+" .. weight(payload), nil,
					#noLoad > 0 and ("Counted, except " .. names .. ": no cargo weight in its data") or "Counted: Loaded weights is on in Settings" }
			end
		end
		if perf then
			items[#items + 1] = { "Acceleration", core.accel(math.max(perf.startAccel, 0)) }
			if perf.flatTime then
				items[#items + 1] = { "0\226\128\147" .. speed(perf.flatTop), core.seconds(perf.flatTime) }
			end
			local slope = string.lower(core.slopeName(s)) .. " slope"
			if perf.spare > -0.5 then -- less than half a tonne short shows as "+0 t", not "0 t over"
				items[#items + 1] = { "Spare pull (" .. slope .. ")", "+" .. core.int(math.max(perf.spare, 0)) .. " t", "vh-good" }
			else
				items[#items + 1] = { "Too heavy (" .. slope .. ")", core.int(-perf.spare) .. " t over", "vh-bad" }
			end
		else
			if (d.tractiveEffort or 0) > 0 then
				items[#items + 1] = { "Locomotive", DASH }
			else
				items[#items + 1] = { "Locomotive", "none yet", "vh-bad" }
			end
		end
		return statGrid(items, 2), perf
	end

	-------------------------------------------------------------------------------------------
	-- the details of one vehicle (click its row)
	-------------------------------------------------------------------------------------------
	-- comfort, noise and pollution as the store's words, with a color: good / poor among the
	-- vehicles of this carrier and year (the store's own ranges)
	local function goodness(store, d)
		local out = {}
		pcall(function()
			if type(vsu.getRangesFromData) ~= "function" or type(vsu.goodnessToTextString) ~= "function" then return end
			local r = vsu.getRangesFromData(d, store.carrier, currentYear())
			local function scale(v, range, invert)
				if v == nil or range == nil or range[1] == nil or range[2] == nil or range[2] == range[1] then return nil end
				local x = math.max(0, math.min(1, (v - range[1]) / (range[2] - range[1])))
				if invert then x = 1 - x end
				return { vsu.goodnessToTextString(x), x >= 0.6 and "vh-good" or (x < 0.4 and "vh-bad" or nil) }
			end
			if d.passengers and (d.comfortFactor or 0) > 0 then out.comfort = scale(d.comfortFactor, r.comfortScoreRange, false) end
			out.noise = scale(d.noise, r.noiseScoreRange, true)
			out.pollution = scale(d.pollution, r.pollutionScoreRange, true)
		end)
		return out
	end

	-- the model of a vehicle, or of a multiple unit's first car
	local function firstModelId(es)
		if not es.multipleUnit then return es.repId end
		local ok, id = pcall(function()
			for _, v in ipairs(api.res.multipleUnitRep.get(es.repId).vehicles) do return api.res.modelRep.find(v.name) end
		end)
		if ok then return id end
		return nil
	end

	local function lifespanYears(es)
		local id = firstModelId(es)
		if id == nil then return nil end
		local ok, years = pcall(function() return api.res.modelRep.get(id).metadata.maintenance.lifespan end)
		if ok and type(years) == "number" and years >= 1 and years <= 150 then return years end
		return nil
	end

	local function descriptionOf(es)
		local ok, t = pcall(function()
			if es.multipleUnit then return api.res.multipleUnitRep.get(es.repId).desc end
			return api.res.modelRep.get(es.repId).metadata.description.description
		end)
		if ok and type(t) == "string" and t ~= "" then return t end
		return nil
	end

	local function largePicture(es)
		local ok, r = pcall(vsu.getVehicleNameAndIcons, es.repId, es.multipleUnit, false)
		if ok and type(r) == "table" and type(r.largeIcon) == "string" and r.largeIcon ~= "" then return r.largeIcon end
		return nil
	end

	-- "Large" / "Small" for ships and planes, like the store
	local function sizeClass(es)
		local ok, r = pcall(function()
			local tm = api.type["enum"].TransportMode
			local modes = es.transportModes or {}
			if (tm.AIRCRAFT and modes[tm.AIRCRAFT]) or (tm.SHIP and modes[tm.SHIP]) then return "Large" end
			if (tm.SMALL_AIRCRAFT and modes[tm.SMALL_AIRCRAFT]) or (tm.SMALL_SHIP and modes[tm.SMALL_SHIP]) then return "Small" end
			return nil
		end)
		if ok then return r end
		return nil
	end

	-- what a vehicle carries, as the game's cargo icons (name and amount in each one's tooltip).
	-- An amount follows each icon only when they differ (otherwise it's the Capacity above).
	-- Vehicles for any cargo show the game's mixed-cargo icon and "All cargo" (passengers first
	-- when they take those too). Every icon is shown (the game's tooltips are text only), in
	-- rows of CARRIES_PER_ROW; each row is a line of text tall, and the section gets an empty
	-- label for each extra row, so the value column keeps lining up with its labels.
	local CARRIES_PER_ROW = 8
	local function mixedCargoIcon()
		local ok, path = pcall(function() return cargo_util.getMixedCargoIcon() end)
		if ok and type(path) == "string" then return path end
		return "::/cargos/icons/cargo_mixed.tga"
	end
	local function carriesNode(d)
		local items = {}
		for id, amount in pairs(d.allCargoTypes or {}) do
			if amount and amount > 0 then
				local info = cargoInfo(id)
				items[#items + 1] = { id = id, name = tostring(info.name), icon = info.icon, amount = amount }
			end
		end
		if #items == 0 then return nil end
		table.sort(items, function(a, b)
			local pa, pb = a.id == passengerId, b.id == passengerId
			if pa ~= pb then return pa end
			return a.name < b.name
		end)
		if forAnyCargo(d) then
			-- passengers (when it takes them) and one entry for all the cargo
			local cargoAmount = 0
			for _, it in ipairs(items) do if it.id ~= passengerId then cargoAmount = math.max(cargoAmount, it.amount) end end
			local pax = items[1].id == passengerId and items[1] or nil
			items = {}
			if pax then items[1] = pax end
			items[#items + 1] = { id = "all", name = "All cargo", icon = mixedCargoIcon(), amount = cargoAmount, label = "All cargo" }
		end
		local same = true
		for _, it in ipairs(items) do if it.amount ~= (d.totalCapacity or 0) then same = false end end
		local rows, kids = {}, {}
		local function endRow()
			-- a space as wide as nothing much: keeps the row a line of text tall with icons only
			kids[#kids + 1] = text(" ", "vh-kv-value")
			rows[#rows + 1] = box(H, kids, "vh-carries")
			kids = {}
		end
		for i, it in ipairs(items) do
			if i > 1 and (i - 1) % CARRIES_PER_ROW == 0 then endRow() end
			if it.icon then
				kids[#kids + 1] = builtin.ImageView{
					meta = { class = "vh-carries-icon", tooltip = it.name .. " " .. core.int(it.amount) },
					path = it.icon,
					scaling = builtin.type.ImageViewScaling and builtin.type.ImageViewScaling.AutoFit or nil,
				}
			end
			local words = {}
			if it.label or not it.icon then words[#words + 1] = it.label or it.name end
			if not same then words[#words + 1] = core.int(it.amount) end
			if #words > 0 then kids[#kids + 1] = text(table.concat(words, " "), "vh-kv-value") end
		end
		endRow()
		if #rows == 1 then return rows[1], 1 end
		return box(V, rows, "vh-carries-rows"), #rows
	end

	-- when it is sold, colored: green while sold, amber in its last 5 years, red when not (yet)
	-- returns the years, their color and, when there is one, a short note (also colored)
	local function availability(d)
		local year = currentYear()
		local from, to = d.yearFrom or 0, d.yearTo or 0
		local hasEnd = to > 0 and to < 5000
		local fromText = from > 0 and tostring(from) or "the start"
		local value = hasEnd and (fromText .. DASH .. tostring(to)) or ("from " .. fromText)
		if from > 0 and year < from then return value, "vh-bad", "not yet" end
		if hasEnd and year >= to then return value, "vh-bad", "no longer sold" end
		if hasEnd and to - year <= 5 then
			local left = to - year
			return value, "vh-warn", "in " .. core.int(left) .. (left == 1 and " year" or " years")
		end
		return value, "vh-good", nil
	end

	-- the details as sections in columns: { { title, rows = { {label, value, class, icon} } } }
	-- the sections in reading order: { title, rows = { {label, value, class, icon} }, tooltip }
	local function detailSections(store, es, s, single)
		local d = es.vehicleData
		local m = metricsFor(d)
		local function rows() return {} end
		local function add(list, label, value, class, icon)
			if value ~= nil and value ~= "" then list[#list + 1] = { label, value, class, icon } end
		end

		local costs = rows()
		add(costs, "Price", money(d.price or 0), nil, nil)
		add(costs, "Upkeep", money(d.runningCosts or 0) .. "/yr")
		if m.pricePerCargo then
			add(costs, "Price/cargo", money(m.pricePerCargo))
			add(costs, "Upkeep/cargo", money(m.upkeepPerCargo) .. "/yr")
		end
		local life = lifespanYears(es)
		if life then add(costs, "Lifespan", core.int(life) .. " years") end

		local load = rows()
		if (d.totalCapacity or 0) > 0 then
			add(load, "Capacity", core.int(d.totalCapacity), nil, "symbol_cargo.tga")
			local carries, lines = carriesNode(d)
			add(load, "Carries", carries)
			if carries and lines > 1 then load[#load].lines = lines end
			if (d.numCompartments or 0) > 1 then add(load, "Compartments", core.int(d.numCompartments)) end
		end
		if m.loadingSpeed then add(load, "Loading speed", string.format("%.1f\195\151", m.loadingSpeed), nil, "relation_cargo_time.tga") end

		local g = goodness(store, d)
		local quality = rows()
		if g.comfort then add(quality, "Comfort", g.comfort[1], g.comfort[2], "symbol_person_comfort.tga") end
		if g.noise then add(quality, "Noise", g.noise[1], g.noise[2], "symbol_noise.tga") end
		if g.pollution then add(quality, "Pollution", g.pollution[1], g.pollution[2], "symbol_pollution.tga") end

		local perf = rows()
		add(perf, "Top speed", speed(d.speed or 0), nil, "symbol_speed.tga")
		if (d.power or 0) > 0 then add(perf, "Power", power(d.power), nil, "symbol_chain_drive.tga") end
		if (d.tractiveEffort or 0) > 0 then add(perf, "Tractive effort", force(d.tractiveEffort), nil, "symbol_arrow_circle_dot.tga") end
		if (d.thrust or 0) > 0 then add(perf, "Thrust", force(d.thrust), nil, "thrust.tga") end
		-- on its own, loaded and empty (whatever Loaded weights is set to); one of each when its
		-- cargo weighs nothing in the data (or it carries nothing)
		local sLoaded, sEmpty = core.copySettings(s), core.copySettings(s)
		sLoaded.trainWeight, sEmpty.trainWeight = 1, 2
		local loaded, empty = core.selfPerformance(d, sLoaded), core.selfPerformance(d, sEmpty)
		if loaded and empty and (d.weightMaxPayload or 0) > 0 then
			add(perf, "Accel. loaded", core.accel(loaded.accel))
			add(perf, "Accel. empty", core.accel(empty.accel))
			if loaded.time then add(perf, "0" .. DASH .. speed(loaded.top) .. " loaded", core.seconds(loaded.time)) end
			if empty.time then add(perf, "0" .. DASH .. speed(empty.top) .. " empty", core.seconds(empty.time)) end
		elseif loaded then
			add(perf, "Acceleration", core.accel(loaded.accel))
			if loaded.time then add(perf, "0" .. DASH .. speed(loaded.top), core.seconds(loaded.time)) end
		elseif (d.power or 0) > 0 and (d.weight or 0) > 0 then
			-- a ship: its pushing force comes from its propeller, worked out inside the game, so no
			-- m/s². Power per tonne compares ships; loaded, the same push moves more weight.
			local we, wl = d.weight, d.weight + (d.weightMaxPayload or 0)
			if wl > we then
				add(perf, "Power/t empty", powerPerTonne(d.power / we))
				add(perf, "Power/t loaded", powerPerTonne(d.power / wl))
				add(perf, "Accel. loaded", "about " .. core.int(100 * we / wl) .. "% of empty")
			else
				add(perf, "Power/t", powerPerTonne(d.power / we))
			end
		end

		-- pulling is for trains only (a bus or a truck pulls nothing)
		local pulling = rows()
		if m.pull and not single then
			for _, sl in ipairs(core.SLOPES) do
				add(pulling, sl.name .. " slope", core.int(core.pullOn(d, sl.value) or 0) .. " t")
			end
		end

		local size = rows()
		add(size, "Weight", weight(d.weight or 0), nil, "symbol_weight.tga")
		if (d.weightMaxPayload or 0) > 0 then
			add(size, "Loaded weight", weight((d.weight or 0) + d.weightMaxPayload))
		elseif (d.totalCapacity or 0) > 0 and (d.thrust or 0) <= 0 then
			-- (often a mod's vehicle) loaded weighs the same as empty, also in the game. Planes and
			-- helicopters (thrust) never have a cargo weight in the game's data: nothing to say there
			add(size, "Cargo weight", "none in data", "vh-warn")
		end
		if (d.length or 0) > 0 then add(size, "Length", trainLength(d.length), nil, "relation_train_length.tga") end
		if es.multipleUnit then add(size, "Cars", core.int(#(es.icons or {}))) end
		add(size, "Class", sizeClass(es))

		local avail = rows()
		local when, whenClass, note = availability(d)
		add(avail, "Available", when, whenClass)
		if note then add(avail, whenClass == "vh-warn" and "Sales end" or "Status", note, whenClass) end
		if es.hasEngine then add(avail, "Engine", engineSummary(es)) end
		if d.isReversible then add(avail, "Reversible", "both ways") end
		if d.isLightrail then add(avail, "Light rail", "tram + rail track") end

		local out = {}
		local function sec(title, list, tooltip) if #list > 0 then out[#out + 1] = { title = title, rows = list, tooltip = tooltip } end end
		sec("Costs", costs)
		sec("Load", load)
		sec("Quality", quality)
		sec("Performance", perf)
		sec("Pulling", pulling, "Heaviest load behind it (not counting itself) it can start and pull at half its top speed, on each slope. The Pull column and Fill use the slope set in Settings (now: "
			.. string.lower(core.slopeName(s)) .. ")")
		sec("Size", size)
		sec("Availability", avail)
		return out
	end

	-- the sections cut into `n` columns, in reading order, with the tallest column as low as it can
	-- be (a fixed number of columns: the game's FlowLayout doesn't grow taller when it wraps, so
	-- wrapped columns were drawn over what comes below)
	local function packColumns(sections, n)
		local count = #sections
		if count <= n then
			local cols = {}
			for i, sec in ipairs(sections) do cols[i] = { sec } end
			return cols
		end
		local h = {}
		for i, sec in ipairs(sections) do
			h[i] = 1.5 -- a title is about a row and a half
			for _, r in ipairs(sec.rows) do h[i] = h[i] + (r.lines or 1) end
		end
		local best
		local cuts = {}
		local function try(start, colsLeft, tallest)
			if colsLeft == 1 then
				local hh = 0
				for i = start, count do hh = hh + h[i] end
				tallest = math.max(tallest, hh)
				if best == nil or tallest < best.tallest then
					best = { tallest = tallest, cuts = {} }
					for i, c in ipairs(cuts) do best.cuts[i] = c end
				end
				return
			end
			local hh = 0
			for stop = start, count - colsLeft + 1 do
				hh = hh + h[stop]
				cuts[#cuts + 1] = stop
				try(stop + 1, colsLeft - 1, math.max(tallest, hh))
				cuts[#cuts] = nil
			end
		end
		try(1, n, 0)
		local cols, from = {}, 1
		local stops = best.cuts
		stops[#stops + 1] = count
		for _, stop in ipairs(stops) do
			local col = {}
			for i = from, stop do col[#col + 1] = sections[i] end
			cols[#cols + 1] = col
			from = stop + 1
		end
		return cols
	end

	-- a section: its title, then a column of labels next to a column of values, so every value
	-- starts at the same place (rows of label / spacer / value don't line up in the game's boxes)
	local function sectionNode(sec)
		local hasIcon = false
		for _, r in ipairs(sec.rows) do if r[4] then hasIcon = true end end
		local labels, values = {}, {}
		for _, r in ipairs(sec.rows) do
			local label = text(r[1], "vh-kv-label")
			if hasIcon then
				label = box(H, { r[4] and image(ICON .. r[4], "vh-kv-icon") or builtin.Component{ meta = { class = "vh-kv-icon-space" } }, label }, "vh-kv-label-box")
			end
			labels[#labels + 1] = label
			-- a value is text, or a node of its own (the cargo icons, maybe several lines: an
			-- empty label for each extra line keeps the next labels next to their values)
			values[#values + 1] = type(r[2]) == "string" and text(r[2], "vh-kv-value" .. (r[3] and (", " .. r[3]) or "")) or r[2]
			for _ = 2, (r.lines or 1) do
				labels[#labels + 1] = hasIcon and box(H, { builtin.Component{ meta = { class = "vh-kv-icon-space" } }, text(" ", "vh-kv-label") }, "vh-kv-label-box")
					or text(" ", "vh-kv-label")
			end
		end
		return box(V, {
			builtin.TextView{ meta = { class = "vh-section-title, font-scale-annotation", tooltip = sec.tooltip }, text = sec.title },
			box(H, { box(V, labels, "vh-kv-labels"), box(V, values, "vh-kv-values") }, "vh-kv"),
		}, "vh-section")
	end

	local function sectionsNode(columns)
		local nodes = {}
		for _, col in ipairs(columns) do
			local kids = {}
			for _, sec in ipairs(col) do kids[#kids + 1] = sectionNode(sec) end
			nodes[#nodes + 1] = box(V, kids, "vh-section-col")
		end
		return box(H, nodes, "vh-sections")
	end

	-- the liveries / versions to pick from (the one shown is lit), with what differs between them
	local function optionsNode(options, currentKey, onPick)
		if #options < 2 then return nil end
		local first = options[1].es
		local differs = false
		for _, o in ipairs(options) do
			local a, b = o.es.vehicleData, first.vehicleData
			if (a.totalCapacity or 0) ~= (b.totalCapacity or 0) or (a.price or 0) ~= (b.price or 0) or #(o.es.icons or {}) ~= #(first.icons or {}) then differs = true end
		end
		local chips = {}
		for _, o in ipairs(options) do
			local es = o.es
			local d = es.vehicleData
			local inner = vehiclePictures(es, false, ui.colors[kindKey(es.multipleUnit, es.repId)], "vh-option-icon", 2)
			local label = es.name
			if differs then
				local extra = {}
				if es.multipleUnit then extra[#extra + 1] = core.int(#(es.icons or {})) .. " cars" end
				if (d.totalCapacity or 0) > 0 then extra[#extra + 1] = core.int(d.totalCapacity) .. " cap." end
				extra[#extra + 1] = money(d.price or 0)
				label = label .. DOT .. table.concat(extra, DOT)
			end
			inner[#inner + 1] = text(label, "vh-option-text")
			local years, _, yearsNote = availability(d)
			if yearsNote then years = years .. " (" .. yearsNote .. ")" end
			chips[#chips + 1] = builtin.Button{
				meta = { tooltip = es.name .. DOT .. years, class = "vh-button, vh-option" .. (o.key == currentKey and ", vh-option-on" or "") },
				content = box(H, inner, "vh-option-box"),
				onClick = function() onPick(o.key) end,
			}
		end
		-- one to a row in a scroll window of up to 3½ rows (two to a row ran past the card's edge
		-- with long names, and a wrapping FlowLayout was drawn over the sections)
		local P = builtin.type.ScrollBarPolicy
		local height = #chips >= 4 and "many" or tostring(#chips)
		return box(H, {
			text("Variations", "vh-filter-label"),
			builtin.ScrollArea{
				meta = { class = "vh-options-scroll, vh-options-scroll-" .. height },
				content = builtin.Component{ layout = box(V, chips, "vh-option-rows") },
				horizontalPolicy = P and P.AsNeeded or nil,
				verticalPolicy = P and P.AsNeeded or nil,
				disableGamepadNavigation = true,
			},
		}, "vh-options-row")
	end

	-- the game's paint bucket button with the store's colors; the color is kept for this model and
	-- used for what you add or buy from now on (like the store)
	local function colorNode(store, es, onColor)
		local palette = store.colorChooserColorsStaticData
		if type(builtin.ColorChooserButton) ~= "function" or type(palette) ~= "table" then return nil end
		local k = kindKey(es.multipleUnit, es.repId)
		local noMask = es.vehicleData and es.vehicleData.noCblendMask == true
		return builtin.ColorChooserButton{
			meta = {
				tooltip = noMask and "This vehicle has no paintable parts" or "Change color (for what you add or buy next)",
				class = "vh-color",
				enabled = not noMask,
			},
			colors = palette,
			color = ui.colors[k],
			image = ICON .. "symbol_paintbucket.tga",
			onValueChange = function(c)
				ui.colors[k] = usableColor(c)
				if onColor then onColor() end
			end,
			resetButton = false,
			innerResetButton = true,
			toolTipPosition = builtin.type.ToolTipPosition and builtin.type.ToolTipPosition.Above or nil,
		}
	end

	-- ctx: options, currentKey, onPick(key), onAdd, onClose, onColor, pictures
	local function detailsCard(store, es, s, single, ctx)
		local index = pathIndex(store.vehiclesStaticData and store.vehiclesStaticData.repId2elementStatic or {})
		local model, livery = namesOf(es, index, variantIndex(store))
		local color = ui.colors[kindKey(es.multipleUnit, es.repId)]
		local tags = {}
		if livery then tags[#tags + 1] = livery end
		if es.multipleUnit then tags[#tags + 1] = "Multiple unit" .. DOT .. core.int(#(es.icons or {})) .. " cars" end
		local cls = sizeClass(es)
		if cls then tags[#tags + 1] = cls end
		if es.hasEngine then tags[#tags + 1] = engineSummary(es) end
		if es.vehicleData.isLightrail then tags[#tags + 1] = "Light rail" end
		if es.vehicleData.isReversible then tags[#tags + 1] = "Reversible" end

		local titleBox = {
			text(model or es.name, "vh-detail-title, font-scale-title-4"),
			#tags > 0 and text(table.concat(tags, DOT), "vh-sub, font-scale-annotation") or nil,
		}
		-- (with a controller this button takes the focus when the details open: ctx.focusRef)
		local mainText = single and ("Buy " .. money(es.vehicleData.price or 0)) or "+ Add to train"
		local mainTip = single and ("Buy one now" .. (usableColor(color) and ", in the color picked" or ""))
			or ("Add it to the train" .. (usableColor(color) and ", in the color picked" or ""))
		if single and rv.mode(store) == "Replace" then
			-- (Replace: what it costs after the old vehicles' value, like the game's Replace)
			local cost, n, resale = rv.singleCost(store, es.vehicleData.price or 0)
			mainText = "Replace for " .. money(cost)
			mainTip = (n == 1 and "Replace the vehicle with this one" or ("Replace the " .. core.int(n) .. " vehicles with this one"))
				.. (usableColor(color) and ", in the color picked" or "") .. ": " .. (n == 1 and "" or (core.int(n) .. TIMES .. " ")) .. money(es.vehicleData.price or 0)
				.. ", less " .. money(resale) .. " for the old " .. (n == 1 and "one" or "ones")
		end
		local mainParams = {
			meta = { class = "vh-button, vh-primary", tooltip = mainTip },
			content = builtin.TextView{ text = mainText },
			onClick = ctx.onAdd,
		}
		local mainButton = (ctx.focusRef and type(react.ref) == "function") and builtin.Button(react.ref(ctx.focusRef), mainParams)
			or builtin.Button(mainParams)
		local header = box(H, {
			box(V, titleBox, "vh-name-box"),
			spacer(),
			colorNode(store, es, ctx.onColor),
			mainButton,
			button("Close", "Close the details", ctx.onClose, "vh-button"),
		}, "vh-detail-header")

		-- right of the picture: the header, the cars (a multiple unit, or in the color picked;
		-- long trains scroll sideways) and the liveries / versions to pick from
		local top = { header }
		-- (pictures are only made when they are shown: a picture made and not used makes the game
		-- log a warning on every frame)
		local cars = #(es.icons or {})
		if ctx.pictures and (cars > 1 or (cars == 1 and usableColor(color))) then
			top[#top + 1] = clip(vehiclePictures(es, false, color, "vh-detail-icon", 60), "vh-strip", H, true)
		end
		local opts = optionsNode(ctx.options or {}, ctx.currentKey, ctx.onPick)
		if opts then top[#top + 1] = opts end
		local large = ctx.pictures and largePicture(es) or nil
		local main = {
			box(H, {
				large and box(V, { image(large, "vh-large-picture") }, "vh-large-box") or nil,
				box(V, top, "vh-detail-top"),
			}, "vh-detail-toprow"),
			-- the numbers use the whole width, below the picture too
			sectionsNode(packColumns(detailSections(store, es, s, single), 4)),
		}
		local desc = descriptionOf(es)
		if desc then
			main[#main + 1] = builtin.ScrollArea{
				meta = { class = "vh-desc-scroll" },
				content = text(desc, "vh-desc, font-scale-annotation"),
				horizontalPolicy = builtin.type.ScrollBarPolicy and builtin.type.ScrollBarPolicy.AlwaysOff or nil,
				verticalPolicy = builtin.type.ScrollBarPolicy and builtin.type.ScrollBarPolicy.AsNeeded or nil,
				disableGamepadNavigation = true,
			}
		end
		return card(V, main, "vh-details")
	end

	-- the details as a recipe of their own, so a controller's B (IA_MENU_BACK) can mean "back to
	-- the list" while the focus is in them (A on a row puts the focus here, Ethan 5 Oct). p.store,
	-- p.es, p.s, p.single, p.ctx: detailsCard's arguments; p.onBack: back to the list
	local VhDetails = react.RegisterRecipe("VhDetails", function(p)
		if p.pad and canIA and p.onBack then
			react.useInputAction("IA_MENU_BACK", react.iaHandler(p.onBack, nil, "Back to the list"))
		end
		local ok, node = pcall(detailsCard, p.store, p.es, p.s, p.single, p.ctx)
		if not ok then fail("vehicle details", node); return nil end
		return box(V, { node }, "vh-details-wrap")
	end)

	-------------------------------------------------------------------------------------------
	-- the buyer
	-------------------------------------------------------------------------------------------
	local VhBuyer = react.RegisterRecipe("VhBuyer", function(props)
		local store = props.store
		local tabs = tabsFor(store.carrier)
		local single = not vsu.acceptsMultiVehicle(store.carrier)
		local carrierKey = tostring(store.carrier)

		local st = {
			tab = react.useState(ui.tab[carrierKey] or 1),
			search = react.useState(""),
			-- (Modify starts with the vehicle's own cars)
			train = react.useState((rv.mode(store) == "Modify" and rv.planFor(store)) or {}),
			message = react.useState({ text = "", class = "" }),
			settings = react.useState(core.settingsVersion),
			cargo = react.useState(depotFilters(store).cargo),
			engines = react.useState(depotFilters(store).engines),
			affordable = react.useState(depotFilters(store).affordable),
			selected = react.useState(nil),
			variant = react.useState(nil),   -- a livery / version picked in the details
			colors = react.useState(0),      -- bumped when a color is picked
			showSettings = react.useState(ui.showSettings),
			sort = react.useState(0),        -- bumped when a header sorts the table (a new table)
		}
		-- the row whose details are open, for the cells (they read it every frame)
		st.openRef = react.useRef(nil)
		-- money is checked once a second; the state only changes when "enough" flips, so the
		-- table isn't rebuilt every second
		st.priceRef = react.useRef(0)
		if engine_react_util and type(engine_react_util.useStepStateTimer) == "function" then
			st.enough = engine_react_util.useStepStateTimer(function()
				local b = balance()
				return b == nil or b >= (st.priceRef:get() or 0)
			end, 1.0)
		end

		-- controller (see padMode): the mode (checked every frame, like the game's store), the
		-- table's node (it takes the focus when the store opens, and after a sort or Close: the
		-- focused thing is gone then), the vehicle whose tile takes the focus after a move
		if engine_react_util and type(engine_react_util.useStepState) == "function" then
			st.pad = engine_react_util.useStepState(padMode)
		end
		if st.pad then st.isPad = st.pad:old() == true else st.isPad = padMode() end
		st.tableRef = type(react.useNodeRef) == "function" and react.useNodeRef() or nil
		st.focusTable = react.useRef(0)     -- frames left in which the table is given the focus
		-- switching to the controller draws a new table (its cells light the focus): it takes the focus
		st.lastPad = react.useRef(nil)
		if st.lastPad:get() ~= st.isPad then
			if st.isPad and st.lastPad:get() ~= nil then
				st.focusTable:set(3)
				padLog("switched to the controller")
			end
			st.lastPad:set(st.isPad)
		end
		st.focusTile = react.useRef(nil)
		st.carryHold = react.useRef(false)
		st.focusRow = react.useRef(nil)     -- the row whose name or + Add has the focus (lit as one box)
		st.detailsRef = type(react.useNodeRef) == "function" and react.useNodeRef() or nil
		st.focusDetails = react.useRef(0)   -- frames left in which the details' main button is given the focus
		st.buyNow = react.useRef(nil)       -- the train's Buy (set by the render), for IA_OPTION1
		if canIA then
			-- the d-pad moves the focus to the next control up, down, left or right
			react.useInputAction("IA_NAV_UP", react.iaFocusTraversal(false, false))
			react.useInputAction("IA_NAV_DOWN", react.iaFocusTraversal(false, true))
			react.useInputAction("IA_NAV_LEFT", react.iaFocusTraversal(true, false))
			react.useInputAction("IA_NAV_RIGHT", react.iaFocusTraversal(true, true))
			-- IA_OPTION1 buys the train, like in the game's store; with nothing to buy it does
			-- nothing (otherwise it would reach the game and pick the bulldozer)
			react.useInputAction("IA_OPTION1", react.iaHandler(function()
				local f = st.buyNow:get()
				if f then padLog("buy"); f() end
			end, function() return st.buyNow:get() ~= nil end, rv.mode(store))) -- (the prompt: Buy, Replace or Modify)
		end
		if st.tableRef and type(react.setPreferredFocusChild) == "function" then react.setPreferredFocusChild(st.tableRef) end
		if type(react.onMount) == "function" then
			react.onMount(function()
				st.focusTable:set(3)
				-- every opening with a controller, and the first one either way (shows the mode)
				if st.isPad or padLogs == 0 then
					padLog("store opened (" .. (st.isPad and "controller" or "mouse and keyboard") .. ")")
				end
			end)
		end
		if type(react.onStep) == "function" then
			react.onStep(function()
				local n = st.focusTable:get() or 0
				if n > 0 and st.tableRef then
					st.focusTable:set(n - 1)
					local nodeRef = st.tableRef:get()
					if nodeRef then pcall(function() nodeRef:focus() end) end
				end
				local d = st.focusDetails:get() or 0
				if d > 0 and st.detailsRef then
					st.focusDetails:set(d - 1)
					local nodeRef = st.detailsRef:get()
					if nodeRef then pcall(function() nodeRef:focus() end) end
				end
			end)
		end

		local okRender, node = pcall(M._render, store, tabs, single, carrierKey, st)
		if okRender then return node end
		-- something in the buyer failed: say so and offer the game's store instead of breaking the UI
		fail("the buyer window", node)
		return box(V, {
			text("The Enhanced Vehicle Store hit an error (details in stdout.txt).", "vh-message"),
			button("Classic store", "Show the game's own store in this window (its Enhanced Store button comes back here)", function() M.showClassic(store) end, "vh-button, vh-primary"),
		}, "vh-buyer")
	end)

	function M._render(store, tabs, single, carrierKey, st)
		local s = core.settings()
		local tabIndex = st.tab:old()
		if tabs[tabIndex] == nil then tabIndex = 1 end
		local tabId = tabs[tabIndex].id
		local filter = makeFilter(store, tabs, tabIndex)
		local opts = { search = st.search:old(), cargo = st.cargo:old(), engines = st.engines:old(), affordable = st.affordable:old(),
			applyCargo = tabId ~= "locomotive", applyEngines = tabId ~= "waggon" }
		local elements, presentCargo, presentEngines, total = availableElements(store, filter, opts, s)
		local byKey, rowKeys = {}, {}
		for i, e in ipairs(elements) do
			e.rank = i -- ties in a sort go by this order (year, then name)
			byKey[e.key] = e
			rowKeys[i] = e.key
		end
		-- which filters apply on this tab: cargo where vehicles carry something, engines where
		-- vehicles have engines (locomotives don't carry cargo, wagons have no engine)
		local showCargo = tabId ~= "locomotive"
		local showEngines = tabId ~= "waggon"
		local entries = st.train:old()

		local okData, d = pcall(trainData, entries)
		if not okData then fail("train numbers", d); d = nil end

		local function say(t, class) st.message:set({ text = t, class = class or "" }) end
		local function setTrain(list)
			st.train:set(list)
			say("")
		end
		local function colorOf(es) return ui.colors[kindKey(es.multipleUnit, es.repId)] end
		local function add(es)
			local list = {}
			for i, e in ipairs(st.train:old()) do list[i] = e end
			list[#list + 1] = trainItem(es, false, colorOf(es))
			setTrain(list)
		end
		-- turn vehicles first..last around (one chip of the train)
		local function reverseRange(first, last)
			local list = {}
			for i, e in ipairs(st.train:old()) do
				if i >= first and i <= last then list[i] = trainItem(e.es, not e.reversed, e.color, e.own) else list[i] = e end
			end
			setTrain(list)
		end
		local function removeAt(index)
			local list = {}
			for i, e in ipairs(st.train:old()) do if i ~= index then list[#list + 1] = e end end
			setTrain(list)
		end
		-- move vehicles first..last so they come before vehicle `before` (#train + 1: to the end)
		local function moveRange(first, last, before)
			local list = st.train:old()
			if first < 1 or last > #list or first > last or (before >= first and before <= last + 1) then return end
			local out = {}
			for i = 1, #list + 1 do
				if i == before then for j = first, last do out[#out + 1] = list[j] end end
				if i <= #list and (i < first or i > last) then out[#out + 1] = list[i] end
			end
			setTrain(out)
		end
		M._moveRange = moveRange -- for tests
		local function removeRange(first, last)
			local list = {}
			for i, e in ipairs(st.train:old()) do if i < first or i > last then list[#list + 1] = e end end
			setTrain(list)
		end
		local function buyEntries(list, isSingle)
			say("Buying...")
			local ok, started, err = pcall(buy, store, list, isSingle, function(success, reason)
				pcall(function()
					local m = rv.mode(store)
					if success and m ~= "Buy" then
						say(m == "Replace" and "Replaced." or "Modified the train.", "vh-good")
					elseif success then
						say("Bought " .. (isSingle and list[1].es.name or "the train") .. ".", "vh-good")
					else
						say("Could not buy: " .. tostring(reason or "not enough money"), "vh-bad")
					end
				end)
			end)
			if not ok then
				fail("buy", started)
				say("Could not buy (see the log)", "vh-bad")
			elseif not started then
				say("Could not buy: " .. tostring(err), "vh-bad")
			end
		end
		local function changeSetting(key, value)
			local n = core.copySettings(core.settings())
			n[key] = value
			core.saveSettings(n)
			st.settings:set(core.settingsVersion)
		end

		-- the table's columns and sort (before the top bar: with a controller the sort is there)
		local kind = nil
		for _, name in ipairs({ "AIR", "WATER", "ROAD", "RAIL", "TRAM" }) do
			if store.carrier ~= nil and store.carrier == carrierEnum(name) then kind = name end
		end
		local cols = visibleColumns(tabId, single, elements, kind)
		local colKeys = {}
		for _, c in ipairs(cols) do colKeys[#colKeys + 1] = c.key end
		local sortIndex, sortAscending = 2, true
		for i, c in ipairs(cols) do
			if c.key == ui.sortKey then sortIndex, sortAscending = i, ui.sortAscending end
		end
		-- a new sort: remembered, and drawn as a new table (see below). keepFocus: the sort came
		-- from the controller's Sort buttons, which keep the focus; otherwise (a header, LB / RB on
		-- a row) the new table takes it
		local function applySort(c, ascending, keepFocus)
			if c == nil then return end
			local current = cols[sortIndex]
			if current ~= nil and c.key == current.key and ascending == sortAscending then return end
			ui.sortKey, ui.sortAscending = c.key, ascending
			if sortLogs < 3 then
				sortLogs = sortLogs + 1
				local first = sortedKeys(rowKeys, byKey, c, ascending)[1]
				local e = first ~= nil and byKey[first] or nil
				core.log("sort: " .. tostring(c.name) .. (ascending and " up" or " down") .. ", first row "
					.. tostring(e and (e.dynamic.model or e.static.name) or "-"))
			end
			st.sort:set((st.sort:old() or 0) + 1)
			if st.isPad and not keepFocus then st.focusTable:set(3) end
		end
		-- controller: the column before / after the sorted one (names A to Z, numbers highest first)
		local function sortStep(d, keepFocus)
			local sortable = {}
			-- (not the + Add column: it has no name, and LB / RB landed on it, Ethan 5 Oct)
			for i, c in ipairs(cols) do if c.compare and c.key ~= "add" then sortable[#sortable + 1] = i end end
			if #sortable == 0 then return end
			local pos = 1
			for k, i in ipairs(sortable) do if i == sortIndex then pos = k end end
			local c = cols[sortable[(pos - 1 + d) % #sortable + 1]]
			applySort(c, c.key == "name", keepFocus)
		end

		-- top bar: tabs, search, count, settings, classic store
		local top = {}
		if #tabs > 1 then
			local tabButtons = {}
			for i, t in ipairs(tabs) do
				tabButtons[#tabButtons + 1] = button(t.label, nil, function()
					ui.tab[carrierKey] = i
					st.tab:set(i)
				end, i == tabIndex and "vh-button, vh-tab, vh-tab-active" or "vh-button, vh-tab")
			end
			top[#top + 1] = box(H, tabButtons, "vh-tabs")
		end
		-- (not with a controller, like the game's store: typing needs a keyboard, and the field
		-- would hold on to the focus)
		if type(builtin.TextInputField) == "function" and not st.isPad then
			top[#top + 1] = builtin.TextInputField{
				meta = { class = "vh-search, font-scale-body" },
				placeholderText = "Search models and variations",
				value = st.search:old(),
				onValueChange = function(t) st.search:set(t or "") end,
				onTyping = function(t) st.search:set(t or "") end,
				acceptOnFocusLoss = false,
			}
		end
		top[#top + 1] = spacer()
		top[#top + 1] = text((#elements < total and (core.int(#elements) .. " of ") or "") .. core.int(total) .. (total == 1 and " vehicle" or " vehicles"), "vh-count")
		-- controller: the headers can't be clicked, so the sort has two buttons here (A: the next
		-- column; A: the other way round). LB / RB on a row do the same as the first (Ethan, 5 Oct)
		if st.isPad and cols[sortIndex] then
			local c = cols[sortIndex]
			top[#top + 1] = button("Sort: " .. tostring(c.name), nil, function() sortStep(1, true) end, "vh-button, vh-small, vh-sort-button")
			local way = c.key == "name" and (sortAscending and "A to Z" or "Z to A") or (sortAscending and "Lowest first" or "Highest first")
			top[#top + 1] = button(way, nil, function() applySort(c, not sortAscending, true) end, "vh-button, vh-small, vh-sort-button")
		end
		top[#top + 1] = toggle(builtin.TextView{ text = "Settings" }, st.showSettings:old(), function(on)
			ui.showSettings = on
			st.showSettings:set(on)
		end, single and "Loaded weights, variations and pictures"
			or "Slope, loaded weights, variations and pictures (in place of the filters while a train is being built and a vehicle's details are open)", "vh-chip, vh-settings-toggle")
		top[#top + 1] = button("Classic store", "Show the game's own store in this window (its Enhanced Store button comes back here)", function() M.showClassic(store) end)

		local children = { box(H, top, "vh-topbar") }

		-- crowded: a train in the builder and a vehicle's details open take most of the window's
		-- height (1080p), and the table got no rows. Then Settings shows in the filters' place, and
		-- many cargo types go in one line instead of two (the train ran off the bottom of the
		-- window with Settings open, and on Wagons the two cargo rows left no table, Ethan 5 Oct).
		-- Otherwise the filters and the settings both show, at every depot
		local allData = store.vehiclesStaticData and store.vehiclesStaticData.repId2elementStatic or {}
		local crowded = not single and #entries > 0 and st.selected:old() ~= nil and allData[st.selected:old()] ~= nil
		local settingsOn = st.showSettings:old()

		-- the filters (filter controls are only made when shown: a control made and not used makes
		-- the game log a warning on every frame)
		if not (settingsOn and crowded) then
			-- filters: engines, affordable, clear on the first row; the cargo filter after them, or on a
			-- row of its own when it has many types. The cargo filter looks like the game's: passengers
			-- in a box, "All cargo" (the mixed-cargo icon) in a box, the cargo types in a box (two rows
			-- when there are many). A vehicle shows when it carries any type picked; All cargo picks
			-- the vehicles for any cargo, and like in the game, picking a type turns All cargo off and
			-- All cargo turns the types off.
			local cargoIds, showPax, showAll = {}, false, false
			if showCargo then
				local picked = st.cargo:old()
				for id, _ in pairs(presentCargo) do
					if id ~= ALL_CARGO and id ~= passengerId then cargoIds[#cargoIds + 1] = id end
				end
				for id, _ in pairs(picked) do
					if id ~= ALL_CARGO and id ~= passengerId and not presentCargo[id] then cargoIds[#cargoIds + 1] = id end
				end
				table.sort(cargoIds, function(a, b) return tostring(cargoInfo(a).name) < tostring(cargoInfo(b).name) end)
				showPax = passengerId ~= nil and (presentCargo[passengerId] or picked[passengerId]) and true or false
				showAll = (presentCargo[ALL_CARGO] or picked[ALL_CARGO]) and true or false
				local count = #cargoIds + (showPax and 1 or 0) + (showAll and 1 or 0)
				if count < 2 and next(picked) == nil then cargoIds, showPax, showAll = {}, false, false end
			end
			local function setCargo(id, on)
				local n = {}
				for k, v in pairs(st.cargo:old()) do n[k] = v end
				if on and id == ALL_CARGO then
					-- All cargo turns the types off (passengers stay)
					for k, _ in pairs(n) do if k ~= passengerId then n[k] = nil end end
				elseif on and id ~= passengerId then
					n[ALL_CARGO] = nil
				end
				n[id] = on and true or nil
				depotFilters(store).cargo = n
				st.cargo:set(n)
			end
			local function cargoChip(id, icon, name, tooltip)
				local content = icon and image(icon, "vh-cargo-icon") or builtin.TextView{ text = name }
				return toggle(content, st.cargo:old()[id] == true, function(on) setCargo(id, on) end,
					tooltip or ("Only vehicles that carry " .. string.lower(tostring(name))), "vh-chip, vh-cargo-chip, forever-fair")
			end
			local function cargoGroup(children, class)
				return builtin.Component{ meta = { class = "vh-cargo-group" .. (class and (", " .. class) or "") }, layout = box(V, children, "vh-cargo-group-box") }
			end
			local cargoChips = {}
			for _, id in ipairs(cargoIds) do
				local info = cargoInfo(id)
				cargoChips[#cargoChips + 1] = cargoChip(id, info.icon, info.name)
			end
			-- many types: two rows, or one line that scrolls sideways when crowded
			local cargoOneLine = #cargoChips > 8 and crowded
			local cargoTwoRows = #cargoChips > 8 and not crowded
			local cargoBar = nil
			if #cargoChips > 0 or showPax or showAll then
				local groups = {}
				if showPax then
					local info = cargoInfo(passengerId)
					groups[#groups + 1] = cargoGroup({ cargoChip(passengerId, info.icon, info.name) }, "vh-cargo-single")
				end
				if showAll then
					groups[#groups + 1] = cargoGroup({ cargoChip(ALL_CARGO, mixedCargoIcon(), "All cargo", "Only vehicles for any cargo") }, "vh-cargo-single")
				end
				if #cargoChips > 0 then
					-- two rows like the game's when there are many: the first gets the extra one
					local rows = {}
					local perRow = cargoTwoRows and math.ceil(#cargoChips / 2) or #cargoChips
					for i = 1, #cargoChips, perRow do
						local row = {}
						for j = i, math.min(i + perRow - 1, #cargoChips) do row[#row + 1] = cargoChips[j] end
						rows[#rows + 1] = box(H, row, "vh-cargo-row")
					end
					groups[#groups + 1] = cargoGroup(rows, "vh-cargo-types")
				end
				cargoBar = box(H, groups, "vh-cargo-bar")
			end

			local row1 = {}
			if showEngines then
				-- which engine types get a chip; the chips are only made when they are shown (a control
				-- made and not used makes the game log a warning on every frame)
				local engineList = {}
				for _, e in ipairs(engineEnum()) do
					if presentEngines[e.value] or st.engines:old()[e.value] then engineList[#engineList + 1] = e end
				end
				if #engineList > 1 or next(st.engines:old()) ~= nil then
					row1[#row1 + 1] = text("Engine", "vh-filter-label")
					for _, e in ipairs(engineList) do
						row1[#row1 + 1] = toggle(builtin.TextView{ text = e.name }, st.engines:old()[e.value] == true, function(on)
							local n = {}
							for k, v in pairs(st.engines:old()) do n[k] = v end
							n[e.value] = on and true or nil
							depotFilters(store).engines = n
							st.engines:set(n)
						end, "Only vehicles with " .. string.lower(e.name) .. " engines")
					end
				end
			end
			row1[#row1 + 1] = toggle(builtin.TextView{ text = "Affordable" }, st.affordable:old(), function(on)
				depotFilters(store).affordable = on
				st.affordable:set(on)
			end, "Only vehicles you can pay for now")
			local anyFilter = next(st.cargo:old()) ~= nil or next(st.engines:old()) ~= nil or st.affordable:old() or st.search:old() ~= ""
			row1[#row1 + 1] = button("Clear filters", nil, function()
				local f = depotFilters(store)
				f.cargo, f.engines, f.affordable = {}, {}, false
				st.cargo:set({}); st.engines:set({}); st.affordable:set(false); st.search:set("")
			end, "vh-button, vh-small", anyFilter)

			-- the rows are packed to the left (not stretched): a stretched box hands its spare width to
			-- its children, which spread the chips across the window. Many cargo types: the cargo
			-- filter gets a row of its own (a wrapping FlowLayout doesn't grow taller, so its second
			-- line was drawn over the table).
			local filterRows
			if cargoBar == nil then
				filterRows = { box(H, row1, "vh-filter-row") }
			elseif cargoOneLine then
				-- crowded: one row, the other filters then the cargo types in one line that takes the
				-- rest of the width and scrolls sideways when they don't fit (its scroll bar's room is
				-- kept, so the icons don't move when it shows)
				local P = builtin.type.ScrollBarPolicy
				filterRows = { box(H, {
					box(H, row1, "vh-filter-row, vh-filter-side"),
					builtin.ScrollArea{
						meta = { class = "vh-cargo-scroll" },
						content = builtin.Component{ layout = cargoBar },
						horizontalPolicy = P and (P.AsNeededButAlwaysReserveSpace or P.AsNeeded) or nil,
						verticalPolicy = P and P.AlwaysOff or nil,
						disableGamepadNavigation = true,
					},
				}, "vh-filter-row, vh-filter-wide") }
			elseif cargoTwoRows then
				filterRows = {
					box(H, row1, "vh-filter-row"),
					box(H, { text("Cargo", "vh-filter-label"), cargoBar }, "vh-filter-row"),
				}
			else
				row1[#row1 + 1] = text("Cargo", "vh-filter-label")
				row1[#row1 + 1] = cargoBar
				filterRows = { box(H, row1, "vh-filter-row") }
			end
			children[#children + 1] = card(V, filterRows, "vh-filters")
		end
		-- the settings, under the filters (or in their place when crowded)
		if settingsOn then
			local slope = core.SLOPES[s.slope]
			children[#children + 1] = card(H, {
				text("Settings", "vh-filter-label"),
				-- the slope is for pulling (rail and tram only)
				not single and button(string.format("Slope: %s (%.2f%%)", slope.name, slope.value * 100), "Slope for the Pull column, Fill and the train's spare pull. Click to change.",
					function() changeSetting("slope", s.slope % #core.SLOPES + 1) end, "vh-button, vh-small") or nil,
				button("Loaded weights: " .. (core.emptyTrains(s) and "off" or "on"),
					"On: the numbers count the weight of a full load of cargo (weight, acceleration, time to top speed, spare pull, Fill). Off: empty vehicles. Click to change.",
					function() changeSetting("trainWeight", s.trainWeight % #core.TRAIN_WEIGHTS + 1) end, "vh-button, vh-small"),
				button(s.groupLiveries and "Variations: one row per model" or "Variations: every variation",
					"Variations are a model's liveries and versions (a multiple unit with other cars, from mods too). One row per model: pick a variation in the details. Every variation: each has its own row. Click to change.",
					function() changeSetting("groupLiveries", not s.groupLiveries) end, "vh-button, vh-small"),
				button(s.pictures and "Pictures: on" or "Pictures: off", "Vehicle pictures in the table and the train. Click to change.",
					function() changeSetting("pictures", not s.pictures) end, "vh-button, vh-small"),
			}, "vh-settings-row")
		end

		-- the table
		-- the rows go to the table in the order it shows them (by its sort column). The table
		-- starts at its first row key and keeps that row in view when it sorts: with the keys in
		-- the game's order (by year) a filter change scrolled the list down to wherever that
		-- vehicle was, and turning a sort around jumped to the bottom (Ethan, 4 Oct). 1.2.5
		-- scrolled to the first row with the table's scrollToRowKey a frame later, and that landed
		-- in the middle (5 Oct). Now nothing is scrolled: a new sort makes a new table (the sort is
		-- in its key, like the filters), and a new table starts at its first row, the top
		rowKeys = sortedKeys(rowKeys, byKey, cols[sortIndex], sortAscending)
		-- a new table whenever what it lists changes, so no row keeps old contents
		local filterKey = {}
		for id, _ in pairs(st.cargo:old()) do filterKey[#filterKey + 1] = "c" .. tostring(id) end
		for t, _ in pairs(st.engines:old()) do filterKey[#filterKey + 1] = "e" .. tostring(t) end
		table.sort(filterKey)
		local tableKey = table.concat({ "vh", tabId, tostring(st.isPad), tostring(s.slope), tostring(s.trainWeight), tostring(s.groupLiveries),
			tostring(s.pictures), tostring(st.affordable:old()), table.concat(filterKey, "."), table.concat(colKeys, "."), st.search:old(),
			tostring(cols[sortIndex] and cols[sortIndex].key), tostring(sortAscending) }, "|")
		local replaceInfo = nil
		if rv.mode(store) == "Replace" then
			local list = rv.entities(store)
			replaceInfo = { count = #list, resale = rv.resale(list) }
		end
		local tableParams = {
			meta = {
				localKey = tableKey,
				class = "vh-table",
			},
			columns = columnNodes(cols, byKey),
			rowKeys = rowKeys,
			userParam = {
				pad = st.isPad,
				byKey = byKey,
				elements = elements,
				single = single,
				-- Replace: how many old vehicles and what they are worth (the Replace buttons' tooltips)
				replace = replaceInfo,
				pictures = s.pictures,
				groupLiveries = s.groupLiveries,
				add = add,
				buyNow = function(es) buyEntries({ trainItem(es, false, colorOf(es)) }, true) end,
				openRef = st.openRef,
				focusRowRef = st.focusRow,
				sortStep = sortStep,
				select = function(key)
					st.variant:set(nil)
					if st.selected:old() == key then st.selected:set(nil)
					else
						st.selected:set(key)
						-- controller: the focus goes to the details (their + Add to train / Buy);
						-- B goes back to the list (VhDetails)
						if st.isPad then st.focusTable:set(0); st.focusDetails:set(3) end
					end
				end,
			},
			initialSortColumn = { sortIndex, sortAscending },
			-- a header click: remember the sort and draw a new table with it (see above)
			onSortColumnChange = function(column, ascending)
				applySort(cols[column], ascending)
			end,
			scrollPolicyVertical = builtin.type.ScrollBarPolicy and builtin.type.ScrollBarPolicy.AsNeededButAlwaysReserveSpace or nil,
		}
		-- the table's node: it takes the focus when the store opens (controller)
		children[#children + 1] = st.tableRef and type(react.ref) == "function" and builtin.DataTable(react.ref(st.tableRef), tableParams)
			or builtin.DataTable(tableParams)

		-- the details of the vehicle clicked in the table
		-- (a livery / version picked there is shown instead of the row's own vehicle)
		local selectedKey = st.selected:old()
		if selectedKey ~= nil and allData[selectedKey] == nil then selectedKey = nil end
		st.openRef:set(selectedKey)
		local shownKey = selectedKey
		if s.groupLiveries and selectedKey ~= nil and st.variant:old() ~= nil and allData[st.variant:old()] ~= nil then shownKey = st.variant:old() end
		local shownEs = shownKey ~= nil and allData[shownKey] or nil
		if shownEs then
			-- the variations picker only when they share a row (Variations: one row per model)
			local okO, options = true, {}
			if s.groupLiveries then okO, options = pcall(optionsOf, store, shownEs, filter) end
			if not okO then fail("variations", options); options = {} end
			children[#children + 1] = VhDetails{ pad = st.isPad, onBack = function()
				padLog("back to the list")
				st.focusDetails:set(0)
				st.focusTable:set(3)
			end, store = store, es = shownEs, s = s, single = single, ctx = {
				focusRef = st.detailsRef,
				options = options,
				currentKey = shownKey,
				pictures = s.pictures,
				onPick = function(key) st.variant:set(key) end,
				onAdd = function()
					if single then buyEntries({ trainItem(shownEs, false, colorOf(shownEs)) }, true) else add(shownEs) end
				end,
				onClose = function()
					st.selected:set(nil); st.variant:set(nil)
					-- the Close button had the focus and is gone: back to the table
					if st.isPad then st.focusDetails:set(0); st.focusTable:set(3) end
				end,
				onColor = function() st.colors:set((st.colors:old() or 0) + 1) end,
			} }
		end

		if not single then
			-- the train: parts, totals, actions
			local parts = {}
			local groups = groupEntries(entries)
			for gi, g in ipairs(groups) do
				local first, last = g.first, g.last
				local prev, nxt = groups[gi - 1], groups[gi + 1]
				parts[#parts + 1] = VhCartPart{
					es = g.es, reversed = g.it.reversed, color = g.it.color, count = g.count, first = first, last = last,
					turnable = canTurn(g.es), pictures = s.pictures,
					onReverse = function() reverseRange(first, last) end,
					onRemove = function()
						-- with a controller the tile that slides into its place takes the focus
						local left = #entries - (last - first + 1)
						if st.isPad and left > 0 then st.focusTile:set(math.min(first, left)) end
						removeRange(first, last)
					end,
					onRemoveOne = function() removeAt(last) end,
					onMove = moveRange,
					-- controller: the tile moves past its neighbour tile, and keeps the focus
					pad = st.isPad, focusRef = st.focusTile, carryRef = st.carryHold,
					onMoveLeft = prev and function()
						st.focusTile:set(prev.first); st.carryHold:set(true)
						moveRange(first, last, prev.first)
					end or nil,
					onMoveRight = nxt and function()
						st.focusTile:set(first + (nxt.last - nxt.first + 1)); st.carryHold:set(true)
						moveRange(first, last, nxt.last + 1)
					end or nil,
				}
			end
			-- Replace: the new train for the old vehicles; Modify: the vehicle's own train
			local mode = rv.mode(store)
			local trainName, emptyText = "Your train", "Empty. Click + Add on a locomotive and some wagons. Click a row for all its details, variations and colors."
			if mode == "Replace" then
				local n = #rv.entities(store)
				trainName = "New train for " .. (n == 1 and "1 vehicle" or (core.int(n) .. " vehicles"))
				emptyText = "Empty. Build the train " .. (n == 1 and "the vehicle becomes" or ("the " .. core.int(n) .. " vehicles become")) .. ": click + Add on a locomotive and some wagons."
			elseif mode == "Modify" then
				local list = rv.entities(store)
				trainName = "Modifying " .. ((list[1] and rv.name(list[1])) or "the train")
				emptyText = "Empty: every car is off. Click + Add to put some on (closing the window keeps the train as it was)."
			end
			local title = #entries > 0 and (trainName .. DOT .. core.int(#entries) .. (#entries == 1 and " vehicle" or " vehicles")) or trainName
			local partsNode
			if #parts == 0 then
				partsNode = box(H, { text(emptyText, "vh-muted") }, "vh-parts-empty")
			else
				-- one row that scrolls sideways (a wrapping FlowLayout hid what went on its 2nd line)
				local P = builtin.type.ScrollBarPolicy
				partsNode = builtin.ScrollArea{
					meta = { class = "vh-parts-scroll" },
					content = builtin.Component{ layout = box(H, parts, "vh-parts-row") },
					horizontalPolicy = P and P.AsNeeded or nil,
					verticalPolicy = P and P.AlwaysOff or nil,
					disableGamepadNavigation = true, -- like the game's train: the d-pad moves between tiles
				}
			end

			local statsNode = trainStats(entries, d, s)

			local lastWagon, lastWagonAt = nil, nil
			for i = #entries, 1, -1 do
				-- the last plain wagon (not a cab car: Fill shouldn't add more of those)
				local wd = entries[i].es.vehicleData
				if (wd.tractiveEffort or 0) <= 0 and (wd.power or 0) <= 0 and not wd.isReversible then lastWagon, lastWagonAt = entries[i], i; break end
			end
			local fill = fillCount(d, lastWagon, s)

			-- (Replace / Modify: what it costs after the old vehicles' value, see rv.trainButton)
			local okB, price, buyLabel, buyTip = pcall(rv.trainButton, store, entries, d)
			if not okB then fail("the Buy button", price); price, buyLabel, buyTip = d and d.price or 0, "Buy", nil end
			st.priceRef:set(price)
			local funds = balance()
			local enough = funds == nil or funds >= price
			local message = st.message:old()
			if not enough and #entries > 0 then message = { text = "Not enough money", class = "vh-bad" } end
			-- the controller's buy button (IA_OPTION1) buys what the Buy button would
			st.buyNow:set((#entries > 0 and enough) and function() buyEntries(entries, false) end or nil)

			local actions = {
				button(buyLabel, buyTip,
					function() buyEntries(entries, false) end, "vh-button, vh-primary, vh-buy", #entries > 0 and enough),
				box(H, {
					button(fill > 0 and ("Fill +" .. core.int(fill)) or "Fill", fill > 0
						and ("Add " .. core.int(fill) .. TIMES .. " " .. lastWagon.es.name .. ", up to the pull limit (" .. string.lower(core.slopeName(s)) .. " slope)")
						or "Adds the last wagon type until the locomotives reach their pull limit",
						function()
							-- the new wagons go right after that wagon (so a cab car or a locomotive at
							-- the back stays at the back)
							local list = {}
							for i, e in ipairs(st.train:old()) do
								list[#list + 1] = e
								if i == lastWagonAt then
									for _ = 1, fill do list[#list + 1] = trainItem(lastWagon.es, lastWagon.reversed, lastWagon.color) end
								end
							end
							setTrain(list)
						end, "vh-button, vh-small", fill > 0),
					button("Clear", "Empty the train", function() setTrain({}) end, "vh-button, vh-small", #entries > 0),
				}, "vh-action-row"),
				message.text ~= "" and text(message.text, "vh-message" .. (message.class ~= "" and (", " .. message.class) or "")) or nil,
				vspacer(),
			}

			children[#children + 1] = card(H, {
				box(V, {
					text(title, "vh-title"),
					partsNode,
					-- with a controller there is no hovering or dragging: how the tiles work instead
					(st.isPad and #parts > 0) and text("Controller: on a car, hold the game's move button and press left or right to move it, LB to turn it around, RB to take one off.", "vh-muted, vh-pad-hint") or nil,
					statsNode,
					vspacer(),
				}, "vh-train-main"),
				box(V, actions, "vh-actions"),
			}, "vh-train")
		elseif st.message:old().text ~= "" then
			local m = st.message:old()
			children[#children + 1] = text(m.text, "vh-message" .. (m.class ~= "" and (", " .. m.class) or ""))
		end

		return box(V, children, "vh-buyer")
	end

	-------------------------------------------------------------------------------------------
	-- plugging in
	-------------------------------------------------------------------------------------------
	local VehicleStoreWindow = vsw.VehicleStoreWindow

	-- buyer or the game's store, chosen once per store window (its params table) on its first draw.
	-- Buy and Replace open the buyer, and Modify of one train (1.2: the vehicle manager's Replace
	-- and Modify opened the game's store, Ethan 5 Oct); Modify of several vehicles stays the game's
	local choice, choices = {}, 0
	local function choiceFor(p)
		local c = choice[p]
		if c == nil then
			if choices > 64 then choice, choices, rv.plans = {}, 0, {} end
			c = (not p.__vhClassic and core.settings().buyer and rv.supported(p)) and "buyer" or "game"
			choice[p] = c
			choices = choices + 1
			if c == "buyer" then
				core.log("buyer opened (" .. tostring(p.vehicleStoreMode) .. ", carrier " .. tostring(p.carrier)
					.. (p.vehicleEntities and (", " .. tostring(#p.vehicleEntities) .. " vehicles") or "") .. ")")
			end
		end
		return c
	end

	-- shows the store window again with new params: the same two calls the store's entry point
	-- makes when it opens a store window (the window stays the game's VehicleStoreWindow)
	local function reopen(store, classic, where)
		local copy = {}
		for k, v in pairs(store) do
			if k ~= "__vhClassic" then copy[k] = v end
		end
		if classic then copy.__vhClassic = true end
		local ok, err = pcall(function()
			local wc = store.gameCtx.windowContainer:get():getApi()
			wc.removeAllWindows(VehicleStoreWindow)
			-- (the names the game gives its store windows: Modify has its own)
			wc.addWindow(VehicleStoreWindow, store.vehicleStoreMode == "Modify" and "modifyVehicle" or "replaceVehicle", copy)
		end)
		if not ok then fail(where, err) end
	end
	-- "Classic store": the game's own store in this window (until it is closed)
	function M.showClassic(store) reopen(store, true, "classic store") end
	-- the "Enhanced Store" button in the game's store: back to the buyer
	function M.showBuyer(store) reopen(store, false, "back to the buyer") end

	-- Every store window stays the game's own VehicleStoreWindow (the replacement only remembers
	-- its params). Its builtin.Window call is where a buyer window gets the buyer as content.
	-- (1.0.0 drew the window itself for the buyer; the game then couldn't switch that window to
	-- its own store, so Classic store closed the window instead.)
	local lastParams = nil
	local function passThrough(...)
		local a1, a2 = ...
		local p = a1
		if not (type(p) == "table" and p.vehicleStoreMode ~= nil) and type(a2) == "table" then p = a2 end
		if type(p) == "table" then
			lastParams = p
			choiceFor(p)
		end
		return react.CallOriginalRecipe(VehicleStoreWindow, ...)
	end
	replacementApi.ReplaceRecipe(VehicleStoreWindow, passThrough)

	-- A Classic store window (the game's store) gets one thing from the mod: a slim bar above
	-- its content with the "Enhanced Store" button that switches it back to the buyer. (1.0 to
	-- 1.2 put the button into the store's top bar by replacing builtin.ToggleButton and
	-- builtin.BoxLayout for the whole game; see below why that is gone.)
	local function classicWithButton(store, content)
		return box(V, {
			box(H, {
				builtin.Component{ meta = { class = "vh-classic-spacer" } },
				builtin.Button{
					meta = { class = "vh-back", tooltip = "Back to the Enhanced Vehicle Store" },
					content = builtin.TextView{ text = "Enhanced Store" },
					onClick = function() M.showBuyer(store) end,
				},
			}, "vh-classic-bar"),
			content,
		}, "vh-classic-wrap")
	end

	local function swapContent(a1, a2, a3)
		local p = a3
		if p == nil then p = a2 end
		if p == nil then p = a1 end
		if type(p) ~= "table" or p.id ~= STORE_WINDOW_ID then return end
		local store = lastParams
		if store == nil then return end
		if p.title ~= nil and store.title ~= nil and p.title ~= store.title then return end
		local c = choice[store]
		if c == "buyer" then
			p.content = VhBuyer{ store = store }
		elseif c == "game" and p.content ~= nil and core.settings().buyer and rv.supported(store) then
			p.content = classicWithButton(store, p.content)
		end
	end

	-- 1.3: builtin.Window is no longer replaced for the whole game. The game knows its interface
	-- parts by their functions: a window recipe registered with
	-- react.RegisterWrapperRecipe(name, builtin.Window, fn) looks up builtin.Window's recipe id
	-- when it is registered. 1.0 to 1.2 replaced builtin.Window, builtin.ToggleButton and
	-- builtin.BoxLayout with plain functions, so every window registered after the mod loaded
	-- (Minimap, top-bar button mods, menus that load later) wrapped "nothing" and the game
	-- crashed when it opened (NodeStorage.cpp "id >= 0" assertion; mod.io reports 5 and 6 Oct,
	-- cause found by APasz).
	-- Now builtin.Window is swapped for exactly one call: the store window's own body
	-- (vehicle_store_window.tl, VehicleStoreWindow) calls vehicle_store_util.acceptsMultiVehicle
	-- right before its builtin.Window{ id = "vehiclestore.window" }. When that happens while the
	-- recipe being drawn is VehicleStoreWindow (react.getCurrentRecipeName), a one-shot
	-- function is put in builtin.Window; its first call puts the game's function back before
	-- anything else, then changes the store window's content. (A recipe's body runs when the
	-- game draws it, after passThrough has returned, so passThrough can't do the swap itself.)
	local origWindow = builtin.Window
	local origAccepts = vsu.acceptsMultiVehicle
	local armedPrev = nil -- the builtin.Window that was there when the one-shot was put in
	local armedWindow
	armedWindow = function(...)
		local prev = armedPrev or origWindow
		armedPrev = nil
		if builtin.Window == armedWindow then builtin.Window = prev end
		local ok, err = pcall(swapContent, ...)
		if not ok then fail("opening the buyer (showing the game's store)", err) end
		return prev(...)
	end
	local function inStoreWindowBody()
		local ok, name = pcall(react.getCurrentRecipeName)
		return ok and name == "VehicleStoreWindow"
	end
	M._origWindow, M._armedWindow = origWindow, armedWindow -- for tests
	if type(react.getCurrentRecipeName) == "function" then
		vsu.acceptsMultiVehicle = function(...)
			if armedPrev == nil and builtin.Window ~= armedWindow and inStoreWindowBody() then
				armedPrev = builtin.Window
				builtin.Window = armedWindow
			end
			return origAccepts(...)
		end
	else
		core.log("buyer: react.getCurrentRecipeName missing in this game version, the store stays the game's")
	end

	core._buyerInstalled = true
	return "ok"
end

return M

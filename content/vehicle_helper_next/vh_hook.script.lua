-- Enhanced Vehicle Store v1.3: start-up hook.
--
-- Runs once when the UI starts (react-replacement-config, see vh_replacements.res.lua) and installs
-- the buyer (vh_buyer.lua): the store window opened by a depot's Buy button shows the Vehicle
-- Helper buyer instead of the game's content. Replace and Modify keep the game's store.
--
-- The game's own store is left as it is, apart from one button in its top bar ("Enhanced Store")
-- that switches a Buy store back to the buyer after "Classic store" (see vh_buyer.lua).
--
-- The game gives mods a reduced Lua: no rawget/rawset, and debug has no getupvalue/setupvalue.
-- So: no closure tricks, no raw access, and every wrapper passes its arguments on unchanged
-- with `...` (React counts them).

local CORE_PATH = "kacsa_enhanced_vehicle_store::/vehicle_helper_next/vh_core.lua"
local BUYER_PATH = "kacsa_enhanced_vehicle_store::/vehicle_helper_next/vh_buyer.lua"

---------------------------------------------------------------------------------------------------
-- per-vehicle numbers, cached per VehicleData table and settings version (bounded, no weak tables)
---------------------------------------------------------------------------------------------------
local function makeMetrics(core)
	local cache, count = {}, 0
	return function(d)
		if type(d) ~= "table" then return {} end
		local c = cache[d]
		if c == nil or c.version ~= core.settingsVersion then
			if count > 4000 then cache, count = {}, 0 end
			c = { version = core.settingsVersion, m = core.vehicleMetrics(d, core.settings()) }
			cache[d] = c
			count = count + 1
		end
		return c.m
	end
end

---------------------------------------------------------------------------------------------------
-- entry point (react-replacement-config doReplaceFn)
---------------------------------------------------------------------------------------------------
local function doReplace(replacementApi)
	local okCore, core = pcall(require, CORE_PATH)
	if not okCore then
		if debugPrint then debugPrint("[EnhancedStore] could not load vh_core.lua, nothing changed: " .. tostring(core)) end
		return
	end
	core.log("v" .. core.VERSION .. " starting")
	local s = core.settings()
	core.log(string.format("settings: slope=%s trainWeight=%s groupLiveries=%s pictures=%s",
		core.slopeName(s), core.TRAIN_WEIGHTS[s.trainWeight], tostring(s.groupLiveries), tostring(s.pictures)))

	local okR, react = pcall(function() return ug_require "::/gui/main/react.lua" end)
	local okB, builtin = pcall(function() return ug_require "::/gui/main/builtin.lua" end)
	if not (okR and okB) then
		core.log("react or builtin could not be loaded (" .. tostring(okR and "" or react) .. " " .. tostring(okB and "" or builtin) .. "); the game's store stays as it is")
		return
	end

	local ok, res = pcall(function()
		local buyer = require(BUYER_PATH)
		return buyer.install(core, react, builtin, replacementApi, makeMetrics(core))
	end)
	core.log("buyer: " .. (ok and tostring(res) or ("failed, the game's store stays as it is: " .. tostring(res))))
end

-- Lua resource files must define a global data() function (Teal files use 'return' instead).
function data()
	return {
		doReplace = doReplace,
	}
end

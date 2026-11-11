function data()
	return {
		-- runs vh_hook.script.lua once when the game's UI starts, before any window is drawn.
		-- (order: when it runs among the start-up hooks of all mods)
		type = "react-replacement-config",
		data = {
			filePath = "kacsa_enhanced_vehicle_store::/vehicle_helper_next/vh_hook.script",
			doReplaceFn = "doReplace",
			order = 115,
		}
	}
end

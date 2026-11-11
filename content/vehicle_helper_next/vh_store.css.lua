-- Enhanced Vehicle Store v1.3: styles.
--
-- Nearly all rules are for the buyer (R::VhBuyer). A Classic store window (the game's store) gets
-- a slim bar above its content with the "Enhanced Store" button; the rules for that bar come first.

local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }
	local a = ssu.makeAdder(result)

	local okColors, colors = pcall(function()
		return api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	end)
	if not okColors or type(colors) ~= "table" then colors = {} end
	local okTr, transparency = pcall(function()
		return api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
	end)
	if not okTr or type(transparency) ~= "table" then transparency = {} end
	-- a game color with another opacity (color_util.withTransparencyRaw)
	local function withAlpha(c, alpha)
		if type(c) ~= "table" then return c end
		return { c[1], c[2], c[3], alpha }
	end

	-- the game's store (Classic store): its content under a slim bar with the "Enhanced Store"
	-- button on the right. The wrap and the game's content fill the window as the content did
	-- on its own.
	a("BoxLayout!vh-classic-wrap", {
		gravity = { -1, -1 },
		innerSpacing = { 0, 4 },
	})
	a("BoxLayout!vh-classic-wrap R::VehicleStoreWindowContent > BoxLayout", {
		gravity = { -1, -1 },
	})
	a("BoxLayout!vh-classic-bar", {
		gravity = { -1, 0 },
	})
	a("Component!vh-classic-spacer", {
		gravity = { -1, 0 },
	})
	a("Button!vh-back", {
		padding = { 4, 12, 4, 12 },
		backgroundColor1 = colors.AccentMedium,
		gravity = { 0, 0.5 },
	})
	a("Button!vh-back:hover", {
		backgroundColor1 = colors.AccentLight,
	})

	-- the buyer (VhBuyer, inside the store window). Cards use the game's own card images, the
	-- same ones the store's panels use (vehicle_store.css.lua).
	local cardImages = {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/card_surface.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 },
		},
		borderImage = {
			fileName = "::/gui/entity_window/design/card_contour.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 },
		},
	}
	local function withCard(t)
		for k, v in pairs(cardImages) do t[k] = v end
		return t
	end

	a("R::VhBuyer", {
		gravity = { -1, -1 },
	})
	a("R::VhBuyer BoxLayout!vh-buyer", {
		gravity = { -1, -1 },
		innerSpacing = { 0, 6 },
		margin = { 0, 6, 0, 6 },
	})
	a("R::VhBuyer R::Component!vh-card", withCard({
		backgroundColor1 = colors.BaseLight,
		borderColor = colors.BaseVeryLight,
		padding = { 6, 8, 6, 8 },
		gravity = { -1, 0 },
	}))
	-- the box inside a card. Its spacing is set per card below with the same selector plus the
	-- box's class: a plain "BoxLayout!vh-filters-box" rule is less specific than this one, so it
	-- never applied (the filter rows and the details' parts had no gap between them)
	a("R::VhBuyer R::Component!vh-card > BoxLayout", {
		gravity = { -1, 0 },
		innerSpacing = { 6, 0 },
	})
	a("R::VhBuyer R::Component!vh-card > BoxLayout!vh-filters-box", {
		innerSpacing = { 0, 10 },
	})
	a("R::VhBuyer R::Component!vh-card > BoxLayout!vh-details-box", {
		innerSpacing = { 0, 12 },
	})
	a("R::VhBuyer R::Component!vh-card > BoxLayout!vh-train-box", {
		innerSpacing = { 16, 0 },
	})
	a("R::VhBuyer R::Component!vh-card > BoxLayout!vh-settings-row-box", {
		innerSpacing = { 8, 0 },
	})
	-- spacers like the game's (gravity only): a fixed size pins them, and then a stretched box
	-- hands its spare room to all the other children instead (things spread out)
	a("R::VhBuyer R::Component!vh-spacer", {
		gravity = { -1, 0 },
	})
	a("R::VhBuyer R::Component!vh-vspacer", {
		gravity = { 0, -1 },
	})

	-- top bar
	a("R::VhBuyer BoxLayout!vh-topbar", {
		gravity = { -1, 0 },
		innerSpacing = { 8, 0 },
		margin = { 4, 0, 0, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-tabs", {
		innerSpacing = { 2, 0 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer TextInputField!vh-search", {
		minSize = { 280, -1 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer TextView!vh-count", {
		gravity = { 0, 0.5 },
		color = colors.NeutralLight,
	})

	-- buttons and chips
	a("R::VhBuyer Button!vh-button", {
		padding = { 5, 12, 5, 12 },
		backgroundColor1 = colors.BaseMedium,
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer Button!vh-button:hover", {
		backgroundColor1 = colors.AccentDark,
	})
	a("R::VhBuyer Button!vh-small", {
		padding = { 3, 10, 3, 10 },
	})
	a("R::VhBuyer Button!vh-primary", {
		backgroundColor1 = colors.AccentMedium,
	})
	a("R::VhBuyer Button!vh-primary:hover", {
		backgroundColor1 = colors.AccentLight,
	})
	a("R::VhBuyer Button!vh-add", {
		backgroundColor1 = colors.AccentDark,
		padding = { 3, 8, 3, 8 },
		margin = { 0, 4, 0, 4 },
		gravity = { 0.5, 0.5 },
	})
	a("R::VhBuyer Button!vh-add:hover", {
		backgroundColor1 = colors.AccentMedium,
	})
	-- tabs (after the generic button rules: same specificity, so these win)
	a("R::VhBuyer Button!vh-tab", {
		padding = { 6, 14, 6, 14 },
		backgroundColor1 = colors.BaseMedium,
	})
	a("R::VhBuyer Button!vh-tab:hover", {
		backgroundColor1 = colors.AccentDark,
	})
	a("R::VhBuyer Button!vh-tab!vh-tab-active, R::VhBuyer Button!vh-tab!vh-tab-active:hover", {
		backgroundColor1 = colors.AccentMedium,
	})
	a("R::VhBuyer Button!vh-tab!vh-tab-active TextView", {
		color = colors.NeutralLightest,
	})
	a("R::VhBuyer ToggleButton!vh-chip", {
		padding = { 3, 8, 3, 8 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer ToggleButton!vh-cargo-chip", {
		padding = { 2, 2, 2, 2 },
	})
	a("R::VhBuyer ImageView!vh-cargo-icon", {
		size = { 20, 20 },
		maxSize = { 20, 20 },
	})
	-- packed to the left, not stretched (see the spacers)
	a("R::VhBuyer BoxLayout!vh-filter-row", {
		gravity = { 0, 0 },
		innerSpacing = { 6, 0 },
	})
	-- the cargo filter, like the game's (vehicle_store.css.lua, CargoFilterBar): passengers,
	-- All cargo and the cargo types each in a dark box with the game's card border
	a("R::VhBuyer BoxLayout!vh-cargo-bar", {
		gravity = { 0, 0 },
		innerSpacing = { 4, 0 },
	})
	a("R::VhBuyer R::Component!vh-cargo-group", {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/icons/card_border.tga",
			horizontal = { 0, 8, 9, 17 },
			vertical = { 0, 8, 9, 17 },
		},
		borderImage = {
			fileName = "::/gui/entity_window/design/card_contour.tga",
			horizontal = { 0, 6, 26, 32 },
			vertical = { 0, 6, 26, 32 },
		},
		backgroundColor1 = colors.BaseDark,
		borderColor = colors.Invisible,
		gravity = { 0, -1 },
		padding = { 2, 2, 2, 2 },
	})
	a("R::VhBuyer BoxLayout!vh-cargo-group-box", {
		gravity = { -1, -1 },
		innerSpacing = { 0, 2 },
	})
	-- passengers and All cargo: one button, in the middle of a box as tall as the types' box
	a("R::VhBuyer R::Component!vh-cargo-single ToggleButton!vh-cargo-chip", {
		gravity = { 0.5, 0.5 },
	})
	a("R::VhBuyer BoxLayout!vh-cargo-row", {
		gravity = { 0, 0 },
		innerSpacing = { 2, 0 },
	})
	-- crowded (a train and a vehicle's details open): the filters in one row across the card, the
	-- cargo types in one line after the other filters that takes the rest of the width and scrolls
	-- sideways. 28 px of icons + room for the scroll bar (always kept, so nothing moves when it
	-- shows); the other filters sit centered on the icons, above the bar's room
	a("R::VhBuyer BoxLayout!vh-filter-row!vh-filter-wide", {
		gravity = { -1, 0 },
		innerSpacing = { 8, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-filter-row!vh-filter-side", {
		gravity = { 0, 0.5 },
		margin = { 0, 0, 10, 0 },
	})
	a("R::VhBuyer ScrollArea!vh-cargo-scroll", {
		gravity = { -1, 0 },
		size = { -1, 40 },
		minSize = { 120, 40 },
	})
	a("R::VhBuyer TextView!vh-filter-label", {
		gravity = { 0, 0.5 },
		margin = { 0, 2, 0, 6 },
		color = colors.NeutralLight,
	})
	a("R::VhBuyer TextView!vh-muted", {
		gravity = { 0, 0.5 },
		color = colors.NeutralLight,
	})

	-- the table takes whatever height is left (like the game's statistics tables), so the
	-- panels above and below always fit in the window
	a("R::VhBuyer DataTable", {
		gravity = { -1, -1 },
		minSize = { -1, 150 },
	})
	-- cells fill their table cell (also in height), so the open row's tint covers the whole row
	a("R::VhBuyer !vh-cell-recipe", {
		gravity = { -1, -1 },
	})
	a("R::VhBuyer BoxLayout!vh-cell", {
		gravity = { -1, -1 },
	})
	a("R::VhBuyer TextView!vh-cell-empty", {
		color = colors.NeutralMedium,
	})
	-- the + Add / Buy cell: a plain panel behind the button, tinted like the row buttons
	a("R::VhBuyer R::Component!vh-add-bg", {
		gravity = { -1, -1 },
		backgroundColor = colors.Invisible,
		backgroundImage1 = {
			fileName = "::/gui/builtin/button/compact_surface.tga",
			horizontal = { 0, 5, 7, 12 },
			vertical = { 0, 5, 7, 12 },
		},
		backgroundColor1 = colors.Invisible,
	})
	a("R::VhBuyer BoxLayout!vh-add-box", {
		gravity = { -1, -1 },
	})
	-- (a square fill, like the game's own list rows: a tinted button picture has rounded corners,
	-- and a row looked like a string of rounded boxes, Ethan 5 Oct)
	a("R::VhBuyer R::Component!vh-add-bg!vh-row-open", {
		backgroundColor = colors.AccentVeryDark,
	})
	a("R::VhBuyer TextView!vh-cell-text", {
		gravity = { 0.5, 0.5 },
		color = colors.NeutralVeryLight,
	})
	-- windows that cut off long trains and long names (a ScrollArea without scroll bars)
	a("R::VhBuyer ScrollArea!vh-icons-clip", {
		size = { 88, 34 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer BoxLayout!vh-icons-clip-box", {
		innerSpacing = { 1, 0 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer ScrollArea!vh-name-clip", {
		gravity = { -1, 0.5 },
		minSize = { 60, 42 },
	})
	a("R::VhBuyer BoxLayout!vh-name-clip-box", {
		gravity = { 0, 0.5 },
	})
	-- a tag next to the name (light rail), like the store's own tags
	a("R::VhBuyer TextView!vh-tag", {
		backgroundImage1 = {
			fileName = "::/gui/builtin/button/compact_surface.tga",
			horizontal = { 0, 5, 7, 12 },
			vertical = { 0, 5, 7, 12 },
		},
		backgroundColor1 = colors.AccentDark,
		color = colors.NeutralLightest,
		padding = { 1, 5, 1, 5 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer BoxLayout!vh-name-line", {
		innerSpacing = { 6, 0 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-sub-row", {
		innerSpacing = { 4, 0 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer ImageView!vh-icon", {
		maxSize = { 86, 28 },
	})
	-- the see-through buttons that make a whole row clickable: no frame or tint on hover or click
	-- (the game gives buttons in tables a framed surface, and a border on hover and click)
	a("R::VhBuyer Button!vh-row-button", {
		gravity = { -1, -1 },
		padding = { 2, 0, 2, 0 },
		margin = { 0, 0, 0, 0 },
		backgroundColor = colors.Invisible,
		backgroundColor1 = colors.Invisible,
		borderColor = colors.Invisible,
	})
	a("R::VhBuyer Button!vh-row-button:hover, R::VhBuyer Button!vh-row-button:active", {
		backgroundColor = colors.Invisible,
		backgroundColor1 = colors.Invisible,
		borderColor = colors.Invisible,
	})
	-- the row whose details are open: tinted across all its cells, with a square fill (the button
	-- picture has rounded corners: every cell was its own rounded box, Ethan 5 Oct)
	a("R::VhBuyer Button!vh-row-button!vh-row-open, R::VhBuyer Button!vh-row-button!vh-row-open:hover, R::VhBuyer Button!vh-row-button!vh-row-open:active", {
		backgroundColor = colors.AccentVeryDark,
		backgroundColor1 = colors.Invisible,
		borderColor = colors.Invisible,
	})
	-- controller: the row whose name or + Add has the focus is lit as one box. The game shows the
	-- focus as :hover (the name cell: vh-pad), the other cells and + Add's panel get vh-row-lit.
	-- (After the open-row rules: the same weight, so these win.)
	a([[R::VhBuyer Button!vh-row-button!vh-pad:hover, R::VhBuyer Button!vh-row-button!vh-pad!vh-row-open:hover,
		R::VhBuyer Button!vh-row-button!vh-row-lit, R::VhBuyer Button!vh-row-button!vh-row-lit:hover,
		R::VhBuyer Button!vh-row-button!vh-row-lit:active, R::VhBuyer Button!vh-row-button!vh-row-lit!vh-row-open]], {
		backgroundColor = colors.AccentDark,
		backgroundColor1 = colors.Invisible,
		borderColor = colors.Invisible,
	})
	a("R::VhBuyer R::Component!vh-add-bg!vh-row-lit, R::VhBuyer R::Component!vh-add-bg!vh-row-lit!vh-row-open", {
		backgroundColor = colors.AccentDark,
	})
	-- the details in their own recipe (VhDetails): its box spans the window like the card did
	a("R::VhBuyer BoxLayout!vh-details-wrap", {
		gravity = { -1, 0 },
	})
	a("R::VhBuyer TextView!vh-name!vh-name-open", {
		color = colors.AccentVeryLight,
	})
	a("R::VhBuyer ImageView!vh-arrow", {
		size = { 14, 14 },
		gravity = { 0, 0.5 },
		color = colors.AccentVeryLight,
	})
	a("R::VhBuyer BoxLayout!vh-name-inner", {
		gravity = { -1, 0.5 },
		innerSpacing = { 8, 0 },
		margin = { 0, 0, 0, 4 },
	})
	-- every cell is a see-through button (click anywhere on a row for its details)
	a("R::VhBuyer BoxLayout!vh-cell-inner", {
		minSize = { 8, 8 },
	})
	a("R::VhBuyer BoxLayout!vh-name-box", {
		gravity = { -1, 0.5 },
	})
	a("R::VhBuyer TextView!vh-name", {
		gravity = { 0, 0 },
		color = colors.NeutralLightest,
		fontWeight = "Medium",
	})
	a("R::VhBuyer TextView!vh-sub", {
		gravity = { 0, 0 },
		color = colors.NeutralLight,
	})
	-- our number cells: the number, and under it a bar as wide as the column less a gap (2 px on the
	-- left, 6 on the right), so two columns' bars never touch (a fixed 64 px bar was as wide as the
	-- narrower columns at 1080p and ran into the next one, Ethan 5 Oct). The cell's box fills the
	-- column, like the name cell's
	a("R::VhBuyer BoxLayout!vh-metric-inner", {
		gravity = { -1, 0.5 },
	})
	a("R::VhBuyer TextView!vh-metric-text", {
		gravity = { 0, 0.5 },
		color = colors.AccentVeryLight,
	})
	a("R::VhBuyer ProgressBar!vh-metric-bar", {
		gravity = { -1, 0.5 },
		size = { -1, 5 },
		minSize = { 8, 5 },
		margin = { 2, 6, 0, 2 },
		backgroundColor1 = colors.BaseDark,
		color = colors.AccentLight,
	})

	-- the details of one vehicle
	a("R::VhBuyer R::Component!vh-details", {
		borderColor = colors.AccentMedium,
	})
	a("R::VhBuyer BoxLayout!vh-detail-header", {
		gravity = { -1, 0 },
		innerSpacing = { 10, 0 },
	})
	a("R::VhBuyer TextView!vh-detail-title", {
		color = colors.NeutralLightest,
		fontWeight = "Medium",
	})
	-- the top of the details: the picture, and right of it the header, the cars and the picker
	a("R::VhBuyer BoxLayout!vh-detail-toprow", {
		gravity = { -1, 0 },
		innerSpacing = { 16, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-detail-top", {
		gravity = { -1, 0 },
		innerSpacing = { 0, 6 },
	})
	a("R::VhBuyer BoxLayout!vh-option-rows", {
		gravity = { 0, 0 },
		innerSpacing = { 0, 4 },
	})
	a("R::VhBuyer BoxLayout!vh-large-box", {
		gravity = { 0, 0 },
	})
	a("R::VhBuyer ImageView!vh-large-picture", {
		size = { 200, 112 },
		gravity = { 0, 0 },
	})
	-- every car of the vehicle in one row; long trains scroll sideways
	a("R::VhBuyer ScrollArea!vh-strip", {
		gravity = { -1, 0 },
		size = { -1, 34 },
	})
	a("R::VhBuyer BoxLayout!vh-strip-box", {
		innerSpacing = { 1, 0 },
		gravity = { 0, 0.5 },
	})
	-- pictures that may be painted (the game's VehicleImage puts a box around its picture)
	-- painted pictures are the game's VehicleImage inside a box of ours ("<class>-box"), so the size
	-- limits are set through both
	a("R::VhBuyer ImageView!vh-detail-icon, R::VhBuyer R::VehicleImage!vh-detail-icon ImageView, R::VhBuyer BoxLayout!vh-detail-icon-box ImageView", {
		maxSize = { 120, 30 },
	})
	a("R::VhBuyer ImageView!vh-part-icon, R::VhBuyer R::VehicleImage!vh-part-icon ImageView, R::VhBuyer BoxLayout!vh-part-icon-box ImageView", {
		maxSize = { 64, 22 },
	})
	a("R::VhBuyer ImageView!vh-option-icon, R::VhBuyer R::VehicleImage!vh-option-icon ImageView, R::VhBuyer BoxLayout!vh-option-icon-box ImageView", {
		maxSize = { 60, 20 },
	})
	-- sections of numbers
	a("R::VhBuyer BoxLayout!vh-sections", {
		gravity = { 0, 0 },
		innerSpacing = { 48, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-section-col", {
		gravity = { 0, 0 },
		innerSpacing = { 0, 8 },
	})
	a("R::VhBuyer BoxLayout!vh-section", {
		gravity = { 0, 0 },
		innerSpacing = { 0, 2 },
	})
	-- a column of labels next to a column of values
	a("R::VhBuyer BoxLayout!vh-kv-labels, R::VhBuyer BoxLayout!vh-kv-values", {
		gravity = { 0, 0 },
		innerSpacing = { 0, 3 },
	})
	a("R::VhBuyer BoxLayout!vh-kv-label-box", {
		innerSpacing = { 6, 0 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer TextView!vh-section-title", {
		color = colors.AccentVeryLight,
		margin = { 6, 0, 2, 0 },
		fontWeight = "Medium",
	})
	a("R::VhBuyer BoxLayout!vh-kv", {
		gravity = { 0, 0 },
		innerSpacing = { 16, 0 },
	})
	a("R::VhBuyer ImageView!vh-kv-icon", {
		size = { 16, 16 },
		gravity = { 0, 0.5 },
		color = colors.NeutralLight,
	})
	-- Carries: the game's cargo icons in one row, as tall as a line of text
	a("R::VhBuyer BoxLayout!vh-carries", {
		gravity = { 0, 0 },
		innerSpacing = { 4, 0 },
	})
	-- more than one row of cargo icons: as far apart as the label rows next to them
	a("R::VhBuyer BoxLayout!vh-carries-rows", {
		gravity = { 0, 0 },
		innerSpacing = { 0, 3 },
	})
	a("R::VhBuyer ImageView!vh-carries-icon", {
		size = { 18, 18 },
		maxSize = { 18, 18 },
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer R::Component!vh-kv-icon-space", {
		size = { 16, 16 },
	})
	a("R::VhBuyer TextView!vh-kv-label", {
		color = colors.NeutralLight,
		gravity = { 0, 0 },
	})
	a("R::VhBuyer TextView!vh-kv-value", {
		color = colors.NeutralLightest,
		fontWeight = "Medium",
		gravity = { 0, 0 },
	})
	a("R::VhBuyer TextView!vh-desc", {
		color = colors.NeutralLight,
		size = { 900, -1 },
		textAutoWrap = true,
	})
	a("R::VhBuyer ScrollArea!vh-desc-scroll", {
		gravity = { -1, 0 },
		maxSize = { -1, 54 },
	})
	-- liveries / versions to pick from
	a("R::VhBuyer BoxLayout!vh-options-row", {
		gravity = { -1, 0 },
		innerSpacing = { 10, 0 },
	})
	-- the liveries / versions: a scroll window as wide as the card allows, as tall as 2, 3 or
	-- 3½ rows (an option row is about 31 px with the medium UI font, plus 4 px between rows)
	a("R::VhBuyer ScrollArea!vh-options-scroll", {
		gravity = { -1, 0 },
	})
	local optionHeights = { ["2"] = 72, ["3"] = 110, many = 124 }
	for _, f in ipairs({ { "", 1 }, { "!font-small ", 0.92 }, { "!font-large ", 1.2 } }) do
		for k, h in pairs(optionHeights) do
			a(f[1] .. "R::VhBuyer ScrollArea!vh-options-scroll-" .. k, {
				size = { -1, math.floor(h * f[2] + 0.5) },
			})
		end
	end
	a("R::VhBuyer Button!vh-option", {
		padding = { 2, 8, 2, 8 },
		backgroundColor1 = colors.BaseMedium,
	})
	a("R::VhBuyer Button!vh-option:hover", {
		backgroundColor1 = colors.AccentDark,
	})
	a("R::VhBuyer Button!vh-option!vh-option-on, R::VhBuyer Button!vh-option!vh-option-on:hover", {
		backgroundColor1 = colors.AccentMedium,
	})
	a("R::VhBuyer BoxLayout!vh-option-box", {
		innerSpacing = { 5, 0 },
	})
	-- the paint bucket (the store's own look for it)
	a("R::VhBuyer ColorChooserButton!vh-color", {
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer ColorChooserButton!vh-color Button", {
		backgroundImage1 = {
			fileName = "::/gui/builtin/button/default_surface.tga",
			horizontal = { 0, 9, 21, 30 },
			vertical = { 0, 9, 21, 30 },
		},
		borderImage = {
			fileName = "::/gui/builtin/button/default_contour.tga",
			horizontal = { 0, 9, 21, 30 },
			vertical = { 0, 9, 21, 30 },
		},
		backgroundColor1 = colors.AccentMedium,
		borderColor = colors.Invisible,
		padding = { 4, 4, 4, 4 },
	})
	a("R::VhBuyer ColorChooserButton!vh-color:hover, R::VhBuyer ColorChooserButton!vh-color:active", {
		borderColor = colors.AccentVeryLight,
		backgroundColor1 = colors.AccentLight,
	})

	-- the train
	a("R::VhBuyer R::Component!vh-train", {
		gravity = { -1, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-parts-empty", {
		minSize = { -1, 40 },
	})
	a("R::VhBuyer BoxLayout!vh-parts-empty TextView", {
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer TextView!vh-muted-value", {
		color = colors.NeutralLight,
	})
	a("R::VhBuyer BoxLayout!vh-train-main", {
		gravity = { -1, -1 },
		innerSpacing = { 0, 6 },
	})
	a("R::VhBuyer TextView!vh-title", {
		color = colors.AccentVeryLight,
	})
	a("R::VhBuyer ScrollArea!vh-parts-scroll", {
		gravity = { -1, 0 },
		size = { -1, 66 },
	})
	a("R::VhBuyer BoxLayout!vh-parts-row", {
		innerSpacing = { 4, 0 },
		gravity = { 0, 0 },
	})
	-- the train's tiles, like the game's cart (vehicle_store.css.lua, VehicleCartVehicle)
	a("R::VhBuyer BoxLayout!vh-cart-part-box", {
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer R::Component!vh-cart-part", {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/icons/card_border.tga",
			horizontal = { 0, 8, 9, 17 },
			vertical = { 0, 8, 9, 17 },
		},
		backgroundColor1 = colors.BaseMedium,
		borderImage = {
			fileName = "::/gui/builtin/button/default_contour.tga",
			horizontal = { 0, 9, 21, 30 },
			vertical = { 0, 9, 21, 30 },
		},
		borderColor = colors.Invisible,
		size = { -1, 56 },
		minSize = { 44, 56 },
	})
	a("R::VhBuyer R::Component!vh-cart-part!vh-cart-hover", {
		backgroundColor1 = withAlpha(colors.NeutralVeryLight, transparency.Medium or 0.5),
	})
	a("R::VhBuyer R::Component!vh-cart-part!vh-cart-grabbed", {
		borderColor = colors.AccentMedium,
	})
	-- controller: the tile is held (the move button is down) and moves with left / right
	a("R::VhBuyer R::Component!vh-cart-part!vh-cart-hold", {
		backgroundColor1 = withAlpha(colors.AccentMedium, transparency.Medium or 0.5),
		borderColor = colors.AccentLight,
	})
	a("R::VhBuyer TextView!vh-pad-hint", {
		margin = { 4, 0, 0, 0 },
	})
	a("R::VhBuyer R::Component!vh-cart-part FloatingLayout", {
		gravity = { -1, -1 },
	})
	-- room left and right of the pictures for the buttons, as in the game
	a("R::VhBuyer BoxLayout!vh-cart-pictures", {
		outerSpacing = { 0, 18 },
		innerSpacing = { 1, 0 },
	})
	a("R::VhBuyer ImageView!vh-part-icon", {
		gravity = { 0, 0.5 },
	})
	a("R::VhBuyer TextView!vh-cart-count", {
		gravity = { 0, 0.5 },
		margin = { 0, 0, 0, 4 },
		color = colors.NeutralVeryLight,
	})
	a("R::VhBuyer TextView!vh-cart-name", {
		gravity = { 0, 0.5 },
	})
	-- the drop halves: invisible buttons over the whole tile
	a("R::VhBuyer R::Component!vh-cart-dnd, R::VhBuyer R::Component!vh-cart-dnd > BoxLayout, R::VhBuyer BoxLayout!vh-cart-dnd-box", {
		gravity = { -1, -1 },
	})
	a("R::VhBuyer Button!vh-cart-dnd-button, R::VhBuyer Button!vh-cart-dnd-button:hover, R::VhBuyer Button!vh-cart-dnd-button:active", {
		gravity = { -1, -1 },
		backgroundColor = colors.Invisible,
		backgroundColor1 = colors.Invisible,
		borderColor = colors.Invisible,
	})
	-- where a dragged tile goes: a bar on the edge of the tile half it is over (a plain
	-- Component draws a solid backgroundColor, like the game's move-vehicle-guide; with only
	-- backgroundColor1 and no image the bar was invisible), and that half lit
	a("R::VhBuyer R::Component!vh-cart-guide", {
		size = { 4, 52 },
		backgroundColor = colors.AccentVeryLight,
		backgroundColor1 = colors.AccentVeryLight,
	})
	a("R::VhBuyer Button!vh-cart-dnd-button!vh-cart-dnd-on, R::VhBuyer Button!vh-cart-dnd-button!vh-cart-dnd-on:hover, R::VhBuyer Button!vh-cart-dnd-button!vh-cart-dnd-on:active", {
		backgroundColor = withAlpha(colors.AccentMedium, transparency.High or 0.25),
		backgroundColor1 = withAlpha(colors.AccentMedium, transparency.High or 0.25),
	})
	-- the game's small corner buttons
	a("R::VhBuyer Button!vh-move-button", {
		backgroundImage1 = {
			fileName = "::/gui/entity_window/design/collapsible_button_surface.tga",
			horizontal = { 0, 3, 9, 12 },
			vertical = { 0, 3, 9, 12 },
		},
		padding = { 2, 2, 2, 2 },
		margin = { 1, 1, 1, 1 },
		borderColor = colors.Invisible,
		backgroundColor1 = colors.Invisible,
	})
	a("R::VhBuyer Button!vh-move-button:hover", {
		borderColor = colors.Invisible,
		backgroundColor1 = withAlpha(colors.AccentMedium, transparency.Low or 0.75),
	})
	a("R::VhBuyer ImageView!vh-move-icon", {
		size = { 12, 12 },
	})
	a("R::VhBuyer TextView!vh-move-text", {
		size = { 12, 12 },
		gravity = { 0.5, 0.5 },
	})
	a("R::VhBuyer BoxLayout!vh-stats", {
		innerSpacing = { 22, 0 },
		margin = { 4, 0, 0, 0 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-stat-col", {
		innerSpacing = { 0, 6 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-stat", {
		gravity = { 0, 0 },
	})
	a("R::VhBuyer TextView!vh-stat-label", {
		color = colors.NeutralLight,
	})
	a("R::VhBuyer TextView!vh-stat-value", {
		color = colors.NeutralLightest,
		fontWeight = "Medium",
	})
	a("R::VhBuyer TextView!vh-good", {
		color = colors.Ok,
	})
	a("R::VhBuyer TextView!vh-bad", {
		color = colors.Negative,
	})
	a("R::VhBuyer TextView!vh-warn", {
		color = colors.Warning,
	})
	a("R::VhBuyer BoxLayout!vh-actions", {
		minSize = { 260, -1 },
		innerSpacing = { 0, 8 },
		gravity = { 0, 0 },
	})
	a("R::VhBuyer BoxLayout!vh-action-row", {
		innerSpacing = { 6, 0 },
	})
	a("R::VhBuyer Button!vh-buy", {
		minSize = { 260, 48 },
	})
	a("R::VhBuyer TextView!vh-message", {
		color = colors.NeutralVeryLight,
	})

	return result
end

--!strict
--[[
	HubConfig
	Every Ranch Hub dimension, position and colour (Stage 1 of the Ranch Hub plan).
	Source: DOCUMENTATION/RANCH_HUB_PROPOSAL.md, decisions O1/O2/O5 approved 2026-11-20.

	All sizes are PROVISIONAL grey-box values (approved as adjustable, not permanent): change them
	here and the whole layout (and its geometry tests) follows. Nothing here is hard-coded elsewhere.

	Hub frame (used by HubLayout):
	  origin = hub centre, on the ground (level with the top of the starting floor)
	  +X     = along the runway toward the Plains starting floor (= the course's forward direction)
	  +Y     = to the right of that direction
	  angles = measured from +X toward +Y, in degrees
]]

local HubConfig = {}

-- Plots (O1: five plots 72° apart; the runway uses the 0° gap between Plot 5 and Plot 1)
HubConfig.PlotCount = 5
HubConfig.FirstPlotAngleDegrees = 36 -- Plot 1; then 108, 180, 252, 324
HubConfig.PlotAngleStepDegrees = 72
HubConfig.PlotCentreRadius = 195 -- O2 (provisional)
HubConfig.PlotWidth = 120 -- across the plot, sideways (O2)
HubConfig.PlotDepth = 120 -- from the plaza-facing front edge to the back edge (O2)

-- Plaza, grass and runway (O2, provisional)
HubConfig.PlazaRadius = 120
HubConfig.GrassRadius = 275
HubConfig.RunwayWidth = 40
HubConfig.RunwayLength = 160 -- from the plaza edge to the starting floor's back edge

-- Inner animal pen (O5: anchored toward the back, grows toward the entrance and sideways)
HubConfig.Pen = table.freeze({
	InitialWidth = 60,
	InitialDepth = 60,
	BackMargin = 4, -- studs between the pen and the plot's back edge
	SideMargin = 4, -- minimum studs between the pen and each plot side
	FrontStrip = 12, -- studs kept free at the plot's front for the entrance and home point
})

-- Per-plot points, in the plot's own frame (Front = toward the plaza, Lateral = + to the plot's right
-- when looking from the plaza at the plot). Positions of the sign and pad sides are O6 (still open).
HubConfig.PlotPoints = table.freeze({
	HomePointInset = 6, -- home point: this far onto the dirt from the front edge
	SignOutset = 5, -- sign: this far in front of the front edge (on the grass strip)
	SignLateral = -30,
	PadOutset = 7.5, -- collection pad centre: this far in front of the front edge
	PadLateral = 30,
	PadRadius = 5,
})

-- Merchant spots (inside the plaza). Length runs along the radial direction, Width across it.
HubConfig.PermanentMerchant = table.freeze({ Radius = 108, AngleDegrees = 17, Length = 16, Width = 10 })
HubConfig.TravelingMerchant = table.freeze({ Radius = 108, AngleDegrees = 197, Length = 16, Width = 10 })

-- Plot marker colours (pads, signs), from the visual reference. Index = plot number.
HubConfig.PlotColors = table.freeze({
	Color3.fromRGB(242, 196, 0), -- 1 yellow
	Color3.fromRGB(255, 111, 181), -- 2 pink
	Color3.fromRGB(60, 200, 232), -- 3 cyan
	Color3.fromRGB(92, 214, 92), -- 4 green
	Color3.fromRGB(255, 154, 60), -- 5 orange
})

-- Minimum clearances the geometry tests enforce (studs). Not gameplay; layout safety margins.
HubConfig.Validation = table.freeze({
	MinPlotGap = 30, -- between neighbouring plots
	MinPlotToPlaza = 10,
	MinPlotToRunway = 8,
	MinPlotToFloor = 20,
	MinPlotToMerchant = 15,
	MinMerchantToRunway = 8,
	MinMerchantToPath = 4, -- to the nominal walking lines (below)
	MinGrassMargin = 8, -- outermost plot corner to the grass edge
	EntrancePathWidth = 16, -- nominal walking line from the centre to each plot entrance
})

return table.freeze(HubConfig)

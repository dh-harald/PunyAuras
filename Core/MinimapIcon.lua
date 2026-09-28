-- Minimap icon: a LibDataBroker-1.1 launcher shown on the minimap through
-- LibDBIcon-1.0, wired the same way as Bagzen and ZygorGuidesViewerNG.

local PA, L, P, G = unpack(PunyAuras)

local AddOnName = "PunyAuras"

-- Case must match the file on disk: Unreal Azeroth resolves media paths
-- case-sensitively, the 1.12.1 client does not. The file name is unique on
-- purpose: named plain "icon", the client drew ZygorGuidesViewerNG's
-- Skins\icon instead, even though GetTexture() returned this path.
local ICON_TEXTURE = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\PunyAurasIcon"

-- LibDBIcon-1.0 keeps its state (hide, minimapPos, lock) in this table.
P.minimap = { hide = false }

function PA:InitializeMinimapIcon()
	local DBIcon = LibStub("LibDBIcon-1.0")

	-- The library instance is shared with every other addon that embeds it;
	-- Bagzen and ZygorGuidesViewerNG set the same tooltip, so it stays the
	-- same whichever addon loads first.
	DBIcon.tooltip = GameTooltip

	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(AddOnName, {
		type = "launcher",
		icon = ICON_TEXTURE,
		tocname = AddOnName,
		label = AddOnName,
		OnTooltipShow = function(tooltip)
			tooltip:AddDoubleLine(AddOnName, PA.version)
			tooltip:AddDoubleLine(L["Left-Click"], L["Toggle Options Window"], 1, 1, 1, 1, 1, 1)
		end,
		-- LibDBIcon-1.0 passes the mouse button as the second argument.
		OnClick = function(_, button)
			if button == "LeftButton" then
				PA:ToggleOptions()
			end
		end,
	})

	DBIcon:Register(AddOnName, launcher, self.db.profile.minimap)
end

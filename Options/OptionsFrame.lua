-- Options window: behaviour of PunyAurasOptions (widgets in OptionsFrame.xml).
--
-- The layout follows WeakAuras' own options window
-- (WeakAurasOptions/OptionsFrames/OptionsFrame.lua, GPLv2): a portrait frame
-- with a title bar, a toolbar and a filter box over the aura list on the
-- left, and the option pane on the right. WeakAuras builds it with
-- AceGUI-3.0, which does not work on Unreal Azeroth, so the widgets here are
-- plain XML frames.
--
-- Unreal Azeroth rules this file follows:
--   * Hiding a frame does not hide its child frames, so every child frame is
--     shown and hidden explicitly (UpdatePartsShown).
--   * Highlight/pushed state textures and the HIGHLIGHT draw layer are drawn
--     permanently on addon-created buttons; hover feedback is a texture
--     toggled from OnEnter/OnLeave.
--   * RegisterForDrag suppresses the button release, so moving starts from
--     OnMouseDown, after a throwaway StartMoving /
--     StopMovingOrSizing pair that collapses the anchors to the single point
--     the client moves (UnrealUI core/mover.lua).
--   * Frames are reached by global name: GetChildren() returns crippled
--     proxies for XML-created frames.
--   * Frame levels are set explicitly, so the controls stay above the drag
--     handle and the panels.

local _G = _G or getfenv()
local PA, L, P, G = unpack(PunyAuras)
local Compat = PunyAuras.Compat

local FRAME_NAME = "PunyAurasOptions"
local TEXTURES = "Interface\\AddOns\\PunyAuras\\Media\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Sizes from WeakAuras' options window. The window is not resizable.
local WIDTH, HEIGHT = 830, 665
local MINIMIZED_WIDTH, MINIMIZED_HEIGHT = 160, 75

-- Horizontal geometry of the aura list, matching the anchors in
-- OptionsFrame.xml: the right pane starts RIGHT_PANE_OFFSET from the
-- window's right edge, the list keeps LIST_MARGIN on both sides and the
-- scroll frame is inset by LIST_INSET inside it.
local RIGHT_PANE_OFFSET = 505
local LIST_MARGIN = 17
local LIST_INSET = 6
-- The strip on the list's right kept for its scrollbar (LibConfig-1.0's,
-- 16px wide), matching the scroll frame's right inset in OptionsFrame.xml.
local LIST_SCROLLBAR_GUTTER = 18
-- Width of the list's rows. Derived from the window's fixed width: the
-- GetWidth() of an anchor-sized frame (the list) is scaled by the UI scale on
-- the 1.12.1 client.
local LIST_CONTENT_WIDTH = WIDTH - RIGHT_PANE_OFFSET - 2 * LIST_MARGIN - 2 * LIST_INSET
	- LIST_SCROLLBAR_GUTTER
-- Height of the list's visible part: the list pane runs from 86px below the
-- window's top to 12px above its bottom, and the scroll frame is inset by
-- LIST_INSET in it. From the fixed window size, as the GetHeight() of an
-- anchor-sized frame is scaled by the UI scale on the 1.12.1 client.
local LIST_VIEW_HEIGHT = HEIGHT - 86 - 12 - 2 * LIST_INSET
local HEADER_HEIGHT, HEADER_SPACING = 20, 2
-- Room for the grouping hint over the list: two lines of small text.
local GROUPING_HINT_HEIGHT = 30
local DISPLAY_HEIGHT = 32
-- A group's children are indented by this much; the gap holds their
-- move-up, ungroup and move-down buttons.
local CHILD_INDENT = 12

-- The list row's group buttons. WeakAuras draws "group" with a glue-screen
-- rotation arrow and the others with the money frame's left arrow, rotated;
-- here the money frame's arrows, which the 1.12.1 FrameXML uses itself, and
-- WeakAuras' own move-up/move-down textures, as rotating a texture takes the
-- eight-argument SetTexCoord, which draws skewed on Unreal Azeroth.
local ROW_BUTTON_TEXTURES = {
	Group = "Interface\\MoneyFrame\\Arrow-Right-Up",
	Ungroup = "Interface\\MoneyFrame\\Arrow-Left-Up",
	Up = TEXTURES .. "PunyAurasMoveUp",
	Down = TEXTURES .. "PunyAurasMoveDown",
}

-- Width the aura options are laid out to: the right pane (RIGHT_PANE_OFFSET
-- minus its 17px right margin), less the 10/6px insets of the host frame in
-- the tab pane, less LibConfig-1.0's 20px scrollbar gutter and its 6px
-- safety margin.
local AURA_OPTIONS_WIDTH = (RIGHT_PANE_OFFSET - 17) - 16 - 26
local AURA_OPTIONS_LABEL_WIDTH = 180

-- The right-pane tab buttons in OptionsFrame.xml, by tab key.
local TAB_BUTTONS = {
	region = "RightPaneTabsRegion",
	trigger = "RightPaneTabsTrigger",
	conditions = "RightPaneTabsConditions",
	actions = "RightPaneTabsActions",
	load = "RightPaneTabsLoad",
	group = "RightPaneTabsGroup",
}

-- Window position, account-wide like WeakAuras'. `point` stays nil until
-- the window is first moved, and the window then opens centred; x/y are
-- offsets from the same point of UIParent. `loadedCollapsed` and
-- `unloadedCollapsed` are the states of the "Loaded/Standby" and "Not
-- Loaded" sections, `collapsedGroups[id]` those of the groups.
G.optionsWindow = { collapsedGroups = {} }

local frame
local parts = {}
-- LibConfig-1.0 embedded view showing the picked aura's options.
local auraOptions
-- Pooled list rows, one per aura, in list order.
local displayRows = {}
-- The list's scrolling: `offset` (pixels from the top), `maxOffset`, and
-- `scrollBar`, LibConfig-1.0's scrollbar control.
local listState = { offset = 0, maxOffset = 0 }

-- Whether a list entry at `top` (pixels from the list's top), `height` tall,
-- is at least partly inside the scrolled view.
local function ListInView(top, height)
	return top + height > listState.offset and top < listState.offset + LIST_VIEW_HEIGHT
end

-- Fits the scroll offset to a list `total` pixels tall and updates the
-- scrollbar. Returns true when the offset had to change, and the list has
-- to be laid out again.
local function SyncListScroll(total)
	local maxOffset = total - LIST_VIEW_HEIGHT
	if maxOffset < 0 then maxOffset = 0 end
	listState.maxOffset = maxOffset
	local changed = false
	if listState.offset > maxOffset then
		listState.offset = maxOffset
		changed = true
	end
	local bar = listState.scrollBar
	if bar then
		bar.SetRange(maxOffset, total > 0 and math.min(1, LIST_VIEW_HEIGHT / total) or 1)
		bar.SetValue(listState.offset)
	end
	return changed
end
-- The line over the list that says what a click does while grouping.
local groupingHint

-- Forward-declared: UpdatePartsShown ends with the first two, UpdateList
-- calls the other two.
local SyncAuraOptions
local SyncTransfer
local EnsureDisplayRows
local ResetRename

local function Get(suffix)
	return _G[FRAME_NAME .. suffix]
end

-- "PunyAuras <version>", or "PunyAuras <version> - <subtitle>" while a
-- sub-view such as the icon picker is open, like WeakAuras' SetTitle.
local function SetTitle(subtitle)
	local text = "PunyAuras " .. PA.version
	if subtitle then
		text = text .. " - " .. subtitle
	end
	Get("TitleText"):SetText(text)
end

local function Round(value)
	return math.floor(value + 0.5)
end

-- Registers a child frame for explicit show/hide. `content` parts are also
-- hidden while the window is minimized; a part with a `condition` is shown
-- only while that function returns true.
local function AddPart(widget, content, condition)
	table.insert(parts, { widget = widget, content = content, condition = condition })
	return widget
end

-- Unreal Azeroth only re-sorts its draw order when a frame is created or
-- reparented. A frame that gets its level, or is shown, after the last such
-- event is drawn at a stale position -- the list rows beneath the window's
-- own translucent background, so they look faded. Reparenting an empty
-- frame, even to the parent it already has, forces the re-sort. It has to
-- run on the next frame: a re-sort in the same frame as the level changes
-- still sees the old order. Harmless on the 1.12.1 client.
local drawOrderFrame, drawOrderTimer
local function ResortOnNextFrame()
	drawOrderTimer:SetScript("OnUpdate", nil)
	pcall(drawOrderFrame.SetParent, drawOrderFrame, UIParent)
end
local function ResortDrawOrder()
	if not drawOrderFrame then
		drawOrderFrame = CreateFrame("Frame", nil, UIParent)
		drawOrderTimer = CreateFrame("Frame", nil, UIParent)
	end
	drawOrderTimer:SetScript("OnUpdate", ResortOnNextFrame)
end

local function UpdatePartsShown()
	local shown = frame:IsShown()
	local i
	for i = 1, Compat.getn(parts) do
		local part = parts[i]
		if shown and not (part.content and frame.minimized)
			and not (part.condition and not part.condition()) then
			part.widget:Show()
		else
			part.widget:Hide()
		end
	end
	SyncAuraOptions()
	SyncTransfer()
	local subtitles = {
		IconPicker = frame.pickerTitle or L["Icon Picker"],
		Import = L["Importing"],
		Export = L["Exporting"],
	}
	SetTitle(subtitles[frame.pickedOption or ""])
	-- The picked aura is shown on screen while the window is open,
	-- minimized included, so it can be looked at without the window in the
	-- way.
	PA:SetPreview(frame:IsShown() and frame.pickedDisplay or nil)
	-- Last: every view change ends here, after its frames got their levels.
	ResortDrawOrder()
end

-- The screen edge or corner the window is closest to, with a small offset
-- from it, which survives a resolution change better than a large offset
-- from the centre. Port of ElvUI's E:CalculateMoverPoints: the screen is
-- split into thirds horizontally and halves vertically, and the edges come
-- from GetTop/GetBottom/GetLeft/GetRight, which measure against UIParent
-- whatever the window is currently anchored to.
local function NearestPoint()
	local cx, cy = frame:GetCenter()
	local screenWidth, screenHeight = UIParent:GetRight(), UIParent:GetTop()
	if not (cx and cy and screenWidth and screenHeight) then return end

	local point, x, y
	if cy >= screenHeight / 2 then
		point = "TOP"
		y = frame:GetTop() - screenHeight
	else
		point = "BOTTOM"
		y = frame:GetBottom()
	end

	if cx >= screenWidth * 2 / 3 then
		point = point .. "RIGHT"
		x = frame:GetRight() - screenWidth
	elseif cx <= screenWidth / 3 then
		point = point .. "LEFT"
		x = frame:GetLeft()
	else
		x = cx - screenWidth / 2
	end

	return point, Round(x), Round(y)
end

-- Stored only, not re-applied: the window stays exactly where it was
-- released, and the point is used the next time the window is placed.
-- Nothing is saved while minimized; restoring keeps the top-right corner
-- in place and the next move saves the full-size window.
local function SavePosition()
	if frame.minimized then return end
	local point, x, y = NearestPoint()
	if not point then return end

	local saved = PA.db.global.optionsWindow
	saved.point, saved.x, saved.y = point, x, y
end

local function ApplyPosition()
	local saved = PA.db.global.optionsWindow
	frame:ClearAllPoints()
	if saved.point then
		frame:SetPoint(saved.point, UIParent, saved.point, saved.x or 0, saved.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function SetMinimized(minimized)
	if (frame.minimized and true or false) == minimized then return end

	local right, top = frame:GetRight(), frame:GetTop()
	frame.minimized = minimized
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)

	if minimized then
		frame:SetWidth(MINIMIZED_WIDTH)
		frame:SetHeight(MINIMIZED_HEIGHT)
		Get("TitleText"):Hide()
		Get("MinimizeButtonIcon"):SetTexture(TEXTURES .. "PunyAurasMaximize")
	else
		frame:SetWidth(WIDTH)
		frame:SetHeight(HEIGHT)
		Get("TitleText"):Show()
		Get("MinimizeButtonIcon"):SetTexture(TEXTURES .. "PunyAurasMinimize")
	end

	UpdatePartsShown()
end

-- Moving by the title bar.
local function StopMove()
	if not frame.moving then return end
	frame.moving = nil

	frame:StopMovingOrSizing()
	-- A user-placed frame's position is also stored and restored by the
	-- 1.12.1 client itself, which would fight the saved nearest point.
	pcall(frame.SetUserPlaced, frame, false)

	SavePosition()
end

local function StartMove()
	if arg1 ~= "LeftButton" or frame.moving then return end
	frame:SetMovable(true)
	if pcall(frame.StartMoving, frame) then
		pcall(frame.StopMovingOrSizing, frame)
	end
	frame:StartMoving()
	frame.moving = true
end

local function AttachHover(button, hover)
	button:SetScript("OnEnter", function() hover:Show() end)
	button:SetScript("OnLeave", function() hover:Hide() end)
end

-- WeakAuras' toolbar button: a 16px icon with the label next to it, as wide
-- as the label plus 24px.
local function SetupToolbarButton(button, text, texture)
	local name = button:GetName()
	_G[name .. "Icon"]:SetTexture(TEXTURES .. texture)

	local label = _G[name .. "Text"]
	label:SetText(text)
	local width = label:GetStringWidth()
	if not width or width <= 0 then
		width = string.len(text) * 7
	end
	button:SetWidth(width + 24)

	AttachHover(button, _G[name .. "Hover"])
end

-- WeakAuras' section header ("Loaded/Standby", "Not Loaded"). The expand
-- button keeps its disabled look while the section has no children;
-- otherwise it shows "-" (expanded) or "+" (collapsed) and calls `onToggle`.
-- `expandDesc`/`collapseDesc` are the button's tooltip lines. UpdateHeader
-- sets the state.
local function SetupHeader(button, text, onToggle, expandDesc, collapseDesc)
	local name = button:GetName()
	_G[name .. "Text"]:SetText(text)

	local expand = _G[name .. "Expand"]
	expand:SetScript("OnEnter", function()
		GameTooltip:SetOwner(button, "ANCHOR_NONE")
		GameTooltip:SetPoint("LEFT", button, "RIGHT", 0, 0)
		GameTooltip:ClearLines()
		if not expand.hasChildren then
			GameTooltip:AddLine(L["Disabled"])
			GameTooltip:AddLine(L["Expansion is disabled because this group has no children"], 1, 1, 1, 1)
		elseif expand.collapsed then
			GameTooltip:AddLine(L["Expand"])
			GameTooltip:AddLine(expandDesc, 1, 1, 1, 1)
		else
			GameTooltip:AddLine(L["Collapse"])
			GameTooltip:AddLine(collapseDesc, 1, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	expand:SetScript("OnLeave", function() GameTooltip:Hide() end)
	expand:SetScript("OnClick", function()
		if expand.hasChildren and onToggle then
			GameTooltip:Hide()
			onToggle()
		end
	end)

	-- `button.inView` is set by UpdateList: false while the list is scrolled
	-- so that the header is out of sight.
	local function Shown() return button.inView ~= false end
	AddPart(button, true, Shown)
	AddPart(expand, true, Shown)
end

local function UpdateHeader(button, hasChildren, collapsed)
	local expand = _G[button:GetName() .. "Expand"]
	expand.hasChildren = hasChildren
	expand.collapsed = collapsed
	if not hasChildren then
		expand:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Disabled")
	elseif collapsed then
		expand:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	else
		expand:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	end
end

-- A search box: a 1px grey frame around a dark fill, "Search" shown while it
-- is empty and unfocused, `onTextChanged(text)` on every edit.
local function SetupSearchBox(box, placeholder, onTextChanged)
	placeholder:SetText(L["Search"])

	-- An addon-created EditBox needs keyboard and mouse enabled explicitly on
	-- Unreal Azeroth, otherwise only pasting works. The font object is set
	-- here too, in case the XML <FontString> does not take on this client.
	pcall(box.SetFontObject, box, GameFontHighlightSmall)
	pcall(box.SetTextInsets, box, 6, 6, 0, 0)
	pcall(box.SetAutoFocus, box, false)
	pcall(box.EnableKeyboard, box, true)
	pcall(box.EnableMouse, box, true)

	box:SetBackdrop({
		edgeFile = WHITE,
		edgeSize = 1,
	})
	box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	local fill = box:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(0, 0, 0, 0.5)
	fill:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)

	local function UpdatePlaceholder()
		if box.hasFocus or (box:GetText() or "") ~= "" then
			placeholder:Hide()
		else
			placeholder:Show()
		end
	end

	box:SetScript("OnEditFocusGained", function()
		box.hasFocus = true
		UpdatePlaceholder()
	end)
	box:SetScript("OnEditFocusLost", function()
		box.hasFocus = nil
		UpdatePlaceholder()
	end)
	box:SetScript("OnTextChanged", function()
		UpdatePlaceholder()
		if onTextChanged then onTextChanged(box:GetText() or "") end
	end)
	box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
	box:SetScript("OnEnterPressed", function() box:ClearFocus() end)

	UpdatePlaceholder()
end

local function SetupFilter()
	SetupSearchBox(Get("Filter"), Get("FilterPlaceholder"), function(text)
		PA.optionsFilter = text
	end)
end

-- A flat text button with a 1px frame and a hover highlight.
local function SetupPanelButton(button, text, onClick)
	local name = button:GetName()
	_G[name .. "Text"]:SetText(text)
	button:SetBackdrop({
		edgeFile = WHITE,
		edgeSize = 1,
	})
	button:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	AttachHover(button, _G[name .. "Hover"])
	button:SetScript("OnClick", onClick)
end

-- AceGUI's InlineGroup pane, which WeakAuras uses for the list and for the
-- right-hand views: the tooltip border, and a 0.1 grey fill at half alpha
-- inside it. The fill is a plain colour texture rather than the backdrop's
-- own bgFile: on Unreal Azeroth the backdrop fill (ChatFrameBackground
-- tinted with SetBackdropColor) came out about twice as light as on the
-- 1.12.1 client, while a colour texture renders the same on both.
local function SetPaneBackdrop(pane)
	pane:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 },
	})
	pane:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	local fill = pane:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(0.1, 0.1, 0.1, 0.5)
	fill:SetPoint("TOPLEFT", pane, "TOPLEFT", 3, -5)
	fill:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -3, 3)
end

local function HasPickedDisplay()
	return frame.pickedDisplay ~= nil and frame.pickedOption == nil
end

-- Whether a top-level list entry goes under "Loaded/Standby": an aura whose
-- load conditions hold or only wait on an optional one (Core/Load.lua); a
-- group that is empty or has such a child.
local function IsListedLoaded(data, env)
	if not PA:IsGroup(data) then
		return PA:CheckLoad(data, env) ~= nil
	end
	local children = data.controlledChildren
	if Compat.getn(children) == 0 then return true end
	local i
	for i = 1, Compat.getn(children) do
		local child = PA:GetData(children[i])
		if child and PA:CheckLoad(child, env) ~= nil then return true end
	end
	return false
end

-- The entries of a list section, as { id, depth } in list order: its
-- top-level auras and groups by name, each expanded group followed by its
-- children in the group's order.
local function SectionEntries(topIds)
	local collapsedGroups = PA.db.global.optionsWindow.collapsedGroups
	local entries = {}
	local i
	for i = 1, Compat.getn(topIds) do
		local id = topIds[i]
		table.insert(entries, { id = id, depth = 0 })
		local data = PA:GetData(id)
		if PA:IsGroup(data) and not collapsedGroups[id] then
			local c
			for c = 1, Compat.getn(data.controlledChildren) do
				table.insert(entries, { id = data.controlledChildren[c], depth = 1 })
			end
		end
	end
	return entries
end

-- Indents a child row's icon, name and rename box. Every anchor of a moved
-- region is set again after ClearAllPoints.
local function SetRowIndent(row, indent)
	if row.indent == indent then return end
	row.indent = indent
	local name = row:GetName()
	local icon = _G[name .. "Icon"]
	icon:ClearAllPoints()
	icon:SetPoint("LEFT", row, "LEFT", indent, 0)
	local title = _G[name .. "Title"]
	title:ClearAllPoints()
	title:SetPoint("TOPLEFT", row, "TOPLEFT", 34 + indent, -2)
	title:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
	local box = _G[name .. "Rename"]
	box:ClearAllPoints()
	box:SetPoint("LEFT", row, "LEFT", 40 + indent, 0)
	box:SetPoint("RIGHT", row, "RIGHT", -4, 0)
end

-- The look of a row while an aura is being grouped (WeakAuras'
-- StartGrouping): rows that cannot be clicked, neither the aura itself nor
-- a group, are dimmed.
local function UpdateRowGroupingLook(row)
	local name = row:GetName()
	local dimmed = frame.grouping ~= nil and row.id ~= frame.grouping and not row.isGroup
	if dimmed then
		_G[name .. "Icon"]:SetVertexColor(0.4, 0.4, 0.4, 1)
		_G[name .. "Title"]:SetTextColor(0.5, 0.5, 0.5)
	else
		_G[name .. "Icon"]:SetVertexColor(1, 1, 1, 1)
		_G[name .. "Title"]:SetTextColor(1, 0.82, 0)
	end
end

local function UpdateRowExpand(row)
	local expand = _G[row:GetName() .. "Expand"]
	if not row.isGroup then return end
	local data = PA:GetData(row.id)
	expand.hasChildren = Compat.getn(data.controlledChildren) > 0
	expand.collapsed = PA.db.global.optionsWindow.collapsedGroups[row.id] and true or false
	if not expand.hasChildren then
		expand:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Disabled")
	elseif expand.collapsed then
		expand:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	else
		expand:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	end
end

-- The aura list, like WeakAuras' SortDisplayButtons: the "Loaded/Standby"
-- header, then the "Not Loaded" header (IsListedLoaded), each with its
-- entries (SectionEntries). Load states are checked here rather than taken
-- from the last trigger evaluation, so a new or just edited aura is listed
-- where it belongs at once. Rows are laid out by hand in the scroll child.
local function UpdateList()
	local content = Get("ListScrollContent")
	content:SetWidth(LIST_CONTENT_WIDTH)

	EnsureDisplayRows()
	local env = PA:LoadEnvironment()
	local loadedIds, unloadedIds = {}, {}
	local ids = PA:GetSortedIds()
	local i
	for i = 1, Compat.getn(ids) do
		local data = PA:GetData(ids[i])
		if not data.parent then
			if IsListedLoaded(data, env) then
				table.insert(loadedIds, ids[i])
			else
				table.insert(unloadedIds, ids[i])
			end
		end
	end
	local loadedEntries = SectionEntries(loadedIds)
	local unloadedEntries = SectionEntries(unloadedIds)
	local order = {}
	for i = 1, Compat.getn(loadedEntries) do table.insert(order, loadedEntries[i].id) end
	for i = 1, Compat.getn(unloadedEntries) do table.insert(order, unloadedEntries[i].id) end

	local saved = PA.db.global.optionsWindow
	local loadedCollapsed = saved.loadedCollapsed and true or false
	local unloadedCollapsed = saved.unloadedCollapsed and true or false

	for i = 1, Compat.getn(displayRows) do
		local row = displayRows[i]
		-- A rename in progress only survives if its row still shows that aura.
		if row.renaming and row.renaming ~= order[i] then ResetRename(row) end
		row.id = nil
		row.visible = nil
	end

	-- `y` runs down the whole list; everything is placed `listState.offset`
	-- higher, so the part in view sits in the scroll frame, which clips the
	-- rest. The scroll frame itself is never scrolled (Unreal Azeroth
	-- scrolls a ScrollFrame by an extra amount for any non-zero value), and
	-- entries out of view are hidden, so they take no clicks either.
	local y = 0
	local index = 0
	local offset = listState.offset
	local function PlaceHeader(header)
		header.inView = ListInView(y, HEADER_HEIGHT)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offset - y)
		header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offset - y)
		y = y + HEADER_HEIGHT + HEADER_SPACING
	end
	local function PlaceRows(entries, collapsed)
		local n
		for n = 1, Compat.getn(entries) do
			index = index + 1
			local row = displayRows[index]
			if not row then return end
			local id = entries[n].id
			local data = PA:GetData(id)
			local name = row:GetName()
			row.id = id
			row.visible = not collapsed and ListInView(y, DISPLAY_HEIGHT)
			row.isGroup = PA:IsGroup(data)
			row.depth = entries[n].depth
			row.canUp = row.depth > 0 and PA:CanMoveInGroup(id, -1)
			row.canDown = row.depth > 0 and PA:CanMoveInGroup(id, 1)
			SetRowIndent(row, row.depth > 0 and CHILD_INDENT or 0)
			_G[name .. "Icon"]:SetTexture(PA:GetAuraIcon(data))
			_G[name .. "Title"]:SetText(id)
			UpdateRowGroupingLook(row)
			UpdateRowExpand(row)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offset - y)
			row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offset - y)
			row.UpdateHover()
			if not collapsed then
				y = y + DISPLAY_HEIGHT + HEADER_SPACING
			end
		end
	end

	if frame.grouping and groupingHint then
		groupingHint:SetText(string.format(L["Click a group to add %s, or the aura again to cancel"],
			frame.grouping))
		groupingHint.inView = ListInView(y, GROUPING_HINT_HEIGHT)
		groupingHint:ClearAllPoints()
		groupingHint:SetPoint("TOPLEFT", content, "TOPLEFT", 4, offset - y)
		groupingHint:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, offset - y)
		y = y + GROUPING_HINT_HEIGHT + HEADER_SPACING
	end
	PlaceHeader(Get("ListScrollContentLoaded"))
	PlaceRows(loadedEntries, loadedCollapsed)
	PlaceHeader(Get("ListScrollContentUnloaded"))
	PlaceRows(unloadedEntries, unloadedCollapsed)

	-- The scroll child only spans the view: the entries are placed by hand.
	content:SetHeight(LIST_VIEW_HEIGHT)
	if SyncListScroll(y) then
		UpdateList()
		return
	end

	UpdateHeader(Get("ListScrollContentLoaded"), Compat.getn(loadedEntries) > 0, loadedCollapsed)
	UpdateHeader(Get("ListScrollContentUnloaded"), Compat.getn(unloadedEntries) > 0, unloadedCollapsed)
	UpdatePartsShown()
end

-- Scrolls the list to `offset` pixels from its top (within its range).
local function ScrollListTo(offset)
	offset = tonumber(offset) or 0
	if offset > listState.maxOffset then offset = listState.maxOffset end
	if offset < 0 then offset = 0 end
	if offset == listState.offset then return end
	listState.offset = offset
	UpdateList()
end

-- Opens `id` in the right pane, like WeakAuras' PickDisplay. The previous
-- page is closed first, so the list update below renders the new one once.
-- The selected tab is kept from aura to aura while the new one has it; a
-- group and an aura have different tabs (PA:GetAuraTabs).
local function PickDisplay(id)
	if auraOptions and auraOptions:IsOpen() then auraOptions:Close() end
	frame.pickedOption = nil
	frame.pickedDisplay = id
	local tabs = PA:GetAuraTabs(PA:GetData(id))
	local keep = false
	local i
	for i = 1, Compat.getn(tabs) do
		if tabs[i].key == frame.selectedTab then keep = true end
	end
	if not keep then frame.selectedTab = tabs[1].key end
	UpdateList()
end

-- Renaming in place, like WeakAuras' display button: the name is swapped for
-- an edit box; Enter applies, Escape cancels. An empty name, or one another
-- aura already has, puts the old name back and keeps the box open.
-- `row.renaming` holds the id being renamed.
ResetRename = function(row)
	if not row.renaming then return end
	row.renaming = nil
	_G[row:GetName() .. "Rename"]:ClearFocus()
	_G[row:GetName() .. "Title"]:Show()
end

local function EndRename(row)
	ResetRename(row)
	UpdatePartsShown()
end

local function StartRename(row)
	if not row.id then return end
	local box = _G[row:GetName() .. "Rename"]
	row.renaming = row.id
	_G[row:GetName() .. "Title"]:Hide()
	box:SetText(row.id)
	UpdatePartsShown()
	box:SetFocus()
	pcall(box.HighlightText, box)
end

local function ApplyRename(row)
	local box = _G[row:GetName() .. "Rename"]
	local oldId = row.renaming
	if not oldId then return end
	local newId = box:GetText() or ""
	if newId == "" or (newId ~= oldId and PA:GetData(newId)) then
		box:SetText(oldId)
		return
	end

	EndRename(row)
	if newId ~= oldId and PA:RenameAura(oldId, newId) then
		local collapsedGroups = PA.db.global.optionsWindow.collapsedGroups
		collapsedGroups[newId] = collapsedGroups[oldId]
		collapsedGroups[oldId] = nil
		if frame.grouping == oldId then frame.grouping = newId end
		if frame.pickedDisplay == oldId then
			-- The options page is keyed by the aura's id.
			if auraOptions:IsOpen() then auraOptions:Close() end
			frame.pickedDisplay = newId
		end
		UpdateList()
	end
end

-- Deleting asks first, like WeakAuras' WEAKAURAS_CONFIRM_DELETE popup, with
-- the number of auras that go. The aura is kept here rather than in the
-- popup's `data`, so nothing depends on how a client's StaticPopup hands
-- that back. `pendingDeleteChildren` is WeakAuras' "Delete children and
-- group".
local pendingDeleteId, pendingDeleteChildren

local function DeletePendingAura()
	local id, withChildren = pendingDeleteId, pendingDeleteChildren
	pendingDeleteId, pendingDeleteChildren = nil, nil
	if not id or not PA:GetData(id) then return end
	PA:DeleteAura(id, withChildren)
	if frame.pickedDisplay and not PA:GetData(frame.pickedDisplay) then
		frame.pickedDisplay = nil
	end
	PA.db.global.optionsWindow.collapsedGroups[id] = nil
	UpdateList()
end

local function ConfirmDelete(id, withChildren)
	pendingDeleteId, pendingDeleteChildren = id, withChildren
	StaticPopup_Show("PUNYAURAS_CONFIRM_DELETE", PA:CountDeleted(id, withChildren))
end

local function RegisterDeletePopup()
	StaticPopupDialogs["PUNYAURAS_CONFIRM_DELETE"] = {
		text = L["You are about to delete %d aura(s). |cFFFF0000This cannot be undone!|r Would you like to continue?"],
		button1 = L["Delete"],
		button2 = L["Cancel"],
		OnAccept = DeletePendingAura,
		OnCancel = function() pendingDeleteId, pendingDeleteChildren = nil, nil end,
		showAlert = 1,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}
end

-- The right-click menu of a list row: the part of WeakAuras' display button
-- menu that exists so far. The native dropdown menu is used with our own
-- dropdown frame (PunyAurasOptionsDisplayMenu).
local menuRow

local function InitDisplayMenu()
	local row = menuRow
	if not (row and row.id) then return end
	UIDropDownMenu_AddButton({
		text = L["Rename"],
		notCheckable = 1,
		func = function() StartRename(row) end,
	})
	UIDropDownMenu_AddButton({
		text = L["Duplicate"],
		notCheckable = 1,
		func = function()
			local id = PA:DuplicateAura(row.id)
			if id then PickDisplay(id) end
		end,
	})
	UIDropDownMenu_AddButton({
		text = L["Export..."],
		notCheckable = 1,
		func = function() PA:OpenExport(row.id) end,
	})
	UIDropDownMenu_AddButton({
		text = L["Delete"],
		notCheckable = 1,
		func = function() ConfirmDelete(row.id) end,
	})
	if row.isGroup then
		UIDropDownMenu_AddButton({
			text = L["Delete children and group"],
			notCheckable = 1,
			func = function() ConfirmDelete(row.id, true) end,
		})
	end
	UIDropDownMenu_AddButton({
		text = " ",
		notClickable = 1,
		notCheckable = 1,
	})
	UIDropDownMenu_AddButton({
		text = L["Close"],
		notCheckable = 1,
		func = function() CloseDropDownMenus() end,
	})
end

local function ShowDisplayMenu(row)
	menuRow = row
	-- Hidden first: ToggleDropDownMenu closes a menu that is already open on
	-- this dropdown frame instead of reopening it for another row.
	HideDropDownMenu(1)
	ToggleDropDownMenu(1, nil, PunyAurasOptionsDisplayMenu, row:GetName(), 0, 0)
end

-- Grouping (WeakAuras' StartGrouping / StopGrouping): after the "group"
-- button of an aura, a click on a group's row puts the aura into it, a click
-- on the aura's own row cancels, and every other row does nothing.
local function StartGrouping(id)
	frame.grouping = id
	GameTooltip:Hide()
	UpdateList()
end

local function StopGrouping()
	if not frame.grouping then return end
	frame.grouping = nil
	GameTooltip:Hide()
	UpdateList()
end

local function ShowTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:SetPoint("LEFT", owner, "RIGHT", 0, 0)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(title)
	GameTooltip:AddLine(text, 1, 1, 1, 1)
	GameTooltip:Show()
end

local function OnRowClick(row)
	if not row.id then return end
	if frame.grouping then
		if row.id == frame.grouping then
			StopGrouping()
		elseif row.isGroup then
			local id = frame.grouping
			frame.grouping = nil
			GameTooltip:Hide()
			PA:AddToGroup(id, row.id)
			UpdateList()
		end
		return
	end
	if arg1 == "RightButton" then
		GameTooltip:Hide()
		if row.id ~= frame.pickedDisplay then PickDisplay(row.id) end
		ShowDisplayMenu(row)
	else
		PickDisplay(row.id)
	end
end

-- The row's tooltip exists only while grouping, naming what a click does.
local function ShowRowTooltip(row)
	if not (frame.grouping and row.id) then return end
	if row.id == frame.grouping then
		ShowTooltip(row, L["Cancel"], L["Do not group this display"])
	elseif row.isGroup then
		ShowTooltip(row, row.id, string.format(L["Add to group %s"], row.id))
	end
end

-- A small icon button of a row: brighter while hovered (the client's
-- highlight textures are drawn permanently on Unreal Azeroth), with
-- WeakAuras' tooltip.
local function SetupRowIconButton(button, texture, title, text, onClick)
	local icon = _G[button:GetName() .. "Icon"]
	icon:SetTexture(texture)
	icon:SetVertexColor(0.8, 0.8, 0.8, 1)
	button:SetScript("OnEnter", function()
		icon:SetVertexColor(1, 1, 1, 1)
		ShowTooltip(button, title, text)
	end)
	button:SetScript("OnLeave", function()
		icon:SetVertexColor(0.8, 0.8, 0.8, 1)
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		GameTooltip:Hide()
		onClick()
	end)
end

-- The row's group controls, from WeakAuras' display button: "group" on an
-- aura that is not a group, "ungroup" and move up / down on a group's child,
-- and the expand button on a group. None of them shows while grouping.
-- `rowShown` is whether the row itself is shown.
local function SetupRowButtons(row, rowShown)
	local name = row:GetName()
	local level = row:GetFrameLevel() + 1

	local function Controls()
		return rowShown() and not frame.grouping and row.renaming == nil
	end
	local buttons = {
		{ "Group", L["Group (verb)"], L["Put this display in a group"],
			function() StartGrouping(row.id) end,
			function() return Controls() and not row.isGroup end },
		{ "Ungroup", L["Ungroup"], L["Remove this display from its group"],
			function()
				PA:Ungroup(row.id)
				UpdateList()
			end,
			function() return Controls() and row.depth > 0 end },
		{ "Up", L["Move Up"], L["Move this display up in its group's order"],
			function()
				PA:MoveInGroup(row.id, -1)
				UpdateList()
			end,
			function() return Controls() and row.canUp end },
		{ "Down", L["Move Down"], L["Move this display down in its group's order"],
			function()
				PA:MoveInGroup(row.id, 1)
				UpdateList()
			end,
			function() return Controls() and row.canDown end },
	}
	local i
	for i = 1, Compat.getn(buttons) do
		local entry = buttons[i]
		local button = _G[name .. entry[1]]
		SetupRowIconButton(button, ROW_BUTTON_TEXTURES[entry[1]], entry[2], entry[3], entry[4])
		button:SetFrameLevel(level)
		AddPart(button, true, entry[5])
	end

	local expand = _G[name .. "Expand"]
	expand:SetScript("OnEnter", function()
		if not expand.hasChildren then
			ShowTooltip(expand, L["Disabled"], L["Expansion is disabled because this group has no children"])
		elseif expand.collapsed then
			ShowTooltip(expand, L["Expand"], L["Show this group's children"])
		else
			ShowTooltip(expand, L["Collapse"], L["Hide this group's children"])
		end
	end)
	expand:SetScript("OnLeave", function() GameTooltip:Hide() end)
	expand:SetScript("OnClick", function()
		if not (expand.hasChildren and row.id) then return end
		GameTooltip:Hide()
		local collapsedGroups = PA.db.global.optionsWindow.collapsedGroups
		collapsedGroups[row.id] = not collapsedGroups[row.id] or nil
		UpdateList()
	end)
	expand:SetFrameLevel(level)
	AddPart(expand, true, function() return rowShown() and row.isGroup and row.renaming == nil end)
end

-- WeakAuras' display button: the aura's icon and name. The picked aura keeps
-- the hover highlight, like WeakAuras' LockHighlight. Right-click opens the
-- menu and picks the aura, as there.
local function CreateDisplayRow(index)
	local ok, row = pcall(CreateFrame, "Button", FRAME_NAME .. "Display" .. index,
		Get("ListScrollContent"), "PunyAurasDisplayButtonTemplate")
	if not ok or not row then return nil end

	local name = row:GetName()
	local hover = _G[name .. "Hover"]

	row.UpdateHover = function()
		if row.hovered or (row.id and row.id == frame.pickedDisplay) then
			hover:Show()
		else
			hover:Hide()
		end
	end
	row:SetScript("OnEnter", function()
		row.hovered = true
		row.UpdateHover()
		ShowRowTooltip(row)
	end)
	row:SetScript("OnLeave", function()
		row.hovered = nil
		row.UpdateHover()
		GameTooltip:Hide()
	end)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function() OnRowClick(row) end)

	-- An addon-created EditBox needs keyboard and mouse enabled explicitly on
	-- Unreal Azeroth.
	local box = _G[name .. "Rename"]
	pcall(box.EnableKeyboard, box, true)
	pcall(box.EnableMouse, box, true)
	box:SetScript("OnEnterPressed", function() ApplyRename(row) end)
	box:SetScript("OnEscapePressed", function() EndRename(row) end)

	row:SetFrameLevel(Get("ListScrollContent"):GetFrameLevel() + 1)
	box:SetFrameLevel(row:GetFrameLevel() + 1)
	-- `row.visible` is set by UpdateList: false while the row's section is
	-- collapsed, or the list is scrolled so that the row is out of sight.
	local function RowShown()
		return row.id ~= nil and row.visible
	end
	AddPart(row, true, RowShown)
	AddPart(box, true, function() return RowShown() and row.renaming ~= nil end)
	SetupRowButtons(row, RowShown)
	table.insert(displayRows, row)
	return row
end

-- Makes sure there is a row for every aura.
EnsureDisplayRows = function()
	local count = Compat.getn(PA:GetSortedIds())
	while Compat.getn(displayRows) < count do
		if not CreateDisplayRow(Compat.getn(displayRows) + 1) then return end
	end
end

local function SetupList()
	SetPaneBackdrop(Get("List"))

	-- Laid out and filled by UpdateList; wraps onto a second line when the
	-- aura's name is long.
	groupingHint = Get("ListScrollContent"):CreateFontString(FRAME_NAME .. "GroupingHint",
		"OVERLAY", "GameFontHighlightSmall")
	groupingHint:SetHeight(GROUPING_HINT_HEIGHT)
	groupingHint:SetJustifyH("LEFT")
	AddPart(groupingHint, true, function()
		return frame.grouping ~= nil and groupingHint.inView ~= false
	end)

	-- LibConfig-1.0's scrollbar in the gutter on the list's right, shown
	-- while the list does not fit.
	local list = Get("List")
	local LC = LibStub("LibConfig-1.0")
	if LC.CreateScrollBar then
		local bar = LC:CreateScrollBar(list, {
			name = FRAME_NAME .. "ListScrollBar",
			step = DISPLAY_HEIGHT + HEADER_SPACING,
			onScroll = ScrollListTo,
		})
		bar.frame:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_INSET, -LIST_INSET)
		bar.frame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
		local function Needed() return listState.maxOffset > 0 end
		local pieces = { bar.frame, bar.upBtn, bar.downBtn, bar.track, bar.thumb }
		local i
		for i = 1, Compat.getn(pieces) do
			AddPart(pieces[i], true, Needed)
		end
		listState.scrollBar = bar
	end

	-- The mouse wheel only reaches a ScrollFrame reliably on Unreal Azeroth;
	-- this one lies over the rows just to catch it (clicks still reach the
	-- rows: it is not mouse-enabled). Two rows per notch.
	local wheel = CreateFrame("ScrollFrame", FRAME_NAME .. "ListWheel", list)
	wheel:SetAllPoints(Get("ListScroll"))
	wheel:SetFrameLevel(Get("ListScrollContent"):GetFrameLevel() + 10)
	pcall(wheel.EnableMouseWheel, wheel, true)
	wheel:SetScript("OnMouseWheel", function(a1, a2)
		local delta = arg1
		if type(a1) == "number" then delta = a1 end
		if type(a2) == "number" then delta = a2 end
		if type(delta) ~= "number" then return end
		ScrollListTo(listState.offset - delta * 2 * (DISPLAY_HEIGHT + HEADER_SPACING))
	end)
	AddPart(wheel, true)

	SetupHeader(Get("ListScrollContentLoaded"), L["Loaded/Standby"], function()
		local saved = PA.db.global.optionsWindow
		saved.loadedCollapsed = not saved.loadedCollapsed
		UpdateList()
	end, L["Expand all loaded displays"], L["Collapse all loaded displays"])
	SetupHeader(Get("ListScrollContentUnloaded"), L["Not Loaded"], function()
		local saved = PA.db.global.optionsWindow
		saved.unloadedCollapsed = not saved.unloadedCollapsed
		UpdateList()
	end, L["Expand all non-loaded displays"], L["Collapse all non-loaded displays"])
end

-- The right pane's tab strip (WeakAuras' TabGroup), drawn with the 1.12.1
-- client's own top-tab art. The selected tab uses the "active" pieces, which
-- sit 3px lower so they join the pane below, and a white label; a hovered
-- tab gets the white label too. The client's own tab hover glow is an ADD
-- blend texture, which Unreal Azeroth does not draw the way the 1.12.1
-- client does.
local function UpdateTabs()
	local key, suffix
	for key, suffix in pairs(TAB_BUTTONS) do
		local name = FRAME_NAME .. suffix
		local selected = (key == frame.selectedTab)
		for _, piece in ipairs({ "Left", "Middle", "Right" }) do
			if selected then
				_G[name .. piece .. "Active"]:Show()
				_G[name .. piece]:Hide()
			else
				_G[name .. piece .. "Active"]:Hide()
				_G[name .. piece]:Show()
			end
		end
		if selected or Get(suffix).hovered then
			_G[name .. "Text"]:SetTextColor(1, 1, 1)
		else
			_G[name .. "Text"]:SetTextColor(1, 0.82, 0)
		end
	end
end

local function SetupTab(key, text)
	local tab = Get(TAB_BUTTONS[key])
	local name = tab:GetName()
	local label = _G[name .. "Text"]
	label:SetText(text)

	local textWidth = label:GetStringWidth()
	if not textWidth or textWidth <= 0 then
		textWidth = string.len(text) * 6
	end
	-- The tab is its 16px end caps plus a middle piece as wide as the label
	-- and some padding.
	local middle = textWidth + 8
	_G[name .. "Middle"]:SetWidth(middle)
	_G[name .. "MiddleActive"]:SetWidth(middle)
	tab:SetWidth(middle + 32)

	tab:SetScript("OnEnter", function()
		tab.hovered = true
		UpdateTabs()
	end)
	tab:SetScript("OnLeave", function()
		tab.hovered = nil
		UpdateTabs()
	end)
	tab:SetScript("OnClick", function()
		if key == frame.selectedTab then return end
		frame.selectedTab = key
		UpdateTabs()
		SyncAuraOptions(true)
	end)

	-- Only the picked aura's own tabs are shown (PA:GetAuraTabs).
	AddPart(tab, true, function()
		if not HasPickedDisplay() then return false end
		local tabs = PA:GetAuraTabs(PA:GetData(frame.pickedDisplay))
		local i
		for i = 1, Compat.getn(tabs) do
			if tabs[i].key == key then return true end
		end
		return false
	end)
end

local function SetupAuraPane()
	AddPart(Get("RightPaneTabs"), true, HasPickedDisplay)
	local i
	for i = 1, Compat.getn(PA.auraTabs) do
		SetupTab(PA.auraTabs[i].key, PA.auraTabs[i].text)
	end
	for i = 1, Compat.getn(PA.groupTabs) do
		SetupTab(PA.groupTabs[i].key, PA.groupTabs[i].text)
	end

	local pane = AddPart(Get("RightPaneTabPane"), true, HasPickedDisplay)
	SetPaneBackdrop(pane)
	local host = AddPart(Get("RightPaneTabPaneHost"), true, HasPickedDisplay)

	auraOptions = LibStub("LibConfig-1.0"):Embed(host, {
		name = FRAME_NAME .. "AuraOptions",
		width = AURA_OPTIONS_WIDTH,
		labelWidth = AURA_OPTIONS_LABEL_WIDTH,
		menuParent = frame,
	})
end

-- Keeps the embedded options view in step with the window. It is only
-- rendered while its host frame is shown (on Unreal Azeroth widgets created
-- under a hidden frame do not draw), and closed whenever the window is
-- hidden or minimized (hiding a frame does not hide its children there).
-- `reopen` re-renders it for a new aura or tab.
SyncAuraOptions = function(reopen)
	if not auraOptions then return end

	local data = frame.pickedDisplay and PA:GetData(frame.pickedDisplay)
	local visible = frame:IsShown() and not frame.minimized and HasPickedDisplay() and data

	if not visible then
		if auraOptions:IsOpen() then auraOptions:Close() end
		return
	end
	if reopen or not auraOptions:IsOpen() then
		UpdateTabs()
		auraOptions:OpenTable(PA:GetAuraOptions(data,
				function()
					UpdateList()
					PA:ScheduleTriggerUpdate()
				end,
				function() SyncAuraOptions(true) end),
			"PunyAuras:" .. data.id, { frame.selectedTab })
	end
end

-- WeakAuras' "New" button: a 40px icon, the title in large yellow and a
-- one-line description under it.
local function SetupNewButton(button, title, description, icon)
	local name = button:GetName()
	_G[name .. "Icon"]:SetTexture(icon)
	_G[name .. "Title"]:SetText(title)
	_G[name .. "Description"]:SetText(description)

	local hover = _G[name .. "Hover"]
	button:SetScript("OnEnter", function()
		hover:Show()
		GameTooltip:SetOwner(button, "ANCHOR_NONE")
		GameTooltip:SetPoint("LEFT", button, "RIGHT", 0, 0)
		GameTooltip:ClearLines()
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(description, 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
end

-- The view WeakAuras shows on "New Aura": one button per region type, the
-- group and the dynamic group first as there. A new aura goes into the group that was picked, or
-- next to the grouped aura that was (`frame.newTarget`, WeakAuras'
-- GetTargetAura); a new group is always top-level, as groups do not nest.
local function SetupNewView()
	local function IsNewView()
		return frame.pickedOption == "New"
	end

	local view = AddPart(Get("RightPaneNewView"), true, IsNewView)
	SetPaneBackdrop(view)

	local group = AddPart(Get("RightPaneNewViewGroup"), true, IsNewView)
	SetupNewButton(group,
		L["Group"], L["Controls the positioning and configuration of multiple displays at the same time"],
		PA.DEFAULT_GROUP_ICON)
	group:SetScript("OnClick", function()
		GameTooltip:Hide()
		local data = PA:NewAura("group")
		if data then PickDisplay(data.id) end
	end)

	local dynamicGroup = AddPart(Get("RightPaneNewViewDynamicGroup"), true, IsNewView)
	SetupNewButton(dynamicGroup,
		L["Dynamic Group"], L["A group that dynamically controls the positioning of its children"],
		PA.DEFAULT_DYNAMIC_GROUP_ICON)
	dynamicGroup:SetScript("OnClick", function()
		GameTooltip:Hide()
		local data = PA:NewAura("dynamicgroup")
		if data then PickDisplay(data.id) end
	end)

	local icon = AddPart(Get("RightPaneNewViewIcon"), true, IsNewView)
	SetupNewButton(icon,
		L["Icon"], L["Shows a spell icon with an optional cooldown overlay"],
		"Interface\\Icons\\Spell_Holy_SealOfSalvation")
	icon:SetScript("OnClick", function()
		GameTooltip:Hide()
		local data = PA:NewAura("icon", frame.newTarget)
		if data then PickDisplay(data.id) end
	end)

	-- The button shows the default bar: the Blizzard statusbar texture in
	-- the default bar colour.
	local auraBar = AddPart(Get("RightPaneNewViewAuraBar"), true, IsNewView)
	SetupNewButton(auraBar,
		L["Progress Bar"], L["Shows a progress bar with name, timer, and icon"],
		"Interface\\TargetingFrame\\UI-StatusBar")
	Get("RightPaneNewViewAuraBarIcon"):SetVertexColor(1, 0, 0, 1)
	auraBar:SetScript("OnClick", function()
		GameTooltip:Hide()
		local data = PA:NewAura("aurabar", frame.newTarget)
		if data then PickDisplay(data.id) end
	end)

	-- The remaining types in WeakAuras' order (by name), each button showing
	-- the region's default look.
	local newTypes = {
		{ key = "Model", regionType = "model", title = L["Model"],
			description = L["Shows a 3D model from the game files"],
			icon = PA.MODEL_ICON },
		{ key = "ProgressTexture", regionType = "progresstexture", title = L["Progress Texture"],
			description = L["Shows a texture that changes based on duration"],
			icon = PA.DEFAULT_AURA_TEXTURE },
		{ key = "Text", regionType = "text", title = L["Text"],
			description = L["Shows one or more lines of text, which can include dynamic information such as progress or stacks"],
			icon = PA.TEXT_ICON },
		{ key = "Texture", regionType = "texture", title = L["Texture"],
			description = L["Shows a custom texture"],
			icon = PA.DEFAULT_AURA_TEXTURE },
	}
	local i
	for i = 1, Compat.getn(newTypes) do
		local entry = newTypes[i]
		local button = AddPart(Get("RightPaneNewView" .. entry.key), true, IsNewView)
		SetupNewButton(button, entry.title, entry.description, entry.icon)
		button:SetScript("OnClick", function()
			GameTooltip:Hide()
			local data = PA:NewAura(entry.regionType, frame.newTarget)
			if data then PickDisplay(data.id) end
		end)
	end
end

-- "New Aura" clears the pick and shows the region type buttons, like
-- WeakAuras' NewAura view; the aura that was picked is kept as the new
-- aura's target.
local function ShowNewView()
	if frame.pickedOption ~= "New" then
		frame.newTarget = frame.pickedDisplay
	end
	frame.grouping = nil
	frame.pickedOption = "New"
	frame.pickedDisplay = nil
	UpdateList()
end

-- The icon picker (WeakAuras' IconPicker view): search box, a grid of icons
-- and a preview of the chosen one. The client has no spell-id list to search
-- the way WeakAuras does, so the icons come from the player's spellbook and
-- the icon cache of auras seen before (found by name), and from the client's
-- macro icon list (found by file name). A pick is applied to the aura at
-- once, so its on-screen preview follows it; Cancel puts the icon settings
-- back.
-- The same view is WeakAuras' TexturePicker for the texture regions
-- (`picker.field` set): it offers the textures that come with the addon
-- (PA.auraTextures) and sets that field of the aura. As WeakAuras'
-- ModelPicker for the model region (`picker.modelMode`), it offers the
-- model paths of the 1.12.1 client (PA.modelPaths, Options/ModelPaths.lua)
-- in a grid of live models: a fixed pool of PlayerModel cells, each given
-- the model of the entry it shows as the grid scrolls, so only the visible
-- page is ever drawn.
local PICKER_COLS, PICKER_ROWS = 11, 13
local PICKER_CELL, PICKER_STEP = 36, 40
-- The 1.12.1 client draws the spell models about half the size Unreal
-- Azeroth does and neither SetModelScale nor SetPosition enlarges them
-- there, while a model grows with its frame: that client gets fewer,
-- larger cells.
local MODEL_COLS, MODEL_ROWS = 6, 7
local MODEL_CELL, MODEL_STEP = 64, 70
if not Compat.isUA then
	MODEL_COLS, MODEL_ROWS = 5, 6
	MODEL_CELL, MODEL_STEP = 78, 84
end
-- A model is drawn from its own origin and at its own size, and not cut to
-- its frame: halved (SetModelScale), most spell effects stay inside their
-- cell. Its position stays 0: SetPosition holds on the 1.12.1 client but
-- only for a moment on Unreal Azeroth, so any offset would draw the two
-- clients differently.
local MODEL_CELL_SCALE = 0.5

local picker = { cells = {}, modelCells = {}, icons = {}, filtered = {}, firstRow = 0,
	columns = PICKER_COLS, visibleRows = PICKER_ROWS }

local function IsIconPicker()
	return frame.pickedOption == "IconPicker"
end

local function FileName(texture)
	local name = string.gsub(texture, "^.*[\\/]", "")
	return name
end

-- Every icon on offer: the player's spells, then auras and spells seen
-- before (the icon cache), then the macro icons. A texture is listed once,
-- under the first name it came with.
local function BuildIconList()
	local icons, seen = {}, {}
	local function Add(texture, name)
		if type(texture) ~= "string" or texture == "" then return end
		local key = string.lower(texture)
		if seen[key] then return end
		seen[key] = true
		table.insert(icons, {
			texture = texture,
			name = name,
			search = string.lower(name .. " " .. texture),
		})
	end

	local i = 1
	while true do
		local ok, name = pcall(GetSpellName, i, "spell")
		if not ok or not name then break end
		local okTexture, texture = pcall(GetSpellTexture, i, "spell")
		if okTexture then Add(texture, name) end
		i = i + 1
	end

	-- Auras and spells seen before (Core/IconCache.lua), under their names.
	local cached = PA:GetCachedIcons()
	for i = 1, Compat.getn(cached) do
		Add(cached[i].icon, cached[i].name)
	end

	local okCount, count = pcall(GetNumMacroIcons)
	if okCount and tonumber(count) then
		for i = 1, count do
			local ok, texture = pcall(GetMacroIconInfo, i)
			if ok and texture then Add(texture, FileName(texture)) end
		end
	end
	return icons
end

-- The textures the texture picker offers, under their names.
local function BuildTextureList()
	local textures = {}
	local i
	for i = 1, Compat.getn(PA.auraTextures) do
		local entry = PA.auraTextures[i]
		table.insert(textures, {
			texture = PA.AURA_TEXTURE_PATH .. entry.file,
			name = entry.name,
			search = string.lower(entry.name .. " " .. entry.file),
		})
	end
	return textures
end

-- The models the model picker offers, by path.
-- Models hidden from the model picker with a right click, by lowercased
-- path, account-wide: a model the client draws empty or off its cell.
G.hiddenModels = {}

local function BuildModelList()
	local models = {}
	local hidden = PA.db.global.hiddenModels or {}
	local i
	for i = 1, Compat.getn(PA.modelPaths or {}) do
		local path = PA.modelPaths[i]
		if not hidden[string.lower(path)] then
			table.insert(models, { texture = path, name = path, search = string.lower(path) })
		end
	end
	return models
end

local function FilterIcons(text)
	text = string.lower(text or "")
	local list = {}
	local i
	for i = 1, Compat.getn(picker.icons) do
		local icon = picker.icons[i]
		if text == "" or string.find(icon.search, text, 1, true) then
			table.insert(list, icon)
		end
	end
	picker.filtered = list
	picker.firstRow = 0
end

local function MaxFirstRow()
	local rows = math.ceil(Compat.getn(picker.filtered) / picker.columns)
	return math.max(rows - picker.visibleRows, 0)
end

-- The aura's current manual icon, or a group's groupIcon, if it has one;
-- in the texture picker, the texture field's value.
local function SelectedIcon()
	local data = picker.data
	if not data then return end
	if picker.field then
		local value = data[picker.field]
		if value and value ~= "" then return value end
		return
	end
	if PA:IsGroup(data) then
		if data.groupIcon and data.groupIcon ~= "" then return data.groupIcon end
		return
	end
	if data.iconSource == 0 and data.displayIcon and data.displayIcon ~= "" then
		return data.displayIcon
	end
end

-- A cell is highlighted while hovered, and while it shows the selected icon
-- (compared in the portable form the icon is stored in).
local function UpdateCellHighlight(cell, selected)
	local entry = cell.entry
	if cell.hovered or (entry and selected
		and PA:PortableIconPath(entry.texture) == PA:PortableIconPath(selected)) then
		_G[cell:GetName() .. "Hover"]:Show()
	else
		_G[cell:GetName() .. "Hover"]:Hide()
	end
end

-- A model cell's highlight (a texture of the grid behind it) shows while it
-- is hovered, and while it shows the selected model.
local function UpdateModelHighlight(cell, selected)
	local entry = cell.entry
	if entry and (cell.hovered or (selected and string.lower(entry.texture) == string.lower(selected))) then
		cell.highlight:Show()
	else
		cell.highlight:Hide()
	end
end

-- Gives a model cell its model, set again only when it changes (and when
-- the cell is shown, see EnsureModelCells).
local function SetCellModel(cell, path)
	if path == cell.path then return end
	cell.path = path
	if path then
		pcall(cell.SetModel, cell, PA:ModelPath(path))
		pcall(cell.SetPosition, cell, 0, 0, 0)
		pcall(cell.SetModelScale, cell, MODEL_CELL_SCALE)
		pcall(cell.SetFacing, cell, 0)
	end
end

local function UpdatePicker()
	local selected = SelectedIcon()

	local i
	for i = 1, Compat.getn(picker.cells) do
		local cell = picker.cells[i]
		local entry = not picker.modelMode and picker.filtered[picker.firstRow * PICKER_COLS + i] or nil
		cell.entry = entry
		if entry then
			_G[cell:GetName() .. "Icon"]:SetTexture(entry.texture)
		end
		UpdateCellHighlight(cell, selected)
	end
	for i = 1, Compat.getn(picker.modelCells) do
		local cell = picker.modelCells[i]
		local entry = picker.modelMode and picker.filtered[picker.firstRow * MODEL_COLS + i] or nil
		cell.entry = entry
		SetCellModel(cell, entry and entry.texture)
		UpdateModelHighlight(cell, selected)
	end

	if picker.modelMode then
		Get("RightPaneIconPickerPreview"):SetTexture(PA.MODEL_ICON)
	else
		Get("RightPaneIconPickerPreview"):SetTexture(selected or PA.DEFAULT_ICON)
	end
	-- The name of the icon picked in this picker; for one that was set
	-- before, its name in the picker's list, or else its file name.
	local label = picker.selectedName
	if not label and selected then
		local key = string.lower(selected)
		local i
		for i = 1, Compat.getn(picker.icons) do
			if string.lower(picker.icons[i].texture) == key then
				label = picker.icons[i].name
				break
			end
		end
		label = label or FileName(selected)
	end
	Get("RightPaneIconPickerLabel"):SetText(label or "")

	local count = Compat.getn(picker.filtered)
	local first = math.min(picker.firstRow * picker.columns + 1, count)
	local last = math.min((picker.firstRow + picker.visibleRows) * picker.columns, count)
	Get("RightPaneIconPickerPage"):SetText(first .. "-" .. last .. " / " .. count)

	UpdatePartsShown()
end

local function ScrollPicker(rows)
	picker.firstRow = math.max(math.min(picker.firstRow + rows, MaxFirstRow()), 0)
	UpdatePicker()
end

local function PickIcon(entry)
	local data = picker.data
	if not (data and entry) then return end
	if picker.field then
		data[picker.field] = entry.texture
	elseif PA:IsGroup(data) then
		data.groupIcon = PA:PortableIconPath(entry.texture)
	else
		data.iconSource = 0
		data.displayIcon = PA:PortableIconPath(entry.texture)
	end
	picker.selectedName = entry.name
	UpdatePicker()
end

-- The grid cells, created on first use while the picker is shown.
local function EnsurePickerCells()
	if Compat.getn(picker.cells) > 0 then return end
	local grid = Get("RightPaneIconPickerGrid")
	local i
	for i = 1, PICKER_COLS * PICKER_ROWS do
		local ok, cell = pcall(CreateFrame, "Button", FRAME_NAME .. "IconCell" .. i, grid,
			"PunyAurasIconCellTemplate")
		if not ok or not cell then return end

		local col = Compat.mod(i - 1, PICKER_COLS)
		local row = math.floor((i - 1) / PICKER_COLS)
		cell:SetPoint("TOPLEFT", grid, "TOPLEFT", 8 + col * PICKER_STEP, -8 - row * PICKER_STEP)
		cell:SetWidth(PICKER_CELL)
		cell:SetHeight(PICKER_CELL)
		cell:SetFrameLevel(grid:GetFrameLevel() + 1)

		cell:SetScript("OnEnter", function()
			cell.hovered = true
			UpdateCellHighlight(cell, SelectedIcon())
			if cell.entry then
				GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
				GameTooltip:ClearLines()
				GameTooltip:AddLine(cell.entry.name)
				GameTooltip:AddLine(cell.entry.texture, 1, 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		cell:SetScript("OnLeave", function()
			cell.hovered = nil
			GameTooltip:Hide()
			UpdateCellHighlight(cell, SelectedIcon())
		end)
		cell:SetScript("OnClick", function() PickIcon(cell.entry) end)

		AddPart(cell, true, function() return IsIconPicker() and cell.entry ~= nil end)
		table.insert(picker.cells, cell)
	end
end

-- Hides a model from the picker for good (G.hiddenModels) and refills the
-- grid in place, the page and the search kept.
local function HideModel(entry)
	if not entry then return end
	local hidden = PA.db.global.hiddenModels
	if type(hidden) ~= "table" then
		hidden = {}
		PA.db.global.hiddenModels = hidden
	end
	hidden[string.lower(entry.texture)] = true
	local firstRow = picker.firstRow
	picker.icons = BuildModelList()
	FilterIcons(Get("RightPaneIconPickerSearch"):GetText())
	picker.firstRow = math.min(firstRow, MaxFirstRow())
	GameTooltip:Hide()
	UpdatePicker()
end

-- The model grid's cells, created on first use while the picker is shown:
-- each a PlayerModel taking the mouse itself (hover shows the path, a click
-- picks it), with its highlight a texture of the grid behind it. A cell
-- sets its model again when shown.
local function EnsureModelCells()
	if Compat.getn(picker.modelCells) > 0 then return end
	local grid = Get("RightPaneIconPickerGrid")
	local i
	for i = 1, MODEL_COLS * MODEL_ROWS do
		local ok, cell = pcall(CreateFrame, "PlayerModel", FRAME_NAME .. "ModelCell" .. i, grid)
		if not ok or not cell then return end
		local col = Compat.mod(i - 1, MODEL_COLS)
		local row = math.floor((i - 1) / MODEL_COLS)
		local x, y = 8 + col * MODEL_STEP, -8 - row * MODEL_STEP
		cell:SetPoint("TOPLEFT", grid, "TOPLEFT", x, y)
		cell:SetWidth(MODEL_CELL)
		cell:SetHeight(MODEL_CELL)
		cell:SetFrameLevel(grid:GetFrameLevel() + 1)
		cell:EnableMouse(true)

		cell.highlight = grid:CreateTexture(nil, "ARTWORK")
		cell.highlight:SetPoint("TOPLEFT", grid, "TOPLEFT", x - 2, y + 2)
		cell.highlight:SetWidth(MODEL_CELL + 4)
		cell.highlight:SetHeight(MODEL_CELL + 4)
		cell.highlight:SetTexture(1, 1, 1, 0.15)
		cell.highlight:Hide()

		cell:SetScript("OnShow", function()
			local path = cell.path
			cell.path = nil
			SetCellModel(cell, path)
		end)
		cell:SetScript("OnEnter", function()
			cell.hovered = true
			UpdateModelHighlight(cell, SelectedIcon())
			if cell.entry then
				GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
				GameTooltip:ClearLines()
				GameTooltip:AddLine(cell.entry.name)
				GameTooltip:AddLine(L["Right-click: hide this model from the list"], 1, 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		cell:SetScript("OnLeave", function()
			cell.hovered = nil
			GameTooltip:Hide()
			UpdateModelHighlight(cell, SelectedIcon())
		end)
		-- The button arrives in the `arg1` global on the 1.12.1 client and as
		-- the second argument on a client that passes (frame, button).
		cell:SetScript("OnMouseUp", function(a1, a2)
			local button = (type(a2) == "string" and a2) or (type(a1) == "string" and a1) or arg1
			if button == "RightButton" then
				HideModel(cell.entry)
			else
				PickIcon(cell.entry)
			end
		end)

		AddPart(cell, true, function() return IsIconPicker() and cell.entry ~= nil end)
		table.insert(picker.modelCells, cell)
	end
end

-- Shows the picker, once its list, its aura and its mode are set.
local function ShowPicker(title)
	picker.selectedName = nil
	if picker.modelMode then
		picker.columns, picker.visibleRows = MODEL_COLS, MODEL_ROWS
	else
		picker.columns, picker.visibleRows = PICKER_COLS, PICKER_ROWS
	end
	FilterIcons("")
	frame.pickerTitle = title
	frame.pickedOption = "IconPicker"
	-- Shown before the cells are created, so they are created under a shown
	-- frame.
	UpdatePartsShown()
	if picker.modelMode then EnsureModelCells() else EnsurePickerCells() end
	Get("RightPaneIconPickerSearch"):SetText("")
	UpdatePicker()
end

-- Opens the icon picker for `data` (the Display tab's "Choose" button).
function PA:OpenIconPicker(data)
	picker.data = data
	picker.field = nil
	picker.modelMode = nil
	picker.original = {
		iconSource = data.iconSource,
		displayIcon = data.displayIcon,
		groupIcon = data.groupIcon,
	}
	picker.icons = BuildIconList()
	ShowPicker(L["Icon Picker"])
end

-- Opens the texture picker for `data[field]` (a texture region's "Choose").
function PA:OpenTexturePicker(data, field)
	picker.data = data
	picker.field = field
	picker.modelMode = nil
	picker.original = { [field] = data[field] }
	picker.icons = BuildTextureList()
	ShowPicker(L["Texture Picker"])
end

-- Opens the model picker for `data.model_path` (the model region's "Choose").
function PA:OpenModelPicker(data)
	picker.data = data
	picker.field = "model_path"
	picker.modelMode = true
	picker.original = { model_path = data.model_path }
	picker.icons = BuildModelList()
	ShowPicker(L["Model Picker"])
end

local function CloseIconPicker(keep)
	local data = picker.data
	if data and not keep and picker.original then
		if picker.field then
			data[picker.field] = picker.original[picker.field]
		elseif PA:IsGroup(data) then
			data.groupIcon = picker.original.groupIcon
		else
			data.iconSource = picker.original.iconSource
			data.displayIcon = picker.original.displayIcon
		end
	end
	picker.data = nil
	picker.field = nil
	picker.modelMode = nil
	picker.original = nil
	frame.pickerTitle = nil
	Get("RightPaneIconPickerSearch"):ClearFocus()
	frame.pickedOption = nil
	UpdateList()
end

local function SetupIconPicker()
	AddPart(Get("RightPaneIconPicker"), true, IsIconPicker)

	local grid = AddPart(Get("RightPaneIconPickerGrid"), true, IsIconPicker)
	SetPaneBackdrop(grid)

	-- The mouse wheel only reaches a ScrollFrame reliably on Unreal Azeroth;
	-- this one covers the grid just to catch it (clicks still reach the
	-- icons: it is not mouse-enabled).
	local wheel = AddPart(Get("RightPaneIconPickerGridWheel"), true, IsIconPicker)
	pcall(wheel.EnableMouseWheel, wheel, true)
	wheel:SetScript("OnMouseWheel", function(a1, a2)
		local delta = arg1
		if type(a1) == "number" then delta = a1 end
		if type(a2) == "number" then delta = a2 end
		if type(delta) ~= "number" then return end
		-- A row of models is taller than a row of icons.
		ScrollPicker(-delta * (picker.modelMode and 1 or 3))
	end)

	local search = AddPart(Get("RightPaneIconPickerSearch"), true, IsIconPicker)
	SetupSearchBox(search, Get("RightPaneIconPickerSearchPlaceholder"), function(text)
		if not picker.data then return end
		FilterIcons(text)
		UpdatePicker()
	end)

	SetupPanelButton(AddPart(Get("RightPaneIconPickerPrev"), true, IsIconPicker), "<",
		function() ScrollPicker(-picker.visibleRows) end)
	SetupPanelButton(AddPart(Get("RightPaneIconPickerNext"), true, IsIconPicker), ">",
		function() ScrollPicker(picker.visibleRows) end)
	SetupPanelButton(AddPart(Get("RightPaneIconPickerOkay"), true, IsIconPicker), L["Okay"],
		function() CloseIconPicker(true) end)
	SetupPanelButton(AddPart(Get("RightPaneIconPickerCancel"), true, IsIconPicker), L["Cancel"],
		function() CloseIconPicker(false) end)
end

-- Import and export (WeakAuras' ImportExport view, with the summary its
-- Update window shows for an import): one large text box. An export fills
-- it with the aura's string and keeps it read-only, for Ctrl+A / Ctrl+C (on
-- Unreal Azeroth HighlightText selects nothing); an import reads whatever is
-- pasted (Core/Transmission.lua), says what it is or why it cannot be
-- imported, and "Import" installs it and picks it.
-- The box follows LibConfig-1.0's recipe: a multi-line EditBox inside a
-- ScrollFrame used as a clipping window, both sized to the window rather
-- than the text. On Unreal Azeroth a long text draws far outside its
-- EditBox, and a ScrollFrame is what cuts it off. The two are created the
-- first time the view is shown, as widgets created under a hidden frame do
-- not draw there.
local TRANSFER_TEXT_WIDTH = RIGHT_PANE_OFFSET - 17 - 16
local TRANSFER_TEXT_HEIGHT = (HEIGHT - 28 - 10) - 28 - 72 - 16

-- mode ("import" / "export"), the export's text, the import's pending
-- data (PA:ParseImport), and the EditBox once it exists.
local transfer = {}

local function IsTransferView()
	return frame.pickedOption == "Import" or frame.pickedOption == "Export"
end

local function HasPendingImport()
	return IsTransferView() and transfer.mode == "import" and transfer.pending ~= nil
end

-- Describes the pasted text: what an import would add, or why it cannot.
local function UpdateImportSummary(text)
	transfer.pending = nil
	local status = Get("RightPaneTransferStatus")
	if string.gsub(text, "%s+", "") == "" then
		status:SetText("")
		UpdatePartsShown()
		return
	end

	local pending, err = PA:ParseImport(text)
	if not pending then
		status:SetText("|cffff4040" .. tostring(err) .. "|r")
		UpdatePartsShown()
		return
	end
	transfer.pending = pending
	local lines = { string.format(L["Importing %s"], tostring(pending.data.id)) }
	if PA:IsGroup(pending.data) then
		table.insert(lines, string.format(L["Importing a group with %s child auras."],
			Compat.getn(pending.children)))
	else
		table.insert(lines, L["Importing a stand-alone aura."])
	end
	local match = PA:FindImportMatch(pending)
	if match then
		table.insert(lines, L["You already have this group/aura. Importing will create a duplicate."])
	end
	status:SetText(table.concat(lines, "\n"))
	Get("RightPaneTransferImportText"):SetText(match and L["Import as Copy"] or L["Import"])
	UpdatePartsShown()
end

local function OnTransferTextChanged()
	local edit = transfer.edit
	if transfer.mode == "export" then
		-- Read-only: any edit puts the export back, once (the guard stops a
		-- loop should the client ever store the text altered).
		if not transfer.restoring and edit:GetText() ~= transfer.text then
			transfer.restoring = true
			edit:SetText(transfer.text)
			transfer.restoring = nil
		end
	elseif transfer.mode == "import" then
		UpdateImportSummary(edit:GetText() or "")
	end
end

local function ResetTransfer()
	transfer.mode = nil
	transfer.text = nil
	transfer.pending = nil
	if transfer.edit then
		transfer.edit:ClearFocus()
		transfer.edit:SetText("")
	end
	Get("RightPaneTransferStatus"):SetText("")
end

local function CloseTransfer()
	ResetTransfer()
	frame.pickedOption = nil
	UpdateList()
end

-- Takes the focus away whenever the box is not on screen (hiding a frame
-- does not reliably do that on Unreal Azeroth), and forgets the view's
-- state once another view replaced it.
SyncTransfer = function()
	if not transfer.edit then return end
	if not (frame:IsShown() and not frame.minimized and IsTransferView()) then
		transfer.edit:ClearFocus()
	end
	if not IsTransferView() and transfer.mode then
		ResetTransfer()
	end
end

local function EnsureTransferBox()
	if transfer.edit then return end
	local box = Get("RightPaneTransferBox")

	local clip = CreateFrame("ScrollFrame", FRAME_NAME .. "TransferClip", box)
	clip:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
	clip:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)

	local edit = CreateFrame("EditBox", FRAME_NAME .. "TransferEdit", clip)
	edit:SetWidth(TRANSFER_TEXT_WIDTH)
	edit:SetHeight(TRANSFER_TEXT_HEIGHT)
	pcall(clip.SetScrollChild, clip, edit)
	pcall(edit.SetMultiLine, edit, true)
	pcall(edit.SetAutoFocus, edit, false)
	pcall(edit.SetJustifyH, edit, "LEFT")
	pcall(edit.SetFontObject, edit, GameFontHighlightSmall)
	-- An addon-created EditBox needs keyboard and mouse enabled explicitly on
	-- Unreal Azeroth, otherwise only pasting works.
	pcall(edit.EnableKeyboard, edit, true)
	pcall(edit.EnableMouse, edit, true)
	edit:SetScript("OnTextChanged", OnTransferTextChanged)
	edit:SetScript("OnEscapePressed", CloseTransfer)

	AddPart(clip, true, IsTransferView)
	AddPart(edit, true, IsTransferView)
	transfer.edit = edit
end

-- Shows the view for `mode`; the box is empty and nothing reacts to it
-- until the caller sets the mode.
local function ShowTransfer(option)
	ResetTransfer()
	frame.grouping = nil
	frame.pickedOption = option
	UpdatePartsShown()
	EnsureTransferBox()
end

-- WeakAuras' ImportFromString: the toolbar's "Import".
local function OpenImport()
	ShowTransfer("Import")
	Get("RightPaneTransferLabel"):SetText(L["Paste text below"])
	transfer.mode = "import"
	transfer.edit:SetFocus()
end

-- WeakAuras' ExportToString: "Export..." in a row's menu. The label is the
-- aura's id and the string's length, as there.
function PA:OpenExport(id)
	if not self:GetData(id) then return end
	local text = self:DisplayToString(id)
	ShowTransfer("Export")
	Get("RightPaneTransferLabel"):SetText(id .. " - " .. string.len(text))
	Get("RightPaneTransferStatus"):SetText(L["Press Ctrl+A, then Ctrl+C to copy the text."])
	transfer.text = text
	transfer.mode = "export"
	transfer.edit:SetText(text)
	transfer.edit:SetFocus()
	pcall(transfer.edit.HighlightText, transfer.edit)
end

local function ImportPending()
	local pending = transfer.pending
	if not pending then return end
	local id = PA:ImportPending(pending)
	ResetTransfer()
	PickDisplay(id)
end

local function SetupTransferView()
	local import = AddPart(Get("ToolbarImport"), true)
	SetupToolbarButton(import, L["Import"], "PunyAurasImport")
	import:SetScript("OnClick", OpenImport)

	AddPart(Get("RightPaneTransfer"), true, IsTransferView)
	local box = AddPart(Get("RightPaneTransferBox"), true, IsTransferView)
	SetPaneBackdrop(box)
	-- A click on the box's margin still puts the cursor in the text.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function()
		if transfer.edit then transfer.edit:SetFocus() end
	end)

	SetupPanelButton(AddPart(Get("RightPaneTransferClose"), true, IsTransferView), L["Close"],
		CloseTransfer)
	SetupPanelButton(AddPart(Get("RightPaneTransferImport"), true, HasPendingImport), L["Import"],
		ImportPending)
end

local function SetFrameLevels()
	local base = frame:GetFrameLevel()
	local levels = {
		RightPane = 1,
		RightPaneNewView = 2,
		RightPaneNewViewIcon = 3,
		RightPaneNewViewAuraBar = 3,
		RightPaneNewViewGroup = 3,
		RightPaneNewViewDynamicGroup = 3,
		RightPaneNewViewModel = 3,
		RightPaneNewViewProgressTexture = 3,
		RightPaneNewViewText = 3,
		RightPaneNewViewTexture = 3,
		RightPaneTabPane = 2,
		RightPaneTabPaneHost = 3,
		RightPaneTabs = 3,
		RightPaneTabsRegion = 4,
		RightPaneTabsTrigger = 4,
		RightPaneTabsLoad = 4,
		RightPaneTabsGroup = 4,
		RightPaneIconPicker = 2,
		RightPaneIconPickerGrid = 3,
		-- Above the cells (grid + 1), so it gets the mouse wheel.
		RightPaneIconPickerGridWheel = 6,
		RightPaneIconPickerSearch = 4,
		RightPaneIconPickerPrev = 4,
		RightPaneIconPickerNext = 4,
		RightPaneIconPickerOkay = 4,
		RightPaneIconPickerCancel = 4,
		RightPaneTransfer = 2,
		RightPaneTransferBox = 3,
		RightPaneTransferClose = 4,
		RightPaneTransferImport = 4,
		List = 1,
		ListScroll = 2,
		ListScrollContent = 3,
		ListScrollContentLoaded = 4,
		ListScrollContentLoadedExpand = 5,
		ListScrollContentUnloaded = 4,
		ListScrollContentUnloadedExpand = 5,
		Toolbar = 2,
		ToolbarNewAura = 3,
		ToolbarImport = 3,
		Filter = 2,
		TitleBar = 2,
		MinimizeButton = 10,
		CloseButton = 10,
	}
	local suffix, offset
	for suffix, offset in pairs(levels) do
		Get(suffix):SetFrameLevel(base + offset)
	end
end

function PA:InitializeOptions()
	frame = Get("")
	-- First: frames created from here on (the embedded options view, the
	-- list rows) take their level from their parent's level at creation.
	SetFrameLevels()

	SetTitle()

	local titleBar = AddPart(Get("TitleBar"))
	titleBar:SetScript("OnMouseDown", StartMove)
	titleBar:SetScript("OnMouseUp", StopMove)

	local close = AddPart(Get("CloseButton"))
	close:SetScript("OnClick", function() frame:Hide() end)

	local minimize = AddPart(Get("MinimizeButton"))
	minimize:SetScript("OnClick", function() SetMinimized(not frame.minimized) end)
	AttachHover(minimize, Get("MinimizeButtonHover"))
	Get("MinimizeButtonIcon"):SetVertexColor(0.8, 0.8, 0.8, 1)

	AddPart(Get("RightPane"), true)
	SetupNewView()
	SetupAuraPane()
	SetupIconPicker()
	SetupTransferView()

	AddPart(Get("Toolbar"), true)
	local newAura = AddPart(Get("ToolbarNewAura"), true)
	SetupToolbarButton(newAura, L["New Aura"], "PunyAurasNewAura")
	newAura:SetScript("OnClick", ShowNewView)

	AddPart(Get("Filter"), true)
	SetupFilter()

	AddPart(Get("List"), true)
	AddPart(Get("ListScroll"), true)
	AddPart(Get("ListScrollContent"), true)
	SetupList()

	frame:SetScript("OnShow", function()
		UpdateList()
	end)
	frame:SetScript("OnHide", function()
		StopMove()
		frame.grouping = nil
		-- Hiding the window does not reliably take the focus away from the
		-- filter box or a rename box on Unreal Azeroth.
		Get("Filter"):ClearFocus()
		local i
		for i = 1, Compat.getn(displayRows) do
			ResetRename(displayRows[i])
		end
		Get("RightPaneIconPickerSearch"):ClearFocus()
		if menuRow then
			CloseDropDownMenus()
			menuRow = nil
		end
		UpdatePartsShown()
	end)

	RegisterDeletePopup()
	-- An aura whose triggers changed state may show another icon in the list.
	PA.onAuraStatesChanged = function()
		if frame:IsShown() then UpdateList() end
	end
	UIDropDownMenu_Initialize(PunyAurasOptionsDisplayMenu, InitDisplayMenu, "MENU")

	table.insert(UISpecialFrames, FRAME_NAME)

	ApplyPosition()
	UpdatePartsShown()
end

-- Whether the options window is open (WeakAuras.IsOptionsOpen): actions do
-- not run meanwhile (Core/Actions.lua).
function PA:IsOptionsOpen()
	return frame ~= nil and Compat.bool(frame:IsShown())
end

function PA:ToggleOptions()
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
	end
end

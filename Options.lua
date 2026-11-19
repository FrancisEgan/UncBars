local _, ns = ...
local panel
local controls, pages, navigation = {}, {}, {}
local refreshing = false
local GOLD = {1, 0.82, 0.32}

local function Label(parent, text, x, y, width, size, muted)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetTextColor(muted and 0.65 or 0.92, muted and 0.69 or 0.89, muted and 0.73 or 0.81)
    label:SetText(text)
    return label
end

local function Surface(name, parent, width, height, r, g, b)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(r, g, b, 0.98)
    frame:SetBackdropBorderColor(0.38, 0.35, 0.28, 1)
    return frame
end

local function Button(parent, text, x, y, width, action, name)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", action)
    return button
end

local function Checkbox(parent, key, text, description, y)
    local check = CreateFrame("CheckButton", "UncBarsOption_" .. key, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    check:SetHitRectInsets(0, -466, 0, -20)
    Label(check, text, 32, -4, 442):SetTextColor(unpack(GOLD))
    Label(check, description, 32, -24, 442, 11, true)
    check:SetScript("OnClick", function(self) ns.SetOption(key, self:GetChecked() and true or false) end)
    controls[#controls + 1] = function() check:SetChecked(ns.GetSettings()[key]) end
    return check
end

local function Slider(parent, key, title, x, y, width, percent)
    local range = ns.Ranges[key]
    local label = Label(parent, title, x, y, width, 12)
    label:SetTextColor(unpack(GOLD))
    local valueText = Label(parent, "", x + width - 44, y, 44, 12)
    valueText:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", "UncBarsOption_" .. key, parent, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 34, y - 26)
    slider:SetSize(width - 68, 14)
    slider:EnableMouse(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
    slider:SetBackdropColor(0.09, 0.11, 0.13, 1)
    slider:SetBackdropBorderColor(0.38, 0.35, 0.28, 1)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(20, 24)
    slider:SetMinMaxValues(range[1], range[2])
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    Button(parent, "-", x, y - 20, 26, function() ns.SetOption(key, ns.GetSettings()[key] - 1) end)
    Button(parent, "+", x + width - 26, y - 20, 26, function() ns.SetOption(key, ns.GetSettings()[key] + 1) end)
    slider:SetScript("OnValueChanged", function(_, value)
        if not refreshing then ns.SetOption(key, math.floor(value + 0.5)) end
    end)
    controls[#controls + 1] = function()
        local value = ns.GetSettings()[key]
        slider:SetValue(value)
        valueText:SetFormattedText(percent and "%d%%" or "%d", value)
    end
end

-- Native color picker for a color saved as <prefix>Red/Green/Blue[/Alpha].
local function ColorPicker(parent, prefix, title, y, name)
    local hasOpacity = ns.Defaults[prefix .. "Alpha"] ~= nil
    Label(parent, title, 26, y, 490):SetTextColor(unpack(GOLD))
    local button = Button(parent, "Choose color", 26, y - 24, 190, function()
        local settings = ns.GetSettings()
        local r, g, b = settings[prefix .. "Red"], settings[prefix .. "Green"], settings[prefix .. "Blue"]
        local a = settings[prefix .. "Alpha"]
        local function Changed()
            local red, green, blue = ColorPickerFrame:GetColorRGB()
            ns.SetColor(prefix, red, green, blue, hasOpacity and ColorPickerFrame:GetColorAlpha() or nil)
        end
        ColorPickerFrame:Hide()
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel(panel:GetFrameLevel() + 10)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = hasOpacity, opacity = a,
            swatchFunc = Changed, opacityFunc = hasOpacity and Changed or nil,
            cancelFunc = function() ns.SetColor(prefix, r, g, b, a) end,
        })
    end, name)
    button.swatch = button:CreateTexture(nil, "OVERLAY")
    button.swatch:SetSize(20, 16)
    button.swatch:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    controls[#controls + 1] = function()
        local settings = ns.GetSettings()
        button.swatch:SetColorTexture(settings[prefix .. "Red"], settings[prefix .. "Green"],
            settings[prefix .. "Blue"], settings[prefix .. "Alpha"] or 1)
    end
    Button(parent, "Reset color", 234, y - 24, 190, function()
        local defaults = ns.Defaults
        ns.SetColor(prefix, defaults[prefix .. "Red"], defaults[prefix .. "Green"],
            defaults[prefix .. "Blue"], defaults[prefix .. "Alpha"])
    end, name .. "Reset")
end

local function ShowPage(key)
    panel.page = key
    for name, page in pairs(pages) do page:SetShown(name == key) end
    for name, button in pairs(navigation) do
        button.selected:SetShown(name == key)
        if name == key then button.label:SetTextColor(unpack(GOLD))
        else button.label:SetTextColor(0.83, 0.85, 0.86) end
    end
end

function ns.RefreshOptions()
    if not panel then return end
    refreshing = true
    for _, refresh in ipairs(controls) do refresh() end
    refreshing = false
    panel.status:SetText(ns.IsNativeUpdatePending()
        and "Saved. Default display visibility updates when combat ends."
        or "Changes are saved for this character and applied immediately.")
end

local function BuildOptions()
    panel = Surface("UncBarsOptions", UIParent, 760, 570, 0.025, 0.04, 0.055)
    panel:Hide()
    panel:SetPoint("LEFT", UIParent, "LEFT", 24, 30)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    UISpecialFrames[#UISpecialFrames + 1] = "UncBarsOptions"
    Label(panel, "UncBars", 22, -18, 250, 21):SetTextColor(unpack(GOLD))
    Label(panel, "Your resources, your way.", 23, -45, 450, 12, true)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    drag:SetSize(700, 54)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local sidebar = Surface(nil, panel, 158, 440, 0.035, 0.045, 0.05)
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -78)
    local content = Surface(nil, panel, 552, 440, 0.018, 0.023, 0.028)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 188, -78)
    for i, entry in ipairs({ {"general", "General"}, {"appearance", "Appearance"},
        {"regen", "Mana regen"}, {"druid", "Druid & combo"} }) do
        local key, title = entry[1], entry[2]
        local nav = CreateFrame("Button", "UncBarsPage_" .. key, sidebar)
        nav:SetSize(144, 34)
        nav:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 7, -12 - (i - 1) * 40)
        nav.selected = nav:CreateTexture(nil, "BACKGROUND")
        nav.selected:SetAllPoints()
        nav.selected:SetColorTexture(0.40, 0.30, 0.08, 0.45)
        local highlight = nav:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.35, 0.32, 0.20, 0.25)
        nav.label = Label(nav, title, 12, -10, 124)
        nav:SetScript("OnClick", function() ShowPage(key) end)
        navigation[key] = nav
        local page = CreateFrame("Frame", nil, content)
        page:SetAllPoints()
        pages[key] = page
        Label(page, title, 24, -20, 490, 17):SetTextColor(unpack(GOLD))
    end
    Label(sidebar, "LIVE HUD", 17, -294, 126, 10, true)
    panel.moveButton = Button(sidebar, "Move bars", 13, -316, 132, function() ns.Command(panel.unlocked and "lock" or "unlock") end,
        "UncBarsMoveButton")
    panel.previewButton = Button(sidebar, "Sample values", 13, -350, 132, function() ns.Command("test") end, "UncBarsPreviewButton")
    Label(sidebar, "Sample mode ends when combat starts.", 17, -386, 126, 10, true)

    local general = pages.general
    Checkbox(general, "enabled", "Enable UncBars", "Show your health and resources below your character.", -58)
    Checkbox(general, "hideDefault", "Replace Forever's personal resource display",
        "Hide the default display while UncBars is enabled.", -118)
    Checkbox(general, "queue", "Preview spell mana costs", "Mark mana reserved by your cast or targeting circle (such as Blizzard).", -178)
    Checkbox(general, "healQueue", "Preview incoming self-healing", "Show healing from your own cast on yourself.", -238)
    Button(general, "Center horizontally", 26, -336, 190, function() ns.Command("center") end)
    Button(general, "Reset all settings", 234, -336, 190, function() ns.Command("reset") end)
    Label(general, "Move / lock lets you drag the entire stack. Press it again to lock.", 26, -386, 494, 11, true)

    -- Two ways to show the same five-second wait. Each has its own sub-tab;
    -- turning one on turns the other off (see ns.SetOption).
    local regen = pages.regen
    local regenTabs, regenPages = {}, {}
    local function ShowRegenTab(key)
        panel.regenTab = key
        for name, page in pairs(regenPages) do page:SetShown(name == key) end
        for name, button in pairs(regenTabs) do button.selected:SetShown(name == key) end
    end
    for i, entry in ipairs({ {"timer", "Timer strip"}, {"colors", "Bar colors"} }) do
        local key, title = entry[1], entry[2]
        local tab = Button(regen, title, 24 + (i - 1) * 168, -48, 160, function() ShowRegenTab(key) end,
            "UncBarsRegenTab_" .. key)
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        tab.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        tab.selected:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, -3)
        tab.selected:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, -3)
        tab.selected:SetHeight(2)
        controls[#controls + 1] = function()
            local settings = ns.GetSettings()
            local on = (key == "timer" and settings.manaRegen) or (key == "colors" and settings.manaRegenColors)
            tab:SetText(on and ("|cffffd36a" .. title .. " (on)|r") or title)
        end
        regenTabs[key] = tab
        local page = CreateFrame("Frame", "UncBarsRegenPage_" .. key, regen)
        page:SetAllPoints()
        regenPages[key] = page
    end

    local timer = regenPages.timer
    Checkbox(timer, "manaRegen", "Show mana regen timer",
        "A strip along the mana bar counts down the five-second wait. Turns off bar colors.", -94)
    Slider(timer, "manaRegenHeight", "Height (% of bar interior)", 26, -174, 492, true)
    Label(timer, "Fills upward from the bottom. The strip stays inside the border, with a 1px minimum.",
        26, -226, 490, 11, true)
    Checkbox(timer, "manaRegenNumber", "Show numbered countdown",
        "Show seconds remaining inside the mana bar, in the indicator color.", -262)
    ColorPicker(timer, "manaRegen", "Indicator color", -328, "UncBarsRegenColor")
    Label(timer, "Use Sample values to preview changes.", 26, -398, 490, 11, true)

    local colors = regenPages.colors
    Checkbox(colors, "manaRegenColors", "Color the mana bar by regen state",
        "Recolor the mana bar itself instead of showing a strip. Turns off the timer strip.", -94)
    -- The pickers only apply while the toggle is on, so show them only then.
    local colorSection = CreateFrame("Frame", "UncBarsManaColorSection", colors)
    colorSection:SetAllPoints()
    ColorPicker(colorSection, "manaFull", "Full", -148, "UncBarsManaFullColor")
    ColorPicker(colorSection, "manaWait", "Not Full, Reduced Mana Regen (Spent mana within last five seconds)",
        -208, "UncBarsManaWaitColor")
    ColorPicker(colorSection, "manaFast", "Not Full, Full Mana Regen (Have not spent mana within last five seconds)",
        -268, "UncBarsManaFastColor")
    ColorPicker(colorSection, "manaSuper", "Supercharged Regen", -328, "UncBarsManaSuperColor")
    Label(colorSection, "Colors fade between states. Use Sample values to preview the wait color.",
        26, -398, 490, 11, true)
    controls[#controls + 1] = function() colorSection:SetShown(ns.GetSettings().manaRegenColors) end
    -- Open on whichever display is in use.
    ShowRegenTab(ns.GetSettings().manaRegenColors and "colors" or "timer")

    local appearance = pages.appearance
    Label(appearance, "Start with a look, then adjust it below.", 24, -50, 496, 11, true)
    local original = Button(appearance, "Original UncBars", 24, -76, 236, function() ns.ApplyPreset("original") end,
        "UncBarsPresetOriginal")
    local forever = Button(appearance, "Forever", 280, -76, 244, function() ns.ApplyPreset("forever") end,
        "UncBarsPresetForever")
    controls[#controls + 1] = function()
        local native = ns.GetSettings().style == "forever"
        original:SetText(native and "Original UncBars" or "|cffffd36aOriginal UncBars|r")
        forever:SetText(native and "|cffffd36aForever|r" or "Forever")
    end
    Label(appearance, "Bar text", 24, -122, 496):SetTextColor(unpack(GOLD))
    for i, entry in ipairs({ {"current", "Value"}, {"full", "Value / max"}, {"percent", "Percent"},
        {"split", "% + value"}, {"hidden", "None"} }) do
        local key, title = entry[1], entry[2]
        local button = Button(appearance, title, 24 + (i - 1) * 102, -146, 94,
            function() ns.SetOption("textMode", key) end)
        controls[#controls + 1] = function()
            button:SetText(ns.GetSettings().textMode == key and ("|cffffd36a" .. title .. "|r") or title)
        end
    end
    Slider(appearance, "width", "Bar width", 26, -196, 232)
    Slider(appearance, "gap", "Space between bars", 286, -196, 232)
    Slider(appearance, "healthHeight", "Health height", 26, -270, 232)
    Slider(appearance, "manaHeight", "Resource height", 286, -270, 232)
    Slider(appearance, "fontSize", "Text size", 26, -344, 232)
    Label(appearance, "Forever uses native bar artwork, split text, and compact spacing.", 286, -350, 232, 11, true)

    local druid = pages.druid
    Checkbox(druid, "druidEnergy", "Keep cat energy visible in every form",
        "Track cat energy alongside your current form's resource.", -58)
    Checkbox(druid, "druidMana", "Show mana while shapeshifted",
        "Keep your mana pool visible below energy or rage.", -128)
    Checkbox(druid, "comboPoints", "Show combo points below the bars",
        "Five Forever-style orbs for druids and rogues, including empty orbs.", -198)
    Slider(druid, "comboSize", "Combo orb size", 26, -280, 232)
    Slider(druid, "comboGap", "Space above combo points", 286, -280, 232)
    Label(druid, "Points follow your current target. Mana-cost previews stay on the mana bar in every form.",
        26, -366, 490, 11, true)
    panel.status = Label(panel, "", 22, -538, 714, 11, true)
    panel:SetScript("OnShow", function(self)
        self:SetScale(math.min(1, UIParent:GetWidth() / 800, UIParent:GetHeight() / 610))
        ns.RefreshOptions()
    end)
    ShowPage("general")
    ns.SetOptionsState(ns.GetDisplayState())
end

function ns.OpenOptions()
    if not panel then BuildOptions() end
    panel:Show()
    ns.RefreshOptions()
end

-- The complete custom window is also discoverable from the modern Settings UI.
function ns.RegisterSettings()
    local canvas = CreateFrame("Frame")
    Label(canvas, "UncBars", 20, -20, 500, 22):SetTextColor(unpack(GOLD))
    Label(canvas, "Customize your health, resources, druid forms, and Forever-style bars.", 20, -60, 550)
    Button(canvas, "Open UncBars options", 20, -104, 230, ns.OpenOptions)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "UncBars")
    Settings.RegisterAddOnCategory(category)
end

function ns.SetOptionsState(isUnlocked, isPreview)
    if not panel then return end
    panel.unlocked = isUnlocked
    panel.moveButton:SetText(isUnlocked and "Lock bars" or "Move bars")
    panel.previewButton:SetText(isPreview and "Exit sample mode" or "Sample values")
end

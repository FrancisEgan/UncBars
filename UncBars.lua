-- WoW: Forever. Native unit, spell-cost, absorb and healing prediction APIs.
local _, ns = ...
local L = ns.Logic
local defaults = {
    enabled = true, x = 0, y = -110, width = 260, healthHeight = 20, manaHeight = 14,
    gap = 0, fontSize = 12, textMode = "current", queue = true, healQueue = true,
    style = "original", druidEnergy = true, druidMana = true, comboPoints = true,
    comboSize = 20, comboGap = 8, hideDefault = false, manaRegen = true,
    manaRegenHeight = 7, manaRegenNumber = false,
    manaRegenRed = 1, manaRegenGreen = 0.72, manaRegenBlue = 0.22, manaRegenAlpha = 0.9,
    -- Optional regen-state colors applied to the mana fill itself.
    manaRegenColors = false,
    manaFullRed = 0.05, manaFullGreen = 0.25, manaFullBlue = 1,
    manaWaitRed = 0.05, manaWaitGreen = 0.25, manaWaitBlue = 1,
    manaFastRed = 0.38, manaFastGreen = 0.68, manaFastBlue = 1,
    manaSuperRed = 0.55, manaSuperGreen = 0.9, manaSuperBlue = 1,
}
local db, root, health, power, energy, manaBar, combo, cast
local targetSpell
local worldActive = true
local powerBars, visibleBars = {}, {}
local class, layoutKey
local initialized, unlocked, preview = false, false, false
local lastMana, lastMaximum, lastPowerType
local regenUntil, regenBypassAura, evocationChannel, superShown
-- Mana may be spent any moment until spendUntil: an instant was just sent, or a
-- cast bar just ended. Casting itself does not start the five-second rule.
local spendUntil
local SPEND_WINDOW = 0.5
local SPEND_LEAD = 0.15 -- a cast's spend is expected this close to its end
-- Regen ticks raise a mana event every two seconds while mana is below full
-- and the wait is over. This long without one, restricted mana is treated as full.
local FULL_IDLE = 2.5
local lastManaEvent, lastWaitEnd = 0, 0
local fullUnsettled = false -- set until a draw sees mana settle at full
local REGEN_DELAY = 5
local EVOCATION = 12051
local INNERVATE = 29166
local INNERVATE_DURATION = 20
-- Set when Innervate is sent at the player, so its success can start the
-- buff while combat hides auras.
local selfInnervateSent
local UpdateDisplay
local absorbCalculator
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FOREVER_BAR_ATLAS = "UI-HUD-CoolDownManager-Bar"
local MANA_TYPE = Enum.PowerType.Mana
local ENERGY_TYPE = Enum.PowerType.Energy
local nativeDisplay, nativeAlpha
local nativeUpdatePending = false

ns.Defaults = defaults
ns.Ranges = { width = {140, 600}, healthHeight = {10, 60}, manaHeight = {10, 60},
    gap = {0, 20}, fontSize = {8, 20}, comboSize = {12, 32}, comboGap = {0, 24},
    manaRegenHeight = {1, 100}, manaRegenRed = {0, 1}, manaRegenGreen = {0, 1},
    manaRegenBlue = {0, 1}, manaRegenAlpha = {0, 1} }
local MANA_COLOR = { 0.05, 0.25, 1 }
-- Slightly brighter than default full regen, so targeting stays visible even
-- before a cast spends mana and changes the bar's regen state.
local COST_COLOR = { 0.55, 0.78, 1 }
local MANA_STATES = { "Full", "Wait", "Fast", "Super" }
for _, state in ipairs(MANA_STATES) do
    for _, channel in ipairs({ "Red", "Green", "Blue" }) do ns.Ranges["mana" .. state .. channel] = {0, 1} end
end
local MANA_FADE = 0.3 -- seconds per color fade
local MANA_FULL_BLEND = 0.97 -- above this fraction, shade toward the full color
-- displayFade: what readable mana shows. notFullFade / fullFade: the two colors
-- the native curve shows for restricted mana below full and at full.
local displayFade, notFullFade, fullFade = {}, {}, {}
local fadeUntil = 0
local manaCurve, curveColors

-- Keep the client's display preference intact. Alpha changes are deferred in
-- combat; late-loaded PRD frames are picked up by ADDON_LOADED.
local function UpdateNativeDisplay()
    local replace = db.enabled and db.hideDefault
    if InCombatLockdown() then
        nativeUpdatePending = replace ~= (nativeDisplay ~= nil)
        return
    end
    nativeUpdatePending = false
    local frame = _G.PersonalResourceDisplayFrame
    if not frame then return end
    if replace then
        if not nativeDisplay then nativeDisplay, nativeAlpha = frame, frame:GetAlpha() end
        frame:SetAlpha(0)
    elseif nativeDisplay then
        nativeDisplay:SetAlpha(nativeAlpha)
        nativeDisplay, nativeAlpha = nil, nil
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff78cdddUncBars:|r " .. message)
end

-- Restricted combat values may be passed to native display methods, but must
-- never be compared or used in Lua segment calculations.
local function Readable(...)
    for index = 1, select("#", ...) do
        if issecretvalue((select(index, ...))) then return false end
    end
    return true
end

-- Returns the mana cost, plus true when restricted cost types hid whether
-- the spell costs mana at all.
local function ManaCost(spellID)
    local uncertain = false
    for _, info in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
        if not Readable(info.type) then uncertain = true
        elseif info.type == MANA_TYPE then return info.cost end
    end
    return nil, uncertain
end

-- Ground-targeted spells have no cast bar while choosing their destination.
-- Use the client's pending spell ID so ranks and cost modifiers stay accurate.
local function TargetSpell()
    if not db.queue or not worldActive or UnitIsDeadOrGhost("player")
        or not C_Spell.GetTargetSpellID or not SpellIsTargeting then return end
    local targeting = SpellIsTargeting()
    if not Readable(targeting) or not targeting then return end
    local spellID = C_Spell.GetTargetSpellID()
    if Readable(spellID) and spellID and spellID > 0 then return spellID end
end

-- Returns when the aura expires (math.huge when it has no duration), or nil
-- when it is absent. The spell lookup requires a non-secret aura, and a
-- restricted lookup may fail.
local function RegenAuraExpiry(spellID)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or not Readable(aura) or aura == nil then return end
    local expires = aura.expirationTime
    if not Readable(expires) or not expires or expires <= 0 then return math.huge end
    return expires
end

-- regenBypassAura holds the latest expiry, so the state ends on time even if
-- no aura event arrives to clear it.
local function RefreshRegenAuras()
    local innervate, evocation = RegenAuraExpiry(INNERVATE), RegenAuraExpiry(EVOCATION)
    local found = innervate and evocation and math.max(innervate, evocation) or innervate or evocation
    if found then
        regenBypassAura = found
    elseif not UnitAffectingCombat("player") then
        regenBypassAura = nil
    end
    -- In combat the lookup finds nothing even while the aura is present, so
    -- an empty result there is not trusted. A known aura runs to its expiry.
end

local function IsFullManaRegenActive()
    if evocationChannel or (regenBypassAura and GetTime() < regenBypassAura) then return true end
    local _, _, _, _, _, _, _, channelSpell = UnitChannelInfo("player")
    if Readable(channelSpell) and channelSpell == EVOCATION then return true end
    local base, casting = GetManaRegen()
    return Readable(base, casting) and base and casting and base > 0 and casting >= base
end

local function StartRegenWait()
    regenUntil = GetTime() + REGEN_DELAY
    lastWaitEnd, fullUnsettled = regenUntil, true
    RefreshRegenAuras()
end

-- Whether mana is full. Restricted mana cannot be compared, so this estimates
-- it from regen ticks: none since the wait ended means nothing to regenerate.
local function ProbablyFull(current, maximum, readable)
    if readable then
        fullUnsettled = false
        return maximum > 0 and current >= maximum
    end
    local now = GetTime()
    if regenUntil and now < regenUntil then return false end
    local full = now - math.max(lastManaEvent, lastWaitEnd) >= FULL_IDLE
    if full then fullUnsettled = false end
    return full
end

-- Never compare restricted costs; these may include free casts we cannot detect.
-- Weapon attacks can be spellbook entries but never start the five-second rule.
local WEAPON_ATTACKS = { [75] = true, [5019] = true, [6603] = true, [3018] = true, [2764] = true }
-- Spells seen with a readable mana cost. Combat can restrict costs, so this is
-- learned from the spellbook and every readable cast. Once a spell is seen
-- costing mana it stays known, so a temporary free-cast proc cannot unlearn it.
local spendsMana = {}

local function CostsMana(spellID)
    local readableID = Readable(spellID)
    if readableID and (spellID == nil or spellID == EVOCATION or WEAPON_ATTACKS[spellID]) then return false end
    local cost, uncertain = ManaCost(spellID)
    if Readable(cost) and not uncertain then
        local spends = cost ~= nil and cost > 0
        if readableID and spends then spendsMana[spellID] = true end
        return spends
    end
    -- An unverified cost (an item, a proc, or a spell never seen readable)
    -- does not start the wait. A restricted spell ID cannot be looked up, so
    -- keep the estimate; this may include free casts.
    if readableID then return spendsMana[spellID] == true end
    return true
end

-- Learn spellbook costs while they are readable. Guarded because spellbook
-- APIs differ between clients; a failure only skips the head start.
local function LearnSpellbookCosts()
    local book, enum = C_SpellBook, Enum
    if InCombatLockdown() or not (book and book.GetNumSpellBookSkillLines and enum.SpellBookSpellBank
        and enum.SpellBookItemType) then return end
    local bank, spellType = enum.SpellBookSpellBank.Player, enum.SpellBookItemType.Spell
    pcall(function()
        for line = 1, book.GetNumSpellBookSkillLines() do
            local info = book.GetSpellBookSkillLineInfo(line)
            if info and info.itemIndexOffset and info.numSpellBookItems then
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = book.GetSpellBookItemInfo(slot, bank)
                    if item and item.itemType == spellType and item.spellID then CostsMana(item.spellID) end
                end
            end
        end
    end)
end

-- SENT fires as soon as a spell is requested. Only spells without a cast time
-- spend mana right after it; others spend at the end of their cast.
local function IsInstant(spellID)
    if Readable(spellID) and spellID == nil then return false end
    local info = C_Spell.GetSpellInfo(spellID)
    return info ~= nil and Readable(info.castTime) and info.castTime == 0
end

-- Whether a friendly spell sent at targetName (SENT's target, a name) lands
-- on the player. The name is the current target's even when the spell
-- self-casts, which a friendly spell does with no target or a hostile one.
-- An Innervate on someone else must not count.
-- Forever names have two parts ("First Last"). UnitName may return them as
-- one string or as name and second part, so accept either form.
local function IsPlayerName(text)
    local name, second = UnitName("player")
    if not Readable(name, second) or not name or name == "" then return false end
    if text == name then return true end
    return second ~= nil and second ~= "" and (text == name .. " " .. second or text == name .. "-" .. second)
end

local function SentAtSelf(targetName)
    if not Readable(targetName) then return false end
    if targetName == nil or targetName == "" or IsPlayerName(targetName) then return true end
    local name, assist = UnitName("target"), UnitCanAssist("player", "target")
    return Readable(name, assist) and name == targetName and not assist
end

local function TrackManaRegen(spellID)
    -- A successful mana-costing spell estimates the five-second rule.
    if CostsMana(spellID) then StartRegenWait() end
end

local function CastSpendsMana()
    return cast ~= nil and not cast.paid and not (Readable(cast.cost) and (cast.cost == nil or cast.cost <= 0))
end

-- True only when mana is about to be spent: at the very end of a mana-costing
-- cast, or just after an instant is sent or a cast bar ends.
local function CastEnding()
    return CastSpendsMana() and cast.finish ~= nil and GetTime() >= cast.finish - SPEND_LEAD
end

local function SpendPending()
    return CastEnding() or (spendUntil ~= nil and GetTime() < spendUntil)
end

-- Same cast test the stop events use: the public cast-bar ID when both sides
-- have one, otherwise the GUID; a restricted or missing GUID matches.
local function SameCast(c, guid, barID)
    if c.barID and barID then return c.barID == barID end
    return not Readable(guid) or not guid or not c.guid or c.guid == guid
end

local function ResetPowerTracking()
    lastPowerType = UnitPowerType("player")
    lastMana = UnitPower("player", MANA_TYPE)
    lastMaximum = UnitPowerMax("player", MANA_TYPE)
end

local function ObserveMana()
    local kind = UnitPowerType("player")
    local current, maximum = UnitPower("player", MANA_TYPE), UnitPowerMax("player", MANA_TYPE)
    if Readable(current, maximum, kind, lastMana, lastMaximum, lastPowerType)
        and lastMana and kind == lastPowerType and maximum == lastMaximum
        and current < lastMana then
        -- The power update can arrive before the success event. Start the wait
        -- now so the mana color does not briefly show the after-wait state.
        if CastSpendsMana() or SpendPending() then
            spendUntil = nil
            StartRegenWait()
        end
        if cast then cast.paid = true end
    end
    lastMana, lastMaximum, lastPowerType = current, maximum, kind
end

local function RefreshCast(eventGUID, eventSpellID, eventBarID, delayed)
    local name, _, _, startTime, endTime, _, castGUID, _, spellID, barID = UnitCastingInfo("player")
    local pending = Readable(name) and name == nil
    if pending and Readable(eventSpellID) and eventSpellID == nil then
        cast = nil
        return
    end
    if Readable(spellID) and spellID == nil then spellID = eventSpellID end
    if Readable(spellID) and spellID == nil then cast = nil; return end
    if Readable(startTime, endTime) and startTime and endTime and endTime <= startTime then cast = nil; return end
    local previous = cast
    local guid
    if Readable(eventGUID) and eventGUID then guid = eventGUID
    elseif Readable(castGUID) then guid = castGUID end
    cast = { guid = guid, spellID = spellID, barID = eventBarID or barID }
    if delayed and previous then cast.paid = previous.paid end
    if Readable(endTime) and endTime then cast.finish = endTime / 1000; cast.deadline = cast.finish + 0.2 end
    if pending then
        cast.pendingUntil = previous and previous.pendingUntil or GetTime() + 0.25
    end
    cast.cost = ManaCost(spellID)
end

local function Texture(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetColorTexture(r, g, b, a or 1)
    return texture
end

local function CreateFill(parent, art)
    local fill = CreateFrame("StatusBar", nil, parent)
    fill:SetAllPoints()
    fill:SetFrameLevel(parent:GetFrameLevel() + 1)
    fill:SetStatusBarTexture(art)
    fill:SetMinMaxValues(0, 1)
    fill:EnableMouse(false)
    return fill
end

local function CreateBar(name)
    local bar = CreateFrame("Frame", name, root)
    bar:SetFrameLevel(root:GetFrameLevel() + 1)
    bar:EnableMouse(false)
    -- Keep each preset's texture on its own StatusBar. Changing the texture
    -- of a bar that previously used an atlas can leave the old sampling state.
    bar.originalFill = CreateFill(bar, BAR_TEXTURE)
    bar.foreverFill = CreateFill(bar, FOREVER_BAR_ATLAS)
    bar.background = Texture(bar, "BACKGROUND", 0.04, 0.045, 0.055, 0.92)
    bar.background:SetAllPoints()
    bar.overlay = CreateFrame("Frame", nil, bar)
    bar.overlay:SetAllPoints()
    bar.overlay:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.overlay:EnableMouse(false)
    bar.text = bar.overlay:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER")
    bar.text:SetTextColor(1, 1, 1)
    bar.leftText = bar.overlay:CreateFontString(nil, "OVERLAY")
    bar.leftText:SetPoint("LEFT", bar, "LEFT", 5, 0)
    bar.leftText:SetTextColor(1, 1, 1)
    bar.frameArt = bar:CreateTexture(nil, "BACKGROUND")
    bar.frameArt:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
    bar.frameArt:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
    bar.frameArt:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -7)
    bar.frameArt:Hide()
    return bar
end

local function StateColor(state)
    return { db["mana" .. state .. "Red"], db["mana" .. state .. "Green"], db["mana" .. state .. "Blue"] }
end

-- Returns the color shown now while fading toward target. A new target
-- starts its fade from whatever is currently displayed.
local function FadeTo(fade, target)
    local now = GetTime()
    if not fade.to then
        fade.from, fade.to, fade.start = target, target, now
    elseif fade.to[1] ~= target[1] or fade.to[2] ~= target[2] or fade.to[3] ~= target[3] then
        fade.from = { L.BlendColor(fade.from, fade.to, (now - fade.start) / MANA_FADE) }
        fade.to, fade.start = target, now
        fadeUntil = math.max(fadeUntil, now + MANA_FADE)
    end
    return L.BlendColor(fade.from, fade.to, (now - fade.start) / MANA_FADE)
end

-- Restricted mana cannot be compared in Lua. A native linear curve evaluates
-- the mana fraction instead: below MANA_FULL_BLEND it shows the (fading)
-- not-full color, then shades into the (fading) full color as mana tops off.
local function ManaCurve(r, g, b, fr, fg, fb)
    local c = curveColors
    if not c or c[1] ~= r or c[2] ~= g or c[3] ~= b or c[4] ~= fr or c[5] ~= fg or c[6] ~= fb then
        curveColors = { r, g, b, fr, fg, fb }
        local notFull = CreateColor(r, g, b)
        manaCurve:ClearPoints()
        manaCurve:AddPoint(0, notFull)
        manaCurve:AddPoint(MANA_FULL_BLEND, notFull)
        manaCurve:AddPoint(1, CreateColor(fr, fg, fb))
    end
    return manaCurve
end

-- Fades are not reset here: color, setting, and sample-mode changes fade too.
local function EnsureManaCurve()
    if not manaCurve then
        manaCurve = C_CurveUtil.CreateColorCurve()
        manaCurve:SetType(Enum.LuaCurveType.Linear)
    end
end

local function ApplyLayout()
    layoutKey = nil
    EnsureManaCurve()
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    local forever = db.style == "forever"
    for _, bar in ipairs({ health, power, energy, manaBar }) do
        local height = bar == health and db.healthHeight or db.manaHeight
        bar:SetSize(db.width, height)
        bar.text:SetFont(STANDARD_TEXT_FONT, math.min(db.fontSize, height - 2), "OUTLINE")
        bar.leftText:SetFont(STANDARD_TEXT_FONT, math.min(db.fontSize, height - 2), "OUTLINE")
        if bar.regen then
            local inset = forever and 2 or 0
            bar.regen:ClearAllPoints()
            -- Percentages use the interior so even 100% fits inside the border.
            bar.regen:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", inset, inset)
            bar.regen:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
            bar.regen:SetHeight(math.max(1, (height - inset * 2) * db.manaRegenHeight / 100))
            bar.regen:SetStatusBarColor(db.manaRegenRed, db.manaRegenGreen, db.manaRegenBlue, db.manaRegenAlpha)
            bar.regenText:SetFont(STANDARD_TEXT_FONT, math.min(10, height - 2), "OUTLINE")
            bar.regenText:SetTextColor(db.manaRegenRed, db.manaRegenGreen, db.manaRegenBlue)
            bar.regenText:ClearAllPoints()
            if db.textMode == "split" then bar.regenText:SetPoint("CENTER", bar, "CENTER")
            else bar.regenText:SetPoint("RIGHT", bar, "RIGHT", -5, 0) end
        end
        bar.text:ClearAllPoints()
        if db.textMode == "split" then bar.text:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
        else bar.text:SetPoint("CENTER") end
        bar.leftText:SetShown(db.textMode == "split")
        bar.frameArt:SetShown(forever)
        bar.background:SetShown(not forever)
        bar.foreverFill:SetShown(forever)
        bar.originalFill:SetShown(not forever)
        bar.activeFill = forever and bar.foreverFill or bar.originalFill
    end
    local healthFill = health.activeFill:GetStatusBarTexture()
    for _, prediction in ipairs({ health.nativeShield, health.nativeHeal }) do
        prediction:SetSize(db.width, db.healthHeight)
        prediction:ClearAllPoints()
        prediction:SetPoint("TOPLEFT", healthFill, "TOPRIGHT")
    end
    root.mode:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    root:EnableMouse(unlocked)
end

local function ArrangeResources(kind, token)
    local druid = class == "DRUID"
    -- In caster/travel forms keep cat energy above mana. In bear form keep
    -- the active rage bar as well. Never duplicate an active resource.
    local primary = druid and db.druidEnergy and kind == MANA_TYPE and ENERGY_TYPE or kind
    local extraEnergy = druid and db.druidEnergy and primary ~= ENERGY_TYPE
    local extraMana = druid and (db.druidMana or (db.druidEnergy and kind == MANA_TYPE)) and primary ~= MANA_TYPE
    local showCombo = db.comboPoints and (druid or class == "ROGUE")
    local key = table.concat({primary, extraEnergy and 1 or 0, extraMana and 1 or 0, showCombo and 1 or 0}, ":")
    power.kind, power.token = primary, primary == ENERGY_TYPE and "ENERGY" or token
    energy.kind, energy.token = ENERGY_TYPE, "ENERGY"
    manaBar.kind, manaBar.token = MANA_TYPE, "MANA"
    if key == layoutKey then return end
    layoutKey = key
    visibleBars = { power }
    energy:SetShown(extraEnergy)
    manaBar:SetShown(extraMana)
    combo:SetShown(showCombo)
    if extraEnergy then visibleBars[#visibleBars + 1] = energy end
    if extraMana then visibleBars[#visibleBars + 1] = manaBar end
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", root, "TOPLEFT")
    local previous, height = health, db.healthHeight
    for _, bar in ipairs(visibleBars) do
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -db.gap)
        height = height + db.gap + db.manaHeight
        previous = bar
    end
    combo:ClearAllPoints()
    combo:SetPoint("TOP", previous, "BOTTOM", 0, -db.comboGap)
    combo:SetSize(db.comboSize * 5 + 4 * 4, db.comboSize)
    for i, orb in ipairs(combo.orbs) do
        orb:SetSize(db.comboSize, db.comboSize)
        orb:ClearAllPoints()
        orb:SetPoint("LEFT", combo, "LEFT", (i - 1) * (db.comboSize + 4), 0)
    end
    if showCombo then height = height + db.comboGap + db.comboSize end
    root:SetSize(db.width, height)
end

local function CreateCost(bar)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints()
    clip:SetClipsChildren(true)
    -- Keep the clip frame itself above both fills (bar + 1). At the same level
    -- the preview and the fill tie, and the fill can draw over the preview.
    clip:SetFrameLevel(bar:GetFrameLevel() + 2)
    clip:EnableMouse(false)
    bar.cost = CreateFrame("StatusBar", nil, clip)
    bar.cost:EnableMouse(false)
    bar.cost:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.cost:SetStatusBarColor(COST_COLOR[1], COST_COLOR[2], COST_COLOR[3], 1)
    bar.cost:SetReverseFill(true)
    bar.cost:SetFrameLevel(clip:GetFrameLevel() + 1)
    bar.overlay:SetFrameLevel(bar.cost:GetFrameLevel() + 1)
    bar.cost:Hide()
end

local function CreateSegment(bar, key, r, g, b, a, er, eg, eb, ea)
    bar[key] = Texture(bar.overlay, "ARTWORK", r, g, b, a)
    bar[key]:Hide()
    bar[key .. "Edge"] = Texture(bar.overlay, "ARTWORK", er, eg, eb, ea)
    bar[key .. "Edge"]:SetWidth(1)
    bar[key .. "Edge"]:Hide()
end

local function SavePosition()
    root:StopMovingOrSizing()
    local x, y = root:GetCenter()
    local px, py = UIParent:GetCenter()
    if x and y and px and py then db.x, db.y = x - px, y - py end
end

local function CreateDisplay()
    root = CreateFrame("Frame", "UncBarsFrame", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    root.mode = root:CreateFontString(nil, "OVERLAY")
    root.mode:SetPoint("BOTTOM", root, "TOP", 0, 5)
    root.mode:SetTextColor(0.85, 0.93, 0.95)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
    root:SetScript("OnDragStop", function() SavePosition(); ApplyLayout() end)
    health, power = CreateBar("UncBarsHealth"), CreateBar("UncBarsPower")
    energy, manaBar = CreateBar("UncBarsEnergy"), CreateBar("UncBarsMana")
    powerBars = { power, energy, manaBar }
    combo = CreateFrame("Frame", "UncBarsComboPoints", root)
    combo:EnableMouse(false)
    combo.orbs = {}
    for i = 1, 5 do
        -- Integer combo counts fill each native bar all-or-nothing. This also
        -- accepts restricted counts without comparing or subtracting in Lua.
        local orb = CreateFrame("StatusBar", nil, combo)
        orb:EnableMouse(false)
        orb:SetMinMaxValues(i - 1, i)
        orb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        orb:GetStatusBarTexture():SetAtlas("uf-roguecp-icon-red")
        orb.background = orb:CreateTexture(nil, "BACKGROUND")
        orb.background:SetAtlas("uf-roguecp-bg-dis")
        orb.background:SetAllPoints()
        combo.orbs[i] = orb
    end
    CreateSegment(health, "heal", 0.69, 0.88, 0.90, 0.85, 0.85, 0.95, 1, 0.95)
    CreateSegment(health, "shield", 0.78, 0.90, 1, 0.78, 0.95, 0.98, 1, 1)
    -- Follow the actual health texture without reading restricted widths.
    -- Native clamping selects the folded bar only when HP + absorb overflows.
    local shieldClip = CreateFrame("Frame", nil, health)
    shieldClip:SetAllPoints()
    shieldClip:SetClipsChildren(true)
    -- Above the health fills (health + 1), so a folded shield is not hidden by them.
    shieldClip:SetFrameLevel(health:GetFrameLevel() + 2)
    shieldClip:EnableMouse(false)
    -- Native fill geometry displays restricted incoming heals, anchored to
    -- actual HP. The shared clip trims overhealing at the health bar's edge.
    health.nativeHeal = CreateFrame("StatusBar", nil, shieldClip)
    health.nativeHeal:EnableMouse(false)
    health.nativeHeal:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health.nativeHeal:SetStatusBarColor(0.69, 0.88, 0.90, 0.85)
    health.nativeHeal:SetFrameLevel(shieldClip:GetFrameLevel() + 1)
    health.nativeHeal:Hide()
    for _, key in ipairs({ "nativeShield", "shieldOverflow" }) do
        local bar = CreateFrame("StatusBar", nil, shieldClip)
        health[key] = bar
        bar:EnableMouse(false)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(0.78, 0.90, 1, 0.78)
        bar:SetFrameLevel(shieldClip:GetFrameLevel() + 1)
        bar:Hide()
        local edge = Texture(bar, "OVERLAY", 0.95, 0.98, 1, 1)
        health[key .. "Edge"] = edge
        edge:SetWidth(1)
        edge:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPLEFT")
        edge:SetPoint("BOTTOMLEFT", bar:GetStatusBarTexture(), "BOTTOMLEFT")
    end
    health.shieldOverflow:SetAllPoints(shieldClip)
    health.shieldOverflow:SetReverseFill(true)
    health.overlay:SetFrameLevel(health.nativeShield:GetFrameLevel() + 1)
    -- Let the native StatusBar size the cost using potentially restricted
    -- values. Its right edge follows actual mana; reverse fill reserves mana
    -- to the left. Clip the part extending below zero mana.
    for _, bar in ipairs(powerBars) do
        CreateCost(bar)
        -- A child of the text overlay would render above its font strings,
        -- regardless of draw layer. Keep the strip on a lower frame level.
        bar.regen = CreateFrame("StatusBar", nil, bar)
        bar.regen:SetFrameLevel(bar.overlay:GetFrameLevel() - 1)
        bar.regen:EnableMouse(false)
        bar.regen:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar.regen:SetMinMaxValues(0, REGEN_DELAY)
        bar.regen:Hide()
        bar.regenText = bar.overlay:CreateFontString(nil, "OVERLAY")
        bar.regenText:Hide()
    end
    ApplyLayout()
end

-- Seconds left in the five-second wait, or 0 when regen is not reduced.
local function RegenRemaining()
    local remaining = regenUntil and math.max(0, regenUntil - GetTime()) or 0
    if remaining == 0 then regenUntil = nil end
    if preview then remaining = 3.2 end
    if remaining <= 0 or UnitIsDeadOrGhost("player") then return 0 end
    -- Keep the original deadline running while an effect bypasses the wait.
    if not preview and IsFullManaRegenActive() then return 0 end
    return remaining
end

local function BarValues(bar)
    if preview then
        if bar.kind == MANA_TYPE then return 1350, 2000 end
        return 75, 100
    end
    return UnitPower("player", bar.kind), UnitPowerMax("player", bar.kind)
end

-- Regen state: supercharged while Innervate, Evocation, or a full casting regen
-- rate applies (shown at any mana level); otherwise, for mana below full,
-- reduced regen inside the wait or full regen after it.
local function RegenState(remaining)
    if remaining > 0 then return "Wait" end
    if not preview and IsFullManaRegenActive() then return "Super" end
    return "Fast"
end

local function ManaColor(current, maximum, state)
    if not db.manaRegenColors then
        -- Keep every fade aimed at the usual color, so turning bar colors on
        -- or off fades as well. The usual color needs no native curve.
        FadeTo(notFullFade, MANA_COLOR)
        FadeTo(fullFade, MANA_COLOR)
        return FadeTo(displayFade, MANA_COLOR)
    end
    local readable = Readable(current, maximum)
    local full = ProbablyFull(current, maximum, readable)
    -- Restricted mana hides the moment it is spent, and the native curve would
    -- show the after-wait color until the success event. Treat a spend that is
    -- about to happen as already in the wait, so the bar does not flash.
    -- Every change fades. A cast's end is known ahead of time, so its fade
    -- starts early enough to finish as the mana is spent. An instant spends
    -- about one round trip after it is sent, so its fade starts at the send.
    if not readable and state == "Fast"
        and ((CastSpendsMana() and cast.finish and GetTime() >= cast.finish - MANA_FADE) or SpendPending()) then
        state = "Wait"
    end
    -- Regen states are tracked by the addon, so their colors can always fade in
    -- Lua. Supercharged regen shows its color even at full mana, so it is the
    -- target for both the not-full and the full color.
    local fullColor = StateColor(state == "Super" and "Super" or "Full")
    -- At full mana the not-full color is hidden, so keep it on the full
    -- color. A spend from full then fades from the color actually shown,
    -- instead of flashing the after-wait color first.
    local notFull = (full and state == "Fast") and fullColor or StateColor(state)
    local r, g, b = FadeTo(notFullFade, notFull)
    local fr, fg, fb = FadeTo(fullFade, fullColor)
    if readable then
        local fraction = maximum > 0 and current / maximum or 1
        -- Match the native curve's shading near full, then fade to it.
        local target = { L.BlendColor(notFull, fullColor, (fraction - MANA_FULL_BLEND) / (1 - MANA_FULL_BLEND)) }
        return FadeTo(displayFade, target)
    end
    -- Lua cannot see what restricted frames displayed; resume without a fade.
    displayFade.to = nil
    return UnitPowerPercent("player", MANA_TYPE, false, ManaCurve(r, g, b, fr, fg, fb)):GetRGB()
end

local function UpdateManaRegen()
    local remaining = RegenRemaining()
    superShown = false
    local drewMana = false
    for _, bar in ipairs(powerBars) do bar.regen:Hide(); bar.regenText:Hide() end
    for _, bar in ipairs(visibleBars) do
        if bar.kind == MANA_TYPE then
            drewMana = true
            -- Recolor here too, so the fill changes when the wait expires
            -- without a power event, and fades animate with colors off too.
            local current, maximum = BarValues(bar)
            local state = RegenState(remaining)
            superShown = superShown or (db.manaRegenColors and state == "Super")
            bar.activeFill:SetStatusBarColor(ManaColor(current, maximum, state))
            -- The two displays are exclusive.
            if not db.manaRegenColors and db.manaRegen and remaining > 0 then
                bar.regen:SetValue(remaining)
                bar.regen:Show()
                if db.manaRegenNumber then
                    bar.regenText:SetFormattedText("%.1fs", math.ceil(remaining * 10) / 10)
                    bar.regenText:Show()
                end
            end
        end
    end
    -- Only regen colors use the fullness estimate; nothing else waits on it.
    if not db.manaRegenColors or not drewMana then fullUnsettled = false end
end

local function DrawManaCost(power, cost, maximum, show)
    if not show or (Readable(cost) and (cost == nil or cost <= 0)) then
        power.cost:Hide()
        return
    end
    power.cost:ClearAllPoints()
    power.cost:SetPoint("TOPRIGHT", power.activeFill:GetStatusBarTexture(), "TOPRIGHT")
    power.cost:SetSize(db.width, db.manaHeight)
    power.cost:SetMinMaxValues(0, maximum)
    power.cost:SetValue(cost)
    -- A zero native fill is already invisible, including a restricted one.
    power.cost:Show()
end

local function PaintBar(bar, current, maximum, r, g, b, percent)
    -- Native setters accept restricted values directly.
    bar.activeFill:SetMinMaxValues(0, maximum)
    bar.activeFill:SetValue(current)
    bar.activeFill:SetStatusBarColor(r, g, b)
    -- Reserve space for the optional timer beside a full current/max label.
    -- Apply this here because the active bar can become mana after a form change.
    local timerBesideFull = bar.kind == MANA_TYPE and db.manaRegen and not db.manaRegenColors
        and db.manaRegenNumber and db.textMode == "full"
    bar.text:SetWidth(timerBesideFull and db.width - 50 or 0)
    bar.text:SetJustifyH(timerBesideFull and "LEFT" or "CENTER")
    bar.text:ClearAllPoints()
    if timerBesideFull then bar.text:SetPoint("LEFT", bar, "LEFT", 5, 0)
    elseif db.textMode == "split" then bar.text:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
    else bar.text:SetPoint("CENTER") end
    if db.textMode == "split" then
        bar.leftText:SetFormattedText("%.0f%%", percent)
        if Readable(current) then bar.text:SetText(BreakUpLargeNumbers(current))
        else bar.text:SetFormattedText("%d", current) end
    elseif db.textMode == "hidden" then bar.text:SetText("")
    elseif db.textMode == "full" then bar.text:SetFormattedText("%d / %d", current, maximum)
    elseif db.textMode == "percent" then bar.text:SetFormattedText("%.0f%%", percent)
    else bar.text:SetFormattedText("%d", current) end
end

local function DrawSegment(bar, key, left, right, height, edgeAtRight)
    local texture, edge = bar[key], bar[key .. "Edge"]
    if not left or right <= left then texture:Hide(); edge:Hide(); return end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", bar.overlay, "TOPLEFT", left * db.width, 0)
    texture:SetSize(math.max(0.1, (right - left) * db.width), height)
    texture:Show()
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", bar.overlay, "TOPLEFT", edgeAtRight and math.max(0, right * db.width - 1) or left * db.width, 0)
    edge:SetHeight(height)
    edge:Show()
end

local percentCurve
local function Percent(current, maximum, isHealth, kind)
    if Readable(current, maximum) then return maximum > 0 and current / maximum * 100 or 0 end
    if isHealth then return UnitHealthPercent("player", false, percentCurve) end
    return UnitPowerPercent("player", kind, false, percentCurve)
end

UpdateDisplay = function()
    if not initialized then return end
    if ns.SetOptionsState then ns.SetOptionsState(unlocked, preview) end
    if not db.enabled and not unlocked and not preview then root:Hide(); return end
    local kind, token = UnitPowerType("player")
    if preview then kind, token = MANA_TYPE, "MANA" end
    -- Portals can briefly remove the player unit. Wait for a valid resource
    -- before arranging or painting; the next unit/world event retries.
    if kind == nil then root:Hide(); return end
    root:Show()
    root.mode:SetText(preview and "PREVIEW - /uncbars test to exit" or (unlocked and "Drag to move - /uncbars lock" or ""))
    local hp, hpMax = UnitHealth("player", false), UnitHealthMax("player")
    if preview then hp, hpMax = 1640, 2000 end
    ArrangeResources(kind, token)
    local red, green = 0, 1
    if Readable(hp, hpMax) then
        local fraction = hpMax > 0 and hp / hpMax or 0
        if fraction <= 0.3 then red, green = 0.90, 0.20
        elseif fraction <= 0.5 then red, green = 0.92, 0.63 end
    end
    PaintBar(health, hp, hpMax, red, green, 0, Percent(hp, hpMax, true))
    local dead = UnitIsDeadOrGhost("player")
    targetSpell = TargetSpell()
    local cost = 0
    if preview then cost = 300
    elseif cast and not cast.paid then cost = cast.cost
    elseif targetSpell then cost = ManaCost(targetSpell) end
    local left, right
    for _, bar in ipairs(powerBars) do bar.cost:Hide() end
    local regenState = RegenState(RegenRemaining())
    for _, bar in ipairs(visibleBars) do
        local current, maximum = BarValues(bar)
        local color = PowerBarColor[bar.token] or PowerBarColor[bar.kind] or { r = 0.8, g = 0.4, b = 0.1 }
        local r, g, b = color.r, color.g, color.b
        if bar.kind == MANA_TYPE then r, g, b = ManaColor(current, maximum, regenState) end
        PaintBar(bar, current, maximum, r, g, b, Percent(current, maximum, false, bar.kind))
        DrawManaCost(bar, cost, maximum, db.queue and bar.kind == MANA_TYPE and not dead)
    end
    UpdateManaRegen()
    if db.comboPoints and (class == "DRUID" or class == "ROGUE") then
        local points = preview and 3 or GetComboPoints("player", "target")
        if dead then points = 0 end
        for _, orb in ipairs(combo.orbs) do orb:SetValue(points) end
    end

    -- The client confirms both the recipient and healing amount. Selecting a
    -- different target during the cast cannot redirect this prediction.
    local heal = preview and 280 or (cast and UnitGetIncomingHeals("player", "player") or 0)
    left, right = nil, nil
    health.nativeHeal:Hide()
    if db.healQueue and not dead then
        if Readable(hp, hpMax, heal) then
            left, right = L.HealSegment(hp, hpMax, heal or 0)
        elseif not (Readable(heal) and (heal == nil or heal <= 0))
            and not (Readable(hpMax) and hpMax <= 0) and not (Readable(hp) and hp <= 0) then
            health.nativeHeal:SetMinMaxValues(0, hpMax)
            health.nativeHeal:SetValue(heal)
            health.nativeHeal:Show()
        end
    end
    DrawSegment(health, "heal", left, right, db.healthHeight, true)

    local absorb = preview and 240 or UnitGetTotalAbsorbs("player")
    left, right = nil, nil
    health.nativeShield:Hide()
    health.shieldOverflow:Hide()
    if not dead and Readable(hp, hpMax, absorb) then
        left, right = L.AbsorbSegment(hp, hpMax, absorb or 0)
    elseif not dead and not (Readable(absorb) and (absorb == nil or absorb <= 0))
        and not (Readable(hpMax) and hpMax <= 0) and not (Readable(hp) and hp <= 0) then
        UnitGetDetailedHealPrediction("player", nil, absorbCalculator)
        local amount, overflow = absorbCalculator:GetDamageAbsorbs()
        health.nativeShield:SetMinMaxValues(0, hpMax)
        health.nativeShield:SetValue(amount)
        health.nativeShield:SetAlphaFromBoolean(overflow, 0, 1)
        health.shieldOverflow:SetMinMaxValues(0, hpMax)
        health.shieldOverflow:SetValue(absorb)
        health.shieldOverflow:SetAlphaFromBoolean(overflow, 1, 0)
        for _, key in ipairs({ "nativeShield", "shieldOverflow" }) do
            if Readable(absorb) then health[key .. "Edge"]:Show() else health[key .. "Edge"]:Hide() end
            health[key]:Show()
        end
    end
    DrawSegment(health, "shield", left, right, db.healthHeight)
end

local function Initialize()
    if initialized then return end
    if type(UncBarsDB) ~= "table" then UncBarsDB = {} end
    db = UncBarsDB
    for key, value in pairs(defaults) do
        if type(db[key]) ~= type(value) then db[key] = value end
    end
    for key, range in pairs(ns.Ranges) do db[key] = L.Clamp(db[key], range[1], range[2]) end
    if not ({ current = true, full = true, percent = true, split = true, hidden = true })[db.textMode] then db.textMode = "current" end
    if db.style ~= "original" and db.style ~= "forever" then db.style = "original" end
    -- Earlier versions ran colors on top of the timer setting; colors won.
    if db.manaRegenColors then db.manaRegen = false end
    class = select(2, UnitClass("player"))
    percentCurve = C_CurveUtil.CreateCurve()
    percentCurve:AddPoint(0, 0)
    percentCurve:AddPoint(1, 100)
    absorbCalculator = CreateUnitHealPredictionCalculator()
    absorbCalculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals)
    CreateDisplay()
    initialized = true
    LearnSpellbookCosts()
    ResetPowerTracking()
    RefreshCast()
    UpdateDisplay()
    UpdateNativeDisplay()
    if ns.RegisterSettings then ns.RegisterSettings() end
end

local events = CreateFrame("Frame", "UncBarsEvents")
for _, name in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "ADDON_LOADED", "SPELLS_CHANGED",
    "CURRENT_SPELL_CAST_CHANGED", "CURSOR_CHANGED",
}) do events:RegisterEvent(name) end
for _, name in ipairs({
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_AURA", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
}) do events:RegisterUnitEvent(name, "player") end

events:SetScript("OnEvent", function(_, event, unit, guid, spellID, barID)
    if event == "PLAYER_LOGIN" then Initialize(); return end
    if not initialized then return end
    if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
    if event == "ADDON_LOADED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        UpdateNativeDisplay()
    end
    if event == "PLAYER_ENTERING_WORLD" then
        worldActive = true
        regenUntil, regenBypassAura, evocationChannel, spendUntil = nil, nil, nil, nil
        ResetPowerTracking()
        RefreshCast()
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_DEAD" then
        if event == "PLAYER_LEAVING_WORLD" then worldActive = false end
        targetSpell = nil
        cast, preview, regenUntil = nil, false, nil
        regenBypassAura, evocationChannel, spendUntil = nil, nil, nil
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- SENT passes (unit, target, castGUID, spellID); spellID arrives in barID.
        if CostsMana(barID) and IsInstant(barID) then spendUntil = GetTime() + SPEND_WINDOW end
        if Readable(barID) and barID == INNERVATE then selfInnervateSent = SentAtSelf(guid) end
    elseif event == "SPELLS_CHANGED" then
        LearnSpellbookCosts()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        ResetPowerTracking()
    elseif event == "PLAYER_REGEN_DISABLED" then
        preview = false
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        -- A cast-time spell spends at the end of its cast, not when it starts.
        if event == "UNIT_SPELLCAST_START" then spendUntil = nil end
        RefreshCast(guid, spellID, barID, event == "UNIT_SPELLCAST_DELAYED")
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            TrackManaRegen(spellID)
            if selfInnervateSent and Readable(spellID) and spellID == INNERVATE then
                -- Combat hides the aura, so start it from the cast. An aura
                -- lookup that can read it later replaces this estimate.
                regenBypassAura = math.max(regenBypassAura or 0, GetTime() + INNERVATE_DURATION)
                selfInnervateSent = nil
            end
        end
        -- Only a cast that reached its end can still be about to spend; a
        -- cast canceled partway through cannot.
        local unpaid = CastEnding()
        -- An instant spell usable during another cast must not clear that cast.
        if cast and SameCast(cast, guid, barID) then cast = nil end
        if event ~= "UNIT_SPELLCAST_STOP" then spendUntil = nil
        elseif unpaid and not cast then
            -- The cast bar ended, but its mana and success event may still be on the way.
            spendUntil = GetTime() + SPEND_WINDOW
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        cast = nil
        evocationChannel = event == "UNIT_SPELLCAST_CHANNEL_START" and Readable(spellID) and spellID == EVOCATION
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        -- guid holds the power token here.
        if not Readable(guid) or guid == "MANA" then lastManaEvent, fullUnsettled = GetTime(), true end
        ObserveMana()
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        ResetPowerTracking()
    elseif event == "UNIT_AURA" then
        if cast then cast.cost = ManaCost(cast.spellID) end
    end
    -- Mana colors also show supercharged regen outside the wait, so keep
    -- Innervate and Evocation auras current while they are enabled.
    if (regenUntil or db.manaRegenColors) and (event == "UNIT_AURA" or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD") then
        RefreshRegenAuras()
    end
    UpdateDisplay()
    if (event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED") and ns.RefreshOptions then
        ns.RefreshOptions()
    end
end)

-- Check the targeting cursor at 20 Hz as well: its cancel/place transition may
-- arrive after the cursor event. Otherwise idle bars still only draw on events.
local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
    -- fadeUntil stays set until a tick has drawn the end of every fade.
    -- Supercharged regen can end without an event (an aura's expiry, or a
    -- regen rate that updates after the aura event), so keep checking it.
    -- Restricted fullness is estimated from time without regen ticks, so
    -- redraw until a draw has seen it settle.
    if not initialized then return end
    elapsed = elapsed + delta
    if elapsed < 0.05 then return end
    elapsed = 0
    local targeting = TargetSpell()
    if targeting or targeting ~= targetSpell then
        UpdateDisplay()
    end
    if not cast and not regenUntil and not spendUntil and fadeUntil == 0
        and not superShown and not fullUnsettled then return end
    local now = GetTime()
    -- A spend that never arrived no longer counts as pending.
    if spendUntil and now >= spendUntil then spendUntil = nil end
    if not cast then
        UpdateManaRegen()
    else
        if cast.pendingUntil then
            if now > cast.pendingUntil then cast = nil
            else RefreshCast(cast.guid, cast.spellID, cast.barID, true) end
        elseif cast.deadline then
            if now > cast.deadline then cast = nil end
        else
            local name = UnitCastingInfo("player")
            if Readable(name) and name == nil then cast = nil end
        end
        UpdateDisplay()
    end
    if fadeUntil > 0 and now >= fadeUntil then fadeUntil = 0 end
end)

SLASH_UNCBARS1 = "/uncbars"
SLASH_UNCBARS2 = "/ub"
SlashCmdList.UNCBARS = function(message)
    if not initialized then Initialize() end
    local command, value = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "unlock" then
        unlocked = true
        Print("Unlocked. Drag the bars, then /uncbars lock.")
    elseif command == "lock" then
        if unlocked then SavePosition() end
        unlocked = false
        Print("Locked.")
    elseif command == "center" then db.x = 0; Print("Centered horizontally.")
    elseif command == "test" then
        preview = not preview and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")
        Print(preview and "Preview on (sample values). /uncbars test to exit."
            or "Preview off (available while alive and out of combat).")
    elseif command == "on" then db.enabled = true
    elseif command == "off" then db.enabled = false; preview, unlocked = false, false; root:StopMovingOrSizing()
    elseif command == "queue" then
        db.queue = not db.queue
        Print(db.queue and "Mana preview on." or "Mana preview off.")
    elseif command == "healqueue" then
        db.healQueue = not db.healQueue
        Print(db.healQueue and "Healing preview on." or "Healing preview off.")
    elseif command == "regen" then
        db.manaRegen = not db.manaRegen
        if db.manaRegen then db.manaRegenColors = false end
        Print(db.manaRegen and "Mana regen timer on (estimated five-second wait); bar colors off." or "Mana regen timer off.")
    elseif command == "" or command == "options" or command == "config" then
        ns.OpenOptions()
    elseif command == "style" then
        if value == "original" or value == "forever" then ns.ApplyPreset(value)
        else Print("Use /uncbars style original | forever.") end
    elseif command == "text" then
        if ({ current = true, full = true, percent = true, split = true, hidden = true })[value] then db.textMode = value
        else Print("Use /uncbars text current | full | percent | split | hidden.") end
    elseif command == "width" or command == "height" or command == "healthheight" or command == "manaheight" or command == "gap" then
        local number = tonumber(value)
        local low, high = 140, 600
        if command == "height" or command == "healthheight" or command == "manaheight" then low, high = 10, 60
        elseif command == "gap" then low, high = 0, 20 end
        if number and number >= low and number <= high then
            if command == "height" then db.healthHeight, db.manaHeight = number, number
            elseif command == "healthheight" then db.healthHeight = number
            elseif command == "manaheight" then db.manaHeight = number
            else db[command] = number end
        else Print(command .. " must be between " .. low .. " and " .. high .. ".") end
    elseif command == "reset" then
        for key, default in pairs(defaults) do db[key] = default end
        preview, unlocked = false, false
        root:StopMovingOrSizing()
        Print("Layout and settings reset.")
    elseif command == "status" then
        Print("Forever native spell costs, incoming self-heals and total absorbs.")
        Print("Mana regen display: " .. (db.manaRegenColors and "bar colors" or (db.manaRegen and "timer strip" or "off"))
            .. " (estimated five-second wait after mana-costing spells).")
        local function Describe(value)
            if not Readable(value) then return "restricted (native display)" end
            return value == nil and "unknown" or tostring(value)
        end
        Print("Mana preview: " .. (db.queue and "on" or "off")
            .. "; cast spell: " .. (cast and Describe(cast.spellID) or "none")
            .. "; cost: " .. (cast and Describe(cast.cost) or "none")
            .. "; " .. (cast and cast.paid and "mana already spent" or "waiting to spend") .. ".")
        if targetSpell then
            Print("Targeting spell: " .. Describe(targetSpell) .. "; cost: " .. Describe(ManaCost(targetSpell)) .. ".")
        end
    else
        Print("/uncbars options | style original/forever")
        Print("/uncbars unlock | lock | center | test | on | off | reset | status")
        Print("/uncbars width 260 | healthheight 20 | manaheight 14 | gap 0")
        Print("/uncbars height 20 (both bars) | text current/full/percent | queue | healqueue | regen")
    end
    ApplyLayout()
    UpdateDisplay()
    UpdateNativeDisplay()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.GetDisplayState() return unlocked, preview end
function ns.IsNativeUpdatePending() return nativeUpdatePending end

function ns.GetSettings() return db end

function ns.RefreshDisplay()
    ApplyLayout()
    UpdateDisplay()
    UpdateNativeDisplay()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.SetOption(key, value)
    if defaults[key] == nil or type(value) ~= type(defaults[key]) then return end
    if ns.Ranges[key] then value = L.Clamp(value, ns.Ranges[key][1], ns.Ranges[key][2]) end
    db[key] = value
    -- The timer strip and bar colors show the same wait; only one is active.
    if key == "manaRegen" and value then db.manaRegenColors = false
    elseif key == "manaRegenColors" and value then db.manaRegen = false end
    if key == "enabled" and not value then
        preview, unlocked = false, false
        root:StopMovingOrSizing()
    end
    ns.RefreshDisplay()
end

-- Saves a color stored as <prefix>Red/Green/Blue and, if it has one, <prefix>Alpha.
function ns.SetColor(prefix, r, g, b, a)
    if defaults[prefix .. "Red"] == nil then return end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    local hasAlpha = defaults[prefix .. "Alpha"] ~= nil
    if hasAlpha and type(a) ~= "number" then return end
    db[prefix .. "Red"], db[prefix .. "Green"] = L.Clamp(r, 0, 1), L.Clamp(g, 0, 1)
    db[prefix .. "Blue"] = L.Clamp(b, 0, 1)
    if hasAlpha then db[prefix .. "Alpha"] = L.Clamp(a, 0, 1) end
    ns.RefreshDisplay()
end

function ns.ApplyPreset(style)
    if style == "forever" then
        db.style, db.width, db.healthHeight, db.manaHeight = style, 200, 16, 12
        db.gap, db.fontSize, db.textMode = 4, 10, "split"
    elseif style == "original" then
        for _, key in ipairs({ "style", "width", "healthHeight", "manaHeight", "gap", "fontSize", "textMode" }) do
            db[key] = defaults[key]
        end
    else return end
    ns.RefreshDisplay()
end

function ns.Command(message) SlashCmdList.UNCBARS(message) end

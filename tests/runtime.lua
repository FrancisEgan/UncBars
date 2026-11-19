-- Simulated native Forever APIs. Visuals and client execution need an in-game check.
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function close(actual, expected, message)
    check(actual and math.abs(actual - expected) < 0.001, message)
end
local ns = {}
assert(load(LOGIC_SOURCE, "@Logic.lua"))("UncBars", ns)
local L = ns.Logic
local left, right = L.CostSegment(600, 1000, 150)
close(left, 0.45, "Cost starts at predicted remaining mana")
close(right, 0.6, "Cost ends at current mana")
left, right = L.CostSegment(80, 1000, 150)
close(left, 0, "Cost clips at zero")
check(not L.CostSegment(0, 0, 100), "Empty resource pool is safe")
local br, bg, bb = L.BlendColor({ 0, 0.2, 1 }, { 1, 0.6, 0 }, 0.25)
close(br, 0.25, "Color blend mixes red")
close(bg, 0.3, "Color blend mixes green")
close(bb, 0.75, "Color blend mixes blue")
close(L.BlendColor({ 0, 0, 0 }, { 1, 1, 1 }, 2), 1, "Color blend clamps past the end")
close(L.BlendColor({ 0.4, 0, 0 }, { 1, 1, 1 }, -1), 0.4, "Color blend clamps before the start")
check(not L.CostSegment(600, 1000, 0), "Free cast has no cost segment")
left, right = L.HealSegment(400, 1000, 150)
close(left, 0.4, "Healing starts at current health")
close(right, 0.55, "Healing ends at predicted health")
left, right = L.HealSegment(950, 1000, 150)
close(right, 1, "Healing clips overheal")
check(not L.HealSegment(0, 1000, 150), "No healing prediction when dead")
check(not L.HealSegment(1000, 1000, 150), "No healing prediction at full health")
left, right = L.AbsorbSegment(950, 1000, 200)
close(left, 0.8, "Shield overflow folds into bar")
close(right, 1, "Shield clips at maximum health")
left, right = L.AbsorbSegment(400, 1000, 150)
close(left, 0.4, "Shield starts at current health when it fits")
close(right, 0.55, "Shield extends effective health")
left, right = L.AbsorbSegment(1000, 1000, 2000)
close(left, 0, "Oversized shield caps at full bar")
close(right, 1, "Oversized shield remains inside bar")

local now, hp, hpMax, mana, manaMax, kind = 100, 800, 1000, 600, 1000, 0
local absorb, incoming, combat, dead = 0, 0, false, false
local activeCast, freeCast, secretStats = nil, false, false
local targetingSpell, secretTargetSpell = nil, false
function SpellIsTargeting() return targetingSpell ~= nil end
local secretCastMetadata, secretCost, secretAbsorb = false, false, false
local secretIncoming = false
local missingCastSpellID, castInfoPending, secretSpellID = false, false, false
local playerClass, points, energyValue = "MAGE", 0, 60
local secretPoints = false
local channelSpell, activeRegenAuras, restrictedAuras = nil, {}, false
local baseRegen, castingRegen = 20, 5
local calls, frames, methods = {}, {}, {}
local nativeAbsorbAmount, nativeAbsorbTotal, nativeOverflow = 0, 0, false
local secret = setmetatable({}, {
    __add = function() error("Secret arithmetic") end,
    __sub = function() error("Secret arithmetic") end,
    __div = function() error("Secret arithmetic") end,
    __mul = function() error("Secret arithmetic") end,
    __lt = function() error("Secret comparison") end,
    __le = function() error("Secret comparison") end,
    __tostring = function() error("Secret conversion") end,
})
function issecretvalue(value) return rawequal(value, secret) end
function methods:SetStatusBarTexture(t)
    self.texture = t
    local fill = self:GetStatusBarTexture()
    if t == "UI-HUD-CoolDownManager-Bar" then fill:SetAtlas(t)
    else fill.atlas = nil end
end
function methods:GetStatusBarTexture()
    self.fill = self.fill or setmetatable({ texCoord = {0, 1, 0, 1} }, { __index = methods })
    return self.fill
end
function methods:SetReverseFill(value) self.reverseFill = value end
function methods:SetClipsChildren(value) self.clipsChildren = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha or 1 end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetAtlas(atlas)
    self.atlas = atlas
    -- Stand in for the subregion selected by native atlas art.
    self:SetTexCoord(0.1, 0.8, 0.2, 0.4)
end
function methods:SetScale(value) self.scale = value end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetJustifyH() end
function methods:SetJustifyV() end
function methods:SetBackdrop() end
function methods:SetBackdropColor() end
function methods:SetBackdropBorderColor() end
function methods:SetOrientation() end
function methods:SetThumbTexture() self.thumb = setmetatable({}, { __index = methods }) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetValueStep() end
function methods:SetObeyStepOnDrag() end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetHitRectInsets() end
function methods:SetAlphaFromBoolean(value, ifTrue, ifFalse)
    -- Emulate the native sink resolving a secret boolean, without allowing
    -- addon code to compare it. Keep the public alpha restricted as well.
    self.alphaCondition, self.alphaIfTrue, self.alphaIfFalse = value, ifTrue, ifFalse
    local resolved = value
    if issecretvalue(value) then resolved = nativeOverflow end
    self.renderedAlpha = resolved and ifTrue or ifFalse
    self.alpha = issecretvalue(value) and secret or self.renderedAlpha
end
function methods:SetMinMaxValues(low, high) self.minimum, self.maximum = low, high end
function methods:SetValue(value)
    self.value = value
    if self.scripts and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:SetStatusBarColor(...) self.color = { ... } end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetAllPoints() end
function methods:SetPoint(...)
    self.point = { ... }
    local point, relative, relativePoint, x, y = ...
    if point == "CENTER" and type(relative) == "table" and relativePoint == "CENTER" then
        self.cx, self.cy = relative.cx + (x or 0), relative.cy + (y or 0)
    end
end
function methods:ClearAllPoints() self.point = nil end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetFont(font, size) self.font, self.fontSize = font, size end
function methods:SetTextColor() end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetText(text) self.text = text end
function methods:SetFormattedText(format, ...)
    local values = { ... }
    for _, value in ipairs(values) do
        if issecretvalue(value) then self.text = "<native restricted text>"; return end
    end
    self.text = string.format(format, ...)
end
function methods:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() self.shown = false end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetMovable() end
function methods:SetClampedToScreen() end
function methods:SetFrameStrata() end
function methods:RegisterForDrag() end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetCenter() return self.cx, self.cy end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:RegisterEvent(name) self.events[name] = true end
function methods:RegisterUnitEvent(name, unit) self.events[name] = unit end
function CreateFrame(frameType, name, parent, template)
    local templates = { BackdropTemplate = true, UICheckButtonTemplate = true,
        UIPanelButtonTemplate = true, UIPanelCloseButton = true }
    assert(not template or templates[template], "Unsupported Forever template: " .. (template or ""))
    local frame = setmetatable({
        scripts = {}, events = {}, level = 1, shown = true, frameType = frameType,
        parent = parent, cx = 900, cy = 500,
    }, { __index = methods })
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function methods:CreateTexture(name) return CreateFrame("Texture", name, self) end
function methods:CreateFontString(name) return CreateFrame("FontString", name, self) end
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UISpecialFrames = {}
unpack = table.unpack
Settings = {
    RegisterCanvasLayoutCategory = function(canvas, name)
        check(name == "UncBars", "Modern Settings category registered")
        return { GetID = function() return 1 end, canvas = canvas }
    end,
    RegisterAddOnCategory = function() end,
}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
Enum = { PowerType = { Mana = 0, Energy = 3, ComboPoints = 4 }, UnitDamageAbsorbClampMode = { MissingHealthWithoutIncomingHeals = 1 },
    LuaCurveType = { Linear = 0, Step = 1, Cosine = 2, Cubic = 3 } }
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1, GetRGB = function(self) return self.r, self.g, self.b end }
end
PowerBarColor = { RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 } }
function UnitHealth(unit, predicted)
    assert(unit == "player" and predicted == false, "Use actual, unpredicted player health")
    return secretStats and secret or hp
end
function UnitHealthMax() return secretStats and secret or hpMax end
function UnitPowerType()
    if kind == nil then return nil, nil end
    return kind, kind == 0 and "MANA" or (kind == 1 and "RAGE" or "ENERGY")
end
function UnitPower(_, powerType) return secretStats and secret or (powerType == 0 and mana or (powerType == 3 and energyValue or 60)) end
function UnitPowerMax(_, powerType) return secretStats and secret or (powerType == 0 and manaMax or 100) end
function UnitGetIncomingHeals(unit, healer)
    assert(unit == "player" and healer == "player", "Only own confirmed self-heals")
    return (secretStats or secretIncoming) and secret or incoming
end
function UnitGetTotalAbsorbs() return (secretStats or secretAbsorb) and secret or absorb end
function CreateUnitHealPredictionCalculator()
    return {
        SetDamageAbsorbClampMode = function(self, mode) self.mode = mode end,
        GetDamageAbsorbs = function(self)
            check(self.updated and self.mode == Enum.UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals,
                "Native absorb calculator refreshed with clamp independent of incoming heals")
            local total = UnitGetTotalAbsorbs()
            if issecretvalue(total) then total = absorb end
            nativeAbsorbTotal = total
            nativeAbsorbAmount = math.min(total, math.max(0, hpMax - hp))
            nativeOverflow = total > math.max(0, hpMax - hp)
            if secretStats or secretAbsorb then return secret, secret end
            return nativeAbsorbAmount, nativeOverflow
        end,
    }
end
function UnitGetDetailedHealPrediction(unit, healer, calculator)
    assert(unit == "player" and healer == nil)
    calculator.updated = true
end
function UnitAffectingCombat() return combat end
function InCombatLockdown() return combat end
function UnitClass() return playerClass, playerClass end
function GetComboPoints(unit, target)
    assert(unit == "player" and target == "target", "Forever combo points belong to the current target")
    return secretPoints and secret or points
end
function BreakUpLargeNumbers(value) return tostring(value) end
function UnitIsDeadOrGhost() return dead end
function GetTime() return now end
function GetManaRegen() return baseRegen, castingRegen end
local targetName, targetFriendly = nil, false
local playerName, playerSecondName = "Tester", nil
function UnitName(unit)
    if unit == "player" then return playerName, playerSecondName end
    if unit == "target" then return targetName end
end
function UnitCanAssist(unit, other)
    assert(unit == "player" and other == "target")
    return targetName ~= nil and targetFriendly
end
function UnitChannelInfo(unit)
    assert(unit == "player")
    return nil, nil, nil, nil, nil, nil, nil, channelSpell
end
C_UnitAuras = { GetPlayerAuraBySpellID = function(spellID)
    if restrictedAuras then error("Spell lookup requires a non-secret aura") end
    return activeRegenAuras[spellID]
end }
function UnitCastingInfo()
    if activeCast and not castInfoPending then
        return secretCastMetadata and secret or "Spell", "Spell", 1,
            secretCastMetadata and secret or 100000, secretCastMetadata and secret or activeCast.finish,
            false, secretCastMetadata and secret or activeCast.guid, false,
            not missingCastSpellID and (secretSpellID and secret or activeCast.id) or nil, activeCast.barID
    end
end
local castTimes = { [205] = 2500 }
C_Spell = { GetTargetSpellID = function()
    return secretTargetSpell and secret or targetingSpell or 0
end, GetSpellInfo = function(id)
    if issecretvalue(id) then id = activeCast.id end
    if id == 999 then return nil end
    return { castTime = castTimes[id] or 0 }
end, GetSpellPowerCost = function(id)
    calls[#calls + 1] = id
    if issecretvalue(id) then id = activeCast.id end -- The native API accepts a restricted spell ID.
    if id == 999 then return nil end
    if id == 998 then return { { type = 1, cost = 10 } } end
    return { { type = 1, cost = 10 }, { type = 0, cost = secretCost and secret or (freeCast and 0 or (id == 10 and 300 or (id == 116 and 25 or 50))) } }
end }
C_CurveUtil = { CreateCurve = function() return {
    AddPoint = function() end,
    Evaluate = function(_, value)
        assert(not issecretvalue(value), "Curve:Evaluate rejects secret arguments from addon code")
        return math.max(0, math.min(1, value))
    end,
} end, CreateColorCurve = function() return {
    points = {},
    SetType = function(self, curveType) self.curveType = curveType end,
    AddPoint = function(self, x, color) self.points[#self.points + 1] = { x = x, color = color } end,
    ClearPoints = function(self) self.points = {} end,
} end }
function UnitHealthPercent() return secret end
-- A color curve resolves natively from hidden mana. The addon only receives
-- restricted channels; nativeManaColor records what the client would render.
local nativeManaColor
function UnitPowerPercent(_, powerType, _, curve)
    if not (curve and curve.points) then return secret end
    assert(curve.curveType == Enum.LuaCurveType.Linear, "Mana colors shade linearly near full")
    assert(powerType == 0, "Mana colors evaluate the mana pool")
    local x, points = mana / manaMax, curve.points
    local color = points[#points].color
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if x <= b.x then
            local t = b.x > a.x and math.max(0, (x - a.x) / (b.x - a.x)) or 1
            color = {}
            for _, channel in ipairs({ "r", "g", "b", "a" }) do
                color[channel] = a.color[channel] + (b.color[channel] - a.color[channel]) * t
            end
            break
        end
    end
    nativeManaColor = color
    return { GetRGB = function() return secret, secret, secret end }
end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
UncBarsDB = { x = 40, y = -160 }
assert(load(ADDON_SOURCE, "@UncBars.lua"))("UncBars", ns)
assert(load(OPTIONS_SOURCE, "@Options.lua"))("UncBars", ns)
local function event(name, ...)
    UncBarsEvents.scripts.OnEvent(UncBarsEvents, name, ...)
end
local function update(delta)
    now = now + delta
    UncBarsEvents.scripts.OnUpdate(UncBarsEvents, delta)
end
local function start(id, guid)
    activeCast = { id = id, guid = guid or "cast1", finish = now * 1000 + 2500 }
    event("UNIT_SPELLCAST_START", "player", activeCast.guid, id)
end
local function stop(name)
    local prior = activeCast
    activeCast = nil
    event(name or "UNIT_SPELLCAST_STOP", "player", prior and prior.guid)
end
-- StatusBar performs these calculations natively. The addon must pass values
-- and anchor to the actual power fill rather than calculating secret widths.
local function costSpan()
    local bar = UncBarsPower.cost
    assert(bar.reverseFill and bar.point[1] == "TOPRIGHT" and bar.point[2] == UncBarsPower.activeFill:GetStatusBarTexture())
    local actual = UncBarsPower.activeFill.value
    local total = UncBarsPower.activeFill.maximum
    local amount = bar.value
    local edge = actual / total * bar.width
    local width = math.min(amount / total * bar.width, edge)
    return width, edge - width
end
local function healSpan()
    local bar = UncBarsHealth.nativeHeal
    assert(bar.parent.clipsChildren and bar.point[1] == "TOPLEFT"
        and bar.point[2] == UncBarsHealth.activeFill:GetStatusBarTexture() and bar.point[3] == "TOPRIGHT",
        "Native healing follows actual HP and clips at maximum health")
    local current = issecretvalue(UncBarsHealth.activeFill.value) and hp or UncBarsHealth.activeFill.value
    local maximum = issecretvalue(bar.maximum) and hpMax or bar.maximum
    local amount = issecretvalue(bar.value) and incoming or bar.value
    return math.min(math.max(0, maximum - current), amount) / maximum * bar.width,
        current / maximum * UncBarsDB.width
end
-- Resolve rendered geometry as the native frames would, using hidden test
-- values only here. The addon sees the secret sentinels above.
local function shieldSpan()
    local forward, folded = UncBarsHealth.nativeShield, UncBarsHealth.shieldOverflow
    assert(forward.point[1] == "TOPLEFT" and forward.point[2] == UncBarsHealth.activeFill:GetStatusBarTexture()
        and forward.point[3] == "TOPRIGHT" and not forward.reverseFill,
        "Forward shield must follow actual HP texture")
    assert(forward.parent.clipsChildren and folded.reverseFill, "Native shields clip and fold inside HP bar")
    if folded.shown and folded.renderedAlpha == 1 then
        return math.max(0, 1 - nativeAbsorbTotal / hpMax) * UncBarsDB.width, UncBarsDB.width
    end
    if forward.shown and forward.renderedAlpha == 1 then
        local amount = issecretvalue(forward.value) and nativeAbsorbAmount or forward.value
        return hp / hpMax * UncBarsDB.width, math.min(1, (hp + amount) / hpMax) * UncBarsDB.width
    end
end
secretStats = true
event("PLAYER_LOGIN")
check(UncBarsHealth.nativeShield.shown and rawequal(UncBarsHealth.nativeShield.value, secret), "Login with restricted stats displays shield without curve evaluation")
check(not UncBarsHealth.nativeShieldEdge.shown, "Restricted zero or positive shield never leaves a fixed-width edge")
secretStats = false
event("PLAYER_ENTERING_WORLD")
check(UncBarsFrame.shown and not UncBarsFrame.mouse, "Visible and click-through on login")
check(UncBarsHealth.activeFill.texture == "Interface\\TargetingFrame\\UI-StatusBar", "Original shaded status-bar art")
check(UncBarsHealth.height == 20 and UncBarsPower.height == 14, "Original compact heights")
check(UncBarsDB.x == 40 and UncBarsDB.y == -160, "Saved position preserved")
close(UncBarsHealth.activeFill.value, 800, "Actual health displayed")
close(UncBarsHealth.activeFill.maximum, 1000, "Actual health maximum")
check(UncBarsPower.text.text == "600", "Current mana text")
check(UncBarsEvents.events.UNIT_POWER_FREQUENT == "player", "Native unit-filtered power events")
check(UncBarsEvents.events.UNIT_SPELLCAST_SENT == "player", "Sent spells are watched for the player only")
check(not UncBarsEvents.events.SPELLCAST_START and not UncBarsEvents.events.AUTO_ATTACK_OTHER, "No Vanilla or Nampower events")

start(116)
kind = nil
event("PLAYER_LEAVING_WORLD")
activeCast = nil
check(not UncBarsFrame.shown, "Portal hides the HUD while player power type is unavailable")
for _, name in ipairs({ "UNIT_HEALTH", "UNIT_DISPLAYPOWER", "UNIT_POWER_FREQUENT", "PLAYER_ENTERING_WORLD" }) do
    event(name, "player")
    check(not UncBarsFrame.shown, "Transition events tolerate missing player power type: " .. name)
end
kind, mana = 0, 575
event("UNIT_POWER_UPDATE", "player", "MANA")
check(UncBarsFrame.shown and UncBarsPower.kind == 0 and UncBarsPower.token == "MANA",
    "HUD resumes with the correct resource when player power data returns")
check(UncBarsPower.text.text == "575" and not UncBarsPower.cost.shown,
    "Portal recovery refreshes mana and clears the departed cast prediction")
check(UncBarsDB.x == 40 and UncBarsDB.y == -160, "Portal preserves the saved position")
mana = 600
event("PLAYER_ENTERING_WORLD")

absorb = 200
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
close(UncBarsHealth.shield.width, 52, "Native shield total appears")
absorb = 125
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
close(UncBarsHealth.shield.width, 32.5, "Native remaining shield spends down")
absorb = 0
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check(not UncBarsHealth.shield.shown, "Expired shield clears")
hp, absorb = 1000, 200
event("UNIT_AURA", "player")
close(UncBarsHealth.shield.width, 52, "Instant ward appears at full HP without an active cast")
close(UncBarsHealth.shield.point[4], 208, "Ward folds inside full health bar")
absorb = 350
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
close(UncBarsHealth.shield.width, 91, "Ward and another shield use one native total without double counting")
secretAbsorb = true
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check(UncBarsHealth.nativeShield.shown and not UncBarsHealth.shield.shown, "Restricted ward switches to native display")
check(rawequal(UncBarsHealth.nativeShield.value, secret), "Restricted ward amount reaches native setter")
check(not UncBarsHealth.nativeShieldEdge.shown, "Restricted absorb hides the fixed-width edge instead of evaluating a secret")
check(not UncBarsHealth.nativeShield.reverseFill and UncBarsHealth.nativeShield.maximum == 1000, "Native ward uses health scale and fills forward from HP")
check(UncBarsHealth.nativeShield.level < UncBarsHealth.overlay.level, "Native ward stays beneath health text")
left, right = shieldSpan()
close(left, 169, "Restricted ward folds at full HP")
close(right, 260, "Folded ward ends at maximum health")
hp = 400
event("UNIT_HEALTH", "player")
left, right = shieldSpan()
close(left, 104, "Restricted ward starts exactly at actual HP after damage")
close(right, 195, "Restricted ward extends from actual HP by its amount")
hp = 250
event("UNIT_HEALTH", "player")
left, right = shieldSpan()
close(left, 65, "Restricted ward follows another HP loss")
close(right, 156, "Restricted ward right edge moves with HP")
hp = 900
event("UNIT_HEALTH", "player")
left, right = shieldSpan()
close(left, 169, "Restricted ward folds again after health increases")
close(right, 260, "Overflow stays inside maximum health")
secretStats, hp, hpMax, absorb = true, 323, 588, 95
event("UNIT_HEALTH", "player")
left, right = shieldSpan()
close(left, 323 / 588 * 260, "Restricted health and ward stay attached at the reported health value")
close(right, 418 / 588 * 260, "Restricted health and ward preserve the correct amount")
absorb = 1000
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
left, right = shieldSpan()
close(left, 0, "Oversized restricted ward caps at the full bar")
close(right, 260, "Oversized restricted ward stays within the bar")
absorb = 0
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
left, right = shieldSpan()
close(left, right, "Restricted depleted ward has zero rendered width")
secretStats, hp, hpMax, absorb = false, 900, 1000, 350
dead = true
event("PLAYER_DEAD")
check(not UncBarsHealth.nativeShield.shown and not UncBarsHealth.shieldOverflow.shown and not UncBarsHealth.shield.shown, "Death hides restricted ward")
dead, secretAbsorb, absorb = false, false, 125
event("PLAYER_ALIVE")
check(not UncBarsHealth.nativeShield.shown and not UncBarsHealth.shieldOverflow.shown and UncBarsHealth.shield.shown, "Readable ward restores normal segment")
absorb = 0
event("UNIT_AURA", "player")
check(not UncBarsHealth.nativeShield.shown and not UncBarsHealth.shield.shown, "Ward expiration clears both display paths")
hp = 400
event("UNIT_HEALTH", "player")
close(UncBarsHealth.activeFill.color[1], 0.92, "Amber at half health")
hp = 250
event("UNIT_HEALTH", "player")
close(UncBarsHealth.activeFill.color[1], 0.9, "Red below thirty percent")
hp = 600
event("UNIT_HEALTH", "player")

start(116)
local costWidth, costLeft = costSpan()
close(costWidth, 6.5, "Exact rank-one spell cost")
close(costLeft, 149.5, "Cost lies inside existing mana")
check(UncBarsPower.cost.parent.clipsChildren, "Native cost is clipped at the bar boundary")
check(UncBarsPower.overlay.level > UncBarsPower.cost.level, "Cost preview remains beneath actual mana text")
for _, bar in ipairs({ UncBarsPower.originalFill, UncBarsPower.foreverFill }) do
    check(UncBarsPower.cost.parent.level > bar.level,
        "The cost preview's clipping frame sits above every mana fill instead of tying with it")
end
check(UncBarsHealth.nativeShield.parent.level > UncBarsHealth.originalFill.level
    and UncBarsHealth.nativeShield.parent.level > UncBarsHealth.foreverFill.level,
    "The shield clipping frame sits above the health fills")
check(UncBarsPower.text.text == "600", "Prediction keeps actual power number")
check(UncBarsPower.costEdge == nil, "The cost preview has no separator line")
check(UncBarsPower.cost.color[1] == 0.55 and UncBarsPower.cost.color[2] == 0.78 and UncBarsPower.cost.color[3] == 1
    and UncBarsPower.cost.color[4] == 1, "The cost preview is opaque pale blue, similar to default full regen")
stop("UNIT_SPELLCAST_INTERRUPTED")
check(not UncBarsPower.cost.shown, "Interruption clears cost")
start(205)
close(costSpan(), 13, "Another rank uses its own cost")
freeCast = true
event("UNIT_AURA", "player")
check(not UncBarsPower.cost.shown, "Free-cast aura refreshes native cost")
freeCast = false
event("UNIT_AURA", "player")
check(UncBarsPower.cost.shown, "Cost returns when free-cast aura ends")
mana = 550
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(not UncBarsPower.cost.shown, "Already deducted mana is not reserved twice")
stop()
mana = 600
event("UNIT_POWER_UPDATE", "player", "MANA")
start(999)
check(not UncBarsPower.cost.shown, "Unknown cost is not guessed")
stop()

incoming = 150
start(2050)
check(UncBarsHealth.heal.shown and UncBarsPower.cost.shown, "Healing and mana predictions coexist")
close(UncBarsHealth.heal.width, 39, "Native own healing amount")
close(UncBarsHealth.heal.point[4], 156, "Healing starts at actual HP")
check(UncBarsHealth.text.text == "600", "Healing keeps actual health number")
hp = 950
event("UNIT_HEALTH", "player")
close(UncBarsHealth.heal.width, 13, "Overhealing clips at maximum health")
incoming = 0
event("UNIT_HEAL_PREDICTION", "player")
check(not UncBarsHealth.heal.shown, "No self-prediction when cast heals someone else")
incoming, hp = 150, 600
event("UNIT_HEAL_PREDICTION", "player")
check(UncBarsHealth.heal.shown, "Client confirms self-healing")
secretIncoming = true
event("UNIT_HEAL_PREDICTION", "player")
check(UncBarsHealth.nativeHeal and UncBarsHealth.nativeHeal.shown and not UncBarsHealth.heal.shown,
    "Restricted incoming self-heals use a native prediction bar")
check(rawequal(UncBarsHealth.nativeHeal.value, secret), "Restricted healing reaches the native value setter unchanged")
local healWidth, healLeft = healSpan()
close(healWidth, 39, "Restricted incoming healing displays its confirmed amount")
close(healLeft, 156, "Restricted healing starts at the actual health fill")
check(UncBarsHealth.nativeHeal.level < UncBarsHealth.overlay.level, "Healing remains below actual health text")
hp = 950
event("UNIT_HEALTH", "player")
close(healSpan(), 13, "Native healing clips overheal at maximum HP")
hp = 1000
event("UNIT_HEALTH", "player")
close(healSpan(), 0, "Full health leaves no visible native healing segment")
hp = 600
incoming = 0
event("UNIT_HEAL_PREDICTION", "player")
close(healSpan(), 0, "Restricted zero healing leaves no fill or fixed-width edge")
incoming = 150
secretStats = true
event("UNIT_HEAL_PREDICTION", "player")
check(UncBarsHealth.nativeHeal.shown and rawequal(UncBarsHealth.nativeHeal.maximum, secret),
    "Healing displays with restricted current health, maximum health, and incoming amount")
close(healSpan(), 39, "Fully restricted healing preserves the correct native geometry")
event("PLAYER_TARGET_CHANGED")
check(UncBarsHealth.nativeHeal.shown, "Changing target preserves client-confirmed self-healing")
ns.SetOption("healQueue", false)
check(not UncBarsHealth.nativeHeal.shown and not UncBarsHealth.heal.shown, "Healing toggle clears the restricted preview")
ns.SetOption("healQueue", true)
check(UncBarsHealth.nativeHeal.shown, "Healing toggle restores the restricted preview during the cast")
stop("UNIT_SPELLCAST_INTERRUPTED")
check(not UncBarsHealth.nativeHeal.shown, "Interrupted self-heals clear the native preview")
start(2050)
secretStats = false
secretIncoming = false
event("UNIT_HEAL_PREDICTION", "player")
check(UncBarsHealth.heal.shown and not UncBarsHealth.nativeHeal.shown,
    "Readable self-heals return to the ordinary segment without duplicate fills")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "unrelated-instant")
check(UncBarsHealth.heal.shown, "Unrelated instant does not clear active cast")
activeCast.finish = activeCast.finish + 1000
event("UNIT_SPELLCAST_DELAYED", "player", activeCast.guid)
update(2.6)
check(UncBarsHealth.heal.shown, "Pushback extends prediction")
update(1.2)
check(not UncBarsHealth.heal.shown, "Expired cast cannot leave stale prediction")
activeCast = nil
start(2050, "cast2")
event("UNIT_SPELLCAST_STOP", "player", "cast1")
check(UncBarsHealth.heal.shown, "Stale stop does not clear a new cast")
stop("UNIT_SPELLCAST_FAILED")
check(not UncBarsHealth.heal.shown and not UncBarsPower.cost.shown, "Failure clears both predictions")
start(2050)
activeCast = nil
event("UNIT_SPELLCAST_CHANNEL_START", "player", "channel1")
check(not UncBarsHealth.heal.shown and not UncBarsPower.cost.shown, "Channels do not reserve paid upfront costs or direct heals")

secretStats = true
start(116)
check(UncBarsPower.cost.shown, "Mana preview remains visible with restricted mana values")
check(rawequal(UncBarsPower.cost.maximum, secret), "Restricted maximum is passed directly to native cost bar")
stop()
secretStats = false
secretCastMetadata = true
start(116)
check(UncBarsPower.cost.shown, "Restricted cast name, timing and GUID do not suppress mana preview")
update(0.1)
check(UncBarsPower.cost.shown, "Restricted cast timing does not expire or reject an active preview")
stop()
secretCastMetadata = false
secretCost = true
start(116)
check(UncBarsPower.cost.shown, "Native cost display accepts restricted cost")
check(rawequal(UncBarsPower.cost.value, secret), "Restricted cost reaches the native value setter")
check(UncBarsPower.cost.color[1] == 0.55 and UncBarsPower.cost.color[4] == 1,
    "A restricted cost keeps the same overlay")
stop()
secretCost = false
missingCastSpellID = true
start(116)
check(UncBarsPower.cost.shown, "Cast event supplies exact spell ID when casting snapshot omits it")
stop()
missingCastSpellID = false
castInfoPending = true
start(116)
check(UncBarsPower.cost.shown, "Cast start can precede casting snapshot")
castInfoPending = false
update(0.05)
check(UncBarsPower.cost.shown, "Next frame resolves pending casting snapshot")
stop()
secretStats, secretCost, secretCastMetadata, secretSpellID = true, true, true, true
activeCast = { id = 116, guid = "restricted", barID = 77, finish = now * 1000 + 2500 }
event("UNIT_SPELLCAST_START", "player", secret, secret, 77)
check(UncBarsPower.cost.shown and rawequal(UncBarsPower.cost.value, secret), "All restricted cast values render together without Lua arithmetic")
event("UNIT_SPELLCAST_SUCCEEDED", "player", secret, secret, 78)
check(UncBarsPower.cost.shown, "Public cast-bar identity preserves active preview across unrelated restricted events")
event("UNIT_SPELLCAST_STOP", "player", secret, secret, 77)
check(not UncBarsPower.cost.shown, "Matching public cast-bar identity clears restricted cast")
activeCast = nil
secretStats, secretCost, secretCastMetadata, secretSpellID = false, false, false, false

mana = 10
event("UNIT_POWER_UPDATE", "player", "MANA")
start(116)
close(costSpan(), 2.6, "Native clipped cost does not extend below zero mana")
stop()
mana = 600
event("UNIT_POWER_UPDATE", "player", "MANA")

kind = 1
event("UNIT_DISPLAYPOWER", "player")
close(UncBarsPower.activeFill.value, 60, "Rage displays in shifted form")
close(UncBarsPower.activeFill.maximum, 100, "Rage maximum")
check(UncBarsPower.activeFill.color[1] == 1 and UncBarsPower.activeFill.color[2] == 0, "Native rage color")
kind = 3
event("UNIT_DISPLAYPOWER", "player")
check(UncBarsPower.activeFill.color[1] == 1 and UncBarsPower.activeFill.color[2] == 1, "Native energy color")
kind = 0
event("UNIT_DISPLAYPOWER", "player")
SlashCmdList.UNCBARS("text full")
check(UncBarsHealth.text.text == "600 / 1000", "Full-value text mode")
SlashCmdList.UNCBARS("text percent")
check(UncBarsPower.text.text == "60%", "Percentage text mode")
SlashCmdList.UNCBARS("text current")
SlashCmdList.UNCBARS("unlock")
check(UncBarsFrame.mouse, "Unlock permits dragging")
UncBarsFrame.cx, UncBarsFrame.cy = 1000, 350
UncBarsFrame.scripts.OnDragStart(UncBarsFrame)
UncBarsFrame.scripts.OnDragStop(UncBarsFrame)
check(UncBarsDB.x == 100 and UncBarsDB.y == -150, "Dragged position is persisted")
SlashCmdList.UNCBARS("lock")
check(not UncBarsFrame.mouse, "Lock restores click-through")
SlashCmdList.UNCBARS("center")
check(UncBarsDB.x == 0 and UncBarsDB.y == -150, "Horizontal centering preserves vertical position")
SlashCmdList.UNCBARS("width 300")
SlashCmdList.UNCBARS("healthheight 30")
SlashCmdList.UNCBARS("manaheight 16")
SlashCmdList.UNCBARS("gap 3")
check(UncBarsHealth.width == 300 and UncBarsFrame.height == 49, "Independent dimensions and gap")
SlashCmdList.UNCBARS("width 1")
check(UncBarsDB.width == 300, "Invalid width rejected")
SlashCmdList.UNCBARS("height 10")
check(UncBarsHealth.height == 10 and UncBarsPower.height == 10 and UncBarsHealth.text.fontSize == 8, "Shared height and fitted text")
SlashCmdList.UNCBARS("test")
check(UncBarsHealth.heal.shown and UncBarsHealth.shield.shown and UncBarsPower.cost.shown, "Test mode demonstrates all segments")
check(UncBarsFrame.mode.text:find("PREVIEW"), "Sample values labeled")
combat = true
event("PLAYER_REGEN_DISABLED")
check(UncBarsPower.text.text == "600" and not UncBarsFrame.mode.text:find("PREVIEW"), "Combat exits test mode")
SlashCmdList.UNCBARS("test")
check(not UncBarsFrame.mode.text:find("PREVIEW"), "Cannot enter preview in combat")
combat = false
start(2050)
SlashCmdList.UNCBARS("healqueue")
check(not UncBarsHealth.heal.shown and UncBarsPower.cost.shown, "Independent healing toggle")
SlashCmdList.UNCBARS("healqueue")
SlashCmdList.UNCBARS("queue")
check(UncBarsHealth.heal.shown and not UncBarsPower.cost.shown, "Independent mana toggle")
SlashCmdList.UNCBARS("queue")
dead = true
event("PLAYER_DEAD")
check(not UncBarsHealth.heal.shown and not UncBarsPower.cost.shown, "Death clears predictions")
check(not UncBarsHealth.nativeHeal.shown, "Death also clears native healing predictions")
dead = false
event("PLAYER_ALIVE")
SlashCmdList.UNCBARS("off")
check(not UncBarsFrame.shown, "Off hides HUD")
SlashCmdList.UNCBARS("on")
check(UncBarsFrame.shown, "On restores HUD")
secretStats = true
event("UNIT_HEALTH", "player")
check(rawequal(UncBarsHealth.activeFill.value, secret) and not UncBarsHealth.shield.shown, "Restricted values reach native bar setters without Lua arithmetic")
check(UncBarsHealth.nativeShield.shown and rawequal(UncBarsHealth.nativeShield.maximum, secret), "Shield remains visible with restricted health and absorbs")
check(rawequal(UncBarsHealth.nativeShield.alphaCondition, secret)
    and UncBarsHealth.nativeShield.alphaIfTrue == 0 and UncBarsHealth.shieldOverflow.alphaIfTrue == 1,
    "Native alpha sinks select attached versus folded display using restricted overflow boolean")
secretAbsorb = false
-- Keep HP restricted while the native absorb total is readable and depleted.
local restrictedAbsorbs = UnitGetTotalAbsorbs
UnitGetTotalAbsorbs = function() return 0 end
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check(not UncBarsHealth.nativeShield.shown, "Depleted ward hides even while health remains restricted")
UnitGetTotalAbsorbs = function() return 100 end
event("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check(UncBarsHealth.nativeShield.shown and UncBarsHealth.nativeShieldEdge.shown, "Readable positive absorb restores edge with restricted health")
UnitGetTotalAbsorbs = restrictedAbsorbs
SlashCmdList.UNCBARS("text full")
SlashCmdList.UNCBARS("text percent")
event("UNIT_POWER_FREQUENT", "player")
secretStats = false
SlashCmdList.UNCBARS("reset")
check(UncBarsDB.width == 260 and UncBarsDB.healthHeight == 20 and UncBarsDB.manaHeight == 14 and UncBarsDB.gap == 0, "Reset restores original layout")
check(UncBarsDB.x == 0 and UncBarsDB.y == -110 and not UncBarsFrame.mouse, "Reset restores locked default position")
hp = 0
hpMax, manaMax = 0, 0
event("UNIT_MAXHEALTH", "player")
check(not UncBarsHealth.heal.shown and not UncBarsPower.cost.shown, "Zero maxima are safe")

-- Reload-like initialization for additional classes and saved preferences.
-- A real /reload recreates all frames; the mock replaces globals and routes
-- events only to the new event frame.
local function login(asClass, settings)
    playerClass, UncBarsDB = asClass, settings or {}
    hp, hpMax, mana, manaMax, kind, points = 800, 1000, 600, 1000, 0, 0
    combat, dead, secretStats, secretPoints, activeCast = false, false, false, false, nil
    targetingSpell, secretTargetSpell = nil, false
    ns = {}
    assert(load(LOGIC_SOURCE, "@Logic.lua"))("UncBars", ns)
    assert(load(ADDON_SOURCE, "@UncBars.lua"))("UncBars", ns)
    assert(load(OPTIONS_SOURCE, "@Options.lua"))("UncBars", ns)
    event("PLAYER_LOGIN")
end

login("DRUID", { x = 75, y = -140 })
check(UncBarsPower.activeFill.value == 60 and UncBarsMana.activeFill.value == 600, "Caster druid shows actual cat energy and mana together")
check(UncBarsMana.shown and not UncBarsEnergy.shown, "Caster has no duplicate energy row")
check(UncBarsFrame.height == 76 and UncBarsComboPoints.shown, "Druid stack includes three bars and combo orbs")
check(UncBarsComboPoints.orbs[1].value == 0, "Empty combo row remains visible outside cat form")
energyValue = 43
event("UNIT_POWER_FREQUENT", "player", "ENERGY")
check(UncBarsPower.activeFill.value == 43 and UncBarsMana.activeFill.value == 600, "Off-form energy updates independently of mana")
kind = 3
event("UPDATE_SHAPESHIFT_FORM")
check(UncBarsPower.activeFill.value == 43 and UncBarsMana.shown and not UncBarsEnergy.shown, "Cat uses a single energy bar and retains mana")
points = 4
event("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
check(UncBarsComboPoints.orbs[4].value == 4, "Combo power event updates native orb fills")
check(UncBarsComboPoints.orbs[4].minimum == 3 and UncBarsComboPoints.orbs[4].maximum == 4,
    "Fourth orb native fill becomes full only at four points")
points = 0
event("PLAYER_TARGET_CHANGED")
check(UncBarsComboPoints.orbs[1].value == 0, "Target switch clears old target points immediately")
points = 2
event("COMBO_TARGET_CHANGED")
check(UncBarsComboPoints.orbs[2].value == 2, "Transferred combo points refresh without a raw power event")
kind = 1
event("UNIT_DISPLAYPOWER", "player")
check(UncBarsPower.activeFill.value == 60 and UncBarsEnergy.activeFill.value == 43 and UncBarsMana.activeFill.value == 600,
    "Bear retains active rage, off-form energy, and mana")
check(UncBarsEnergy.shown and UncBarsMana.shown and UncBarsFrame.height == 90,
    "Bear stack grows to fit the additional resource")
kind = nil
event("PLAYER_LEAVING_WORLD")
check(not UncBarsFrame.shown, "Druid portal tolerates a missing active resource")
kind = 0
event("PLAYER_ENTERING_WORLD")
check(UncBarsFrame.shown and UncBarsPower.kind == 3 and UncBarsMana.shown
    and not UncBarsEnergy.shown and UncBarsFrame.height == 76,
    "Portal recovery rearranges druid resources when the active form changes")
kind = 1
event("UNIT_DISPLAYPOWER", "player")
start(116)
check(UncBarsMana.cost.shown and not UncBarsPower.cost.shown and not UncBarsEnergy.cost.shown,
    "Shapeshifted mana preview attaches to mana, not rage or energy")
mana = 575
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(not UncBarsMana.cost.shown, "Off-form mana payment clears reserved mana")
stop()
kind = 0
event("UNIT_DISPLAYPOWER", "player")
check(not UncBarsEnergy.shown and UncBarsFrame.height == 76, "Leaving bear removes extra row and collapses stack")
check(UncBarsDB.x == 75 and UncBarsDB.y == -140, "Shapeshifting preserves saved position")
secretStats, secretPoints = true, true
event("UNIT_POWER_FREQUENT", "player", "ENERGY")
check(rawequal(UncBarsPower.activeFill.value, secret) and rawequal(UncBarsMana.activeFill.value, secret),
    "Both druid resource bars accept restricted power values")
check(rawequal(UncBarsComboPoints.orbs[5].value, secret), "Restricted combo count passes directly to native orb setters")
secretStats, secretPoints = false, false
ns.SetOption("druidEnergy", false)
check(UncBarsPower.activeFill.value == 575 and not UncBarsMana.shown, "Disabling off-form energy restores caster mana without a duplicate")
kind = 3
event("UNIT_DISPLAYPOWER", "player")
check(UncBarsPower.activeFill.value == 43 and UncBarsMana.shown, "Energy option does not hide cat's active energy")
ns.SetOption("druidMana", false)
check(not UncBarsMana.shown, "Optional mana row can be hidden while shifted")
ns.SetOption("comboPoints", false)
check(not UncBarsComboPoints.shown and UncBarsFrame.height == 34, "Combo toggle removes orbs and their reserved space")
ns.SetOption("druidEnergy", true)
ns.SetOption("druidMana", true)
ns.SetOption("comboPoints", true)

-- Build and exercise the actual options window, including native slider
-- callbacks during refresh, so accidental refresh recursion is observable.
ns.Command("unlock")
ns.Command("")
check(UncBarsOptions.shown and UncBarsOptions.unlocked, "Bare /ub opens options and reflects an already unlocked HUD")
check(UncBarsMoveButton.text == "Lock bars", "Move action reflects current state")
UncBarsMoveButton.scripts.OnClick(UncBarsMoveButton)
check(not UncBarsFrame.mouse and UncBarsMoveButton.text == "Move bars", "Options move action relocks the HUD")
local resourceRows = { UncBarsHealth, UncBarsPower, UncBarsMana, UncBarsEnergy }
local originalFills = {}
for _, bar in ipairs(resourceRows) do originalFills[bar] = bar.activeFill end
UncBarsPresetForever.scripts.OnClick(UncBarsPresetForever)
check(UncBarsDB.style == "forever" and UncBarsHealth.width == 200 and UncBarsHealth.height == 16,
    "Forever preset applies compact native dimensions")
check(UncBarsHealth.frameArt.shown and not UncBarsHealth.background.shown
    and UncBarsHealth.activeFill:GetStatusBarTexture().atlas == "UI-HUD-CoolDownManager-Bar", "Forever preset uses the native bar atlas and frame")
for _, bar in ipairs(resourceRows) do
    check(bar.activeFill ~= originalFills[bar] and bar.activeFill.shown and not originalFills[bar].shown,
        "Forever uses an independent fill and hides the untouched Original fill")
end
check(UncBarsPower.leftText.text == "43%" and UncBarsPower.text.text == "43", "Split text places percentage and value separately")
check(UncBarsDB.x == 75 and UncBarsDB.y == -140 and UncBarsDB.druidEnergy, "Appearance preset preserves location and resource choices")
UncBarsOption_width:SetValue(321)
check(UncBarsDB.width == 321 and UncBarsMana.width == 321, "Options slider updates all rows live without refresh recursion")
UncBarsPreviewButton.scripts.OnClick(UncBarsPreviewButton)
check(UncBarsComboPoints.orbs[1].value == 3 and UncBarsMana.cost.shown, "Druid preview includes combo points and mana-cost prediction")
check(UncBarsMana.cost.point[2] == UncBarsMana.activeFill:GetStatusBarTexture(),
    "Mana cost preview follows the active Forever mana fill")
combat = true
event("PLAYER_REGEN_DISABLED")
check(UncBarsComboPoints.orbs[1].value == 2 and UncBarsPreviewButton.text == "Sample values", "Combat restores real combo points and updates preview button")
combat = false
event("PLAYER_REGEN_ENABLED")
UncBarsOption_comboPoints:SetChecked(false)
UncBarsOption_comboPoints.scripts.OnClick(UncBarsOption_comboPoints)
check(not UncBarsComboPoints.shown and not UncBarsDB.comboPoints, "Options checkbox changes the resource display")
UncBarsPresetOriginal.scripts.OnClick(UncBarsPresetOriginal)
check(UncBarsDB.width == 260 and UncBarsDB.textMode == "current" and not UncBarsHealth.frameArt.shown,
    "Original preset restores borderless style and centered values")
for _, bar in ipairs(resourceRows) do
    local fill = bar.activeFill
    check(fill == originalFills[bar] and fill.shown and not bar.foreverFill.shown
        and fill.texture == "Interface\\TargetingFrame\\UI-StatusBar" and not fill:GetStatusBarTexture().atlas,
        "Switching back shows the same Original fill that was built at login")
end
check(UncBarsHealth.nativeHeal.point[2] == UncBarsHealth.activeFill:GetStatusBarTexture()
    and UncBarsHealth.nativeShield.point[2] == UncBarsHealth.activeFill:GetStatusBarTexture(),
    "Switching styles moves native healing and shield anchors to the active health fill")
check(UncBarsMana.activeFill.value == mana and UncBarsHealth.activeFill.value == hp,
    "The newly selected fills show current values immediately")
ns.Command("text hidden")
check(UncBarsHealth.text.text == "" and not UncBarsHealth.leftText.shown, "Hidden text mode leaves no leftover split labels")
ns.Command("text split")
secretStats = true
event("UNIT_HEALTH", "player")
check(UncBarsHealth.text.text == "<native restricted text>" and UncBarsHealth.leftText.text == "<native restricted text>",
    "Split labels render restricted values without formatting them in Lua")
secretStats = false

-- Replacement is reversible, respects combat lockdown, and works when the
-- client loads its resource display after UncBars.
PersonalResourceDisplayFrame = nil
ns.SetOption("hideDefault", true)
PersonalResourceDisplayFrame = CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
PersonalResourceDisplayFrame:SetAlpha(0.75)
event("ADDON_LOADED", "Blizzard_PersonalResourceDisplay")
check(PersonalResourceDisplayFrame.alpha == 0, "Replacement picks up the late-loaded default display")
ns.Command("off")
check(PersonalResourceDisplayFrame.alpha == 0.75, "Disabling UncBars restores original default display alpha")
ns.Command("on")
check(PersonalResourceDisplayFrame.alpha == 0, "Enabling UncBars reapplies replacement")
combat = true
ns.SetOption("hideDefault", false)
check(PersonalResourceDisplayFrame.alpha == 0, "Combat defers default frame restoration")
combat = false
event("PLAYER_REGEN_ENABLED")
check(PersonalResourceDisplayFrame.alpha == 0.75, "Combat end restores the default frame")
ns.Command("reset")
check(not UncBarsDB.hideDefault and UncBarsDB.style == "original" and UncBarsDB.druidEnergy,
    "Full reset restores default appearance and druid preferences")

login("ROGUE")
kind, points = 3, 5
event("PLAYER_TARGET_CHANGED")
check(UncBarsComboPoints.shown and not UncBarsMana.shown and not UncBarsEnergy.shown,
    "Rogue gets combo orbs with a single active resource bar")
check(UncBarsComboPoints.orbs[5].value == 5, "Rogue combo points use the same target-bound display")
dead = true
event("PLAYER_DEAD")
check(UncBarsComboPoints.orbs[1].value == 0, "Death clears combo orb fills")

login("MAGE", { style = "forever", textMode = "split", width = 222, comboSize = 25, druidEnergy = false })
check(UncBarsDB.style == "forever" and UncBarsDB.textMode == "split" and UncBarsHealth.width == 222,
    "Reload preserves customized Forever settings")
check(not UncBarsComboPoints.shown and not UncBarsMana.shown and not UncBarsEnergy.shown,
    "Non-combo classes retain the original two-bar layout")
login("DRUID", { style = "bad", textMode = "bad", width = 1, comboSize = 500, druidEnergy = "bad" })
check(UncBarsDB.style == "original" and UncBarsDB.textMode == "current" and UncBarsDB.width == 140
    and UncBarsDB.comboSize == 32 and UncBarsDB.druidEnergy == true, "Invalid saved settings are repaired at login")
-- Five-second regen waits are independent of pending cast predictions.
login("MAGE")
check(UncBarsDB.manaRegen and not UncBarsPower.regen.shown,
    "Regen timer defaults on but stays invisible while idle")
start(116)
check(not UncBarsPower.regen.shown, "Starting a cast does not start the regen wait")
stop("UNIT_SPELLCAST_INTERRUPTED")
check(not UncBarsPower.regen.shown, "Canceled unpaid casts do not start the regen wait")
start(116)
stop()
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast1", 116)
check(UncBarsPower.regen.shown and UncBarsPower.regen.value == 5,
    "Successful spell starts the timer even when STOP arrives before SUCCEEDED")
update(1.25)
close(UncBarsPower.regen.value, 3.75, "Countdown animates without an active cast or resource event")
local remaining = UncBarsPower.regen.value
freeCast = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "free", 116)
close(UncBarsPower.regen.value, remaining, "Readable free spell does not restart the wait")
freeCast = false
event("UNIT_SPELLCAST_SUCCEEDED", "player", "nonmana", 998)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "unknown", 999)
close(UncBarsPower.regen.value, remaining, "Non-mana and unknown spell costs do not restart the wait")
start(116)
stop("UNIT_SPELLCAST_FAILED")
close(UncBarsPower.regen.value, remaining, "Failed casts leave the previous wait intact")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "instant", 116)
close(UncBarsPower.regen.value, 5, "Next paid instant spell restarts the five-second wait")
event("UNIT_SPELLCAST_CHANNEL_START", "player", "instant", 116)
update(2)
event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "instant", 116)
close(UncBarsPower.regen.value, 3, "Channel stop does not extend the wait from its upfront success")
mana = 500
event("UNIT_POWER_FREQUENT", "player", "MANA")
close(UncBarsPower.regen.value, 3, "Mana drain alone does not falsely restart the cast-based timer")
ns.Command("regen")
check(not UncBarsDB.manaRegen and not UncBarsPower.regen.shown,
    "Regen toggle hides the strip immediately")
ns.Command("regen")
close(UncBarsPower.regen.value, 3, "Re-enabling the timer preserves the current wait")
update(3.1)
check(not UncBarsPower.regen.shown,
    "Timer disappears on expiry without an active cast")
secretStats, secretCost = true, true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "restricted", 116)
check(UncBarsPower.regen.shown and UncBarsPower.regen.value == 5,
    "Restricted mana and costs use a cast-based estimate without secret arithmetic")
secretStats, secretCost = false, false
dead = true
event("PLAYER_DEAD")
check(not UncBarsPower.regen.shown, "Death clears the regen timer")
dead = false
event("PLAYER_ALIVE")
check(not UncBarsPower.regen.shown, "Reviving does not restore a stale timer")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "portal", 116)
event("PLAYER_LEAVING_WORLD")
event("PLAYER_ENTERING_WORLD")
check(not UncBarsPower.regen.shown, "World transitions clear untrusted timer state")
ns.Command("test")
check(UncBarsPower.regen.shown and UncBarsPower.regen.value == 3.2, "Sample mode demonstrates the regen indicator")
ns.Command("test")
check(not UncBarsPower.regen.shown, "Leaving sample mode restores the real idle state")
ns.Command("")
UncBarsOption_manaRegen:SetChecked(false)
UncBarsOption_manaRegen.scripts.OnClick(UncBarsOption_manaRegen)
check(not UncBarsDB.manaRegen, "Options checkbox persists the regen preference")
login("DRUID")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "druid", 116)
check(UncBarsMana.regen.shown and not UncBarsPower.regen.shown and not UncBarsEnergy.regen.shown,
    "Caster druid regen indicator follows mana below cat energy")
kind = 1
event("UNIT_DISPLAYPOWER", "player")
check(UncBarsMana.regen.shown and not UncBarsPower.regen.shown and not UncBarsEnergy.regen.shown,
    "Shapeshifting keeps the regen indicator off rage and energy")
ns.SetOption("druidMana", false)
check(not UncBarsMana.regen.shown, "Hiding the off-form mana row hides its indicator")
-- Configure the timer through the real controls and exercise native picker
-- callbacks, including cancel, rather than only setting the saved variables.
login("MAGE")
ns.Command("")
UncBarsPage_regen.scripts.OnClick(UncBarsPage_regen)
check(UncBarsOptions.page == "regen", "Mana regen page is reachable from options")
check(not UncBarsPage_manacolors, "Mana colors no longer has its own sidebar page")
check(UncBarsOptions.regenTab == "timer" and UncBarsRegenPage_timer.shown and not UncBarsRegenPage_colors.shown,
    "Mana regen opens on the timer strip sub-tab while the strip is in use")
check(UncBarsRegenTab_timer.text:find("(on)", 1, true) and not UncBarsRegenTab_colors.text:find("(on)", 1, true),
    "Sub-tab labels show which display is on")
ns.Command("test")
check(not UncBarsPower.regenText.shown and UncBarsPower.regen.height == 1,
    "Existing settings migrate to a thin strip with no countdown")
UncBarsOption_manaRegenHeight:SetValue(50)
close(UncBarsPower.regen.height, 7, "Height slider scales the strip to half the original mana bar")
ns.ApplyPreset("forever")
close(UncBarsPower.regen.height, 4, "Forever height uses the bar interior to preserve its border")
ns.SetOption("manaHeight", 20)
close(UncBarsPower.regen.height, 8, "Changing mana bar height rescales the regen strip")
UncBarsOption_manaRegenHeight:SetValue(100)
close(UncBarsPower.regen.height, 16, "Full-height regen remains inside the Forever border")
check(UncBarsPower.regen.level < UncBarsPower.overlay.level, "Tall regen fill stays behind resource text")
UncBarsOption_manaRegenNumber:SetChecked(true)
UncBarsOption_manaRegenNumber.scripts.OnClick(UncBarsOption_manaRegenNumber)
check(UncBarsPower.regenText.shown and UncBarsPower.regenText.text == "3.2s",
    "Countdown checkbox shows remaining seconds in sample mode")
check(UncBarsPower.text.text == "1350" and UncBarsPower.leftText.text == "68%",
    "Optional countdown preserves the actual split resource labels")
ns.Command("text full")
check(UncBarsPower.regenText.shown and UncBarsPower.text.width == UncBarsDB.width - 50,
    "Full resource text reserves space for the optional countdown")
ns.Command("text hidden")
check(UncBarsPower.regenText.shown and UncBarsPower.text.text == "",
    "Countdown toggle is independent of the resource text mode")
ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
function ColorPickerFrame:SetupColorPickerAndShow(info)
    self.info = info
    self.r, self.g, self.b, self.a = info.r, info.g, info.b, info.opacity
    self:Show()
    info.swatchFunc()
end
function ColorPickerFrame:GetColorRGB() return self.r, self.g, self.b end
function ColorPickerFrame:GetColorAlpha() return self.a end
UncBarsRegenColor.scripts.OnClick(UncBarsRegenColor)
check(ColorPickerFrame.shown and ColorPickerFrame.info.hasOpacity, "Color button opens the native picker with opacity")
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b, ColorPickerFrame.a = 0.2, 0.7, 0.9, 0.4
ColorPickerFrame.info.swatchFunc()
close(UncBarsPower.regen.color[1], 0.2, "Picker changes preview on the regen indicator immediately")
close(UncBarsRegenColor.swatch.color[3], 0.9, "Options swatch follows the selected color")
ColorPickerFrame.a = 0.6
ColorPickerFrame.info.opacityFunc()
close(UncBarsPower.regen.color[4], 0.6, "Opacity changes preview immediately")
ColorPickerFrame.info.cancelFunc()
close(UncBarsDB.manaRegenRed, 1, "Cancel restores the color from before opening the picker")
close(UncBarsDB.manaRegenAlpha, 0.9, "Cancel restores the previous opacity")
UncBarsRegenColor.scripts.OnClick(UncBarsRegenColor)
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0.2, 0.3, 0.4
ColorPickerFrame.info.swatchFunc()
ColorPickerFrame:Hide()
local savedRegenSettings = {}
for key, value in pairs(UncBarsDB) do savedRegenSettings[key] = value end
login("MAGE", savedRegenSettings)
check(UncBarsDB.manaRegenNumber and UncBarsDB.manaRegenHeight == 100 and UncBarsDB.manaRegenBlue == 0.4,
    "Reload preserves customized height, countdown and color")
ns.Command("")
UncBarsRegenColorReset.scripts.OnClick(UncBarsRegenColorReset)
close(UncBarsDB.manaRegenGreen, 0.72, "Reset color restores amber")
check(UncBarsDB.manaRegenNumber and UncBarsDB.manaRegenHeight == 100, "Reset color preserves other regen preferences")
ns.Command("test")
ns.SetOption("manaRegen", false)
check(not UncBarsPower.regen.shown and not UncBarsPower.regenText.shown, "Disabling regen hides both strip and optional number")
ns.Command("reset")
check(UncBarsDB.manaRegenHeight == 7 and not UncBarsDB.manaRegenNumber and UncBarsDB.manaRegenBlue == 0.22,
    "Full reset restores all regen defaults")
login("MAGE", { manaRegenHeight = 150, manaRegenNumber = "bad", manaRegenRed = -1, manaRegenAlpha = 3 })
check(UncBarsDB.manaRegenHeight == 100 and not UncBarsDB.manaRegenNumber
    and UncBarsDB.manaRegenRed == 0 and UncBarsDB.manaRegenAlpha == 1,
    "Invalid saved regen preferences are repaired and clamped")
login("MAGE", { manaRegenNumber = true })
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
update(1)
-- Success can precede the channel event. Evocation must leave the old deadline intact.
event("UNIT_SPELLCAST_SUCCEEDED", "player", "evocation", 12051)
close(UncBarsPower.regen.value, 4, "Evocation success does not restart the original wait")
event("UNIT_SPELLCAST_CHANNEL_START", "player", "evocation", 12051)
check(not UncBarsPower.regen.shown and not UncBarsPower.regenText.shown,
    "Evocation channel hides both indicators as soon as it starts")
update(1)
event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "evocation", 12051)
check(UncBarsPower.regen.shown and UncBarsPower.regenText.text == "3.0s",
    "Canceling Evocation reveals only the remainder of the original wait")
channelSpell = 12051
event("UNIT_SPELLCAST_CHANNEL_START", "player", secret, secret)
check(not UncBarsPower.regen.shown, "Readable channel info identifies Evocation if the event ID is restricted")
update(4)
channelSpell = nil
event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "evocation", 12051)
check(not UncBarsPower.regen.shown, "The original wait expires while Evocation is active")

activeRegenAuras[29166] = {}
event("UNIT_AURA", "player")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
check(not UncBarsPower.regen.shown, "An existing Innervate on the player suppresses a new wait")
update(2)
activeRegenAuras[29166] = nil
event("UNIT_AURA", "player")
close(UncBarsPower.regen.value, 3, "Innervate ending reveals any remaining time")
activeRegenAuras[29166] = {}
event("UNIT_AURA", "player")
check(not UncBarsPower.regen.shown, "Receiving Innervate mid-wait suppresses the indicator immediately")
activeRegenAuras[29166] = nil
event("UNIT_AURA", "player")
castingRegen = baseRegen
update(0.5)
check(not UncBarsPower.regen.shown, "Any readable full casting regen rate suppresses the indicator")
castingRegen = baseRegen / 2
update(0.5)
check(UncBarsPower.regen.shown, "Partial regen leaves the underlying wait visible")
mana = 700
event("UNIT_POWER_FREQUENT", "player", "MANA")
close(UncBarsPower.regen.value, 2, "A mana restore does not end or restart the wait")
baseRegen, castingRegen, channelSpell, restrictedAuras = secret, secret, secret, true
event("UNIT_AURA", "player")
check(UncBarsPower.regen.shown, "Restricted aura, channel, and regen data preserve the normal estimate")
baseRegen, castingRegen, channelSpell, restrictedAuras = 20, 5, nil, false

-- Regen-state colors tint the mana fill itself instead of drawing the strip.
local function fillColor(bar) return bar.activeFill.color end
login("MAGE")
check(not UncBarsDB.manaRegenColors, "Mana regen colors default off")
close(fillColor(UncBarsPower)[1], 0.05, "Mana keeps its usual color while the toggle is off")
check(UncBarsDB.manaFullRed == 0.05 and UncBarsDB.manaFullGreen == 0.25 and UncBarsDB.manaFullBlue == 1
    and UncBarsDB.manaWaitRed == UncBarsDB.manaFullRed and UncBarsDB.manaWaitGreen == UncBarsDB.manaFullGreen
    and UncBarsDB.manaWaitBlue == UncBarsDB.manaFullBlue, "Full and waiting colors default to the existing mana color")
check(UncBarsDB.manaFastRed > UncBarsDB.manaFullRed and UncBarsDB.manaFastGreen > UncBarsDB.manaFullGreen
    and UncBarsDB.manaFastBlue == 1, "After-wait color defaults to a lighter blue")
check(UncBarsDB.manaSuperRed > UncBarsDB.manaFastRed and UncBarsDB.manaSuperGreen > UncBarsDB.manaFastGreen
    and UncBarsDB.manaSuperBlue == 1, "Supercharged color defaults to an even lighter blue")
ns.Command("")
UncBarsPage_regen.scripts.OnClick(UncBarsPage_regen)
UncBarsRegenTab_colors.scripts.OnClick(UncBarsRegenTab_colors)
check(UncBarsOptions.page == "regen" and UncBarsOptions.regenTab == "colors"
    and UncBarsRegenPage_colors.shown and not UncBarsRegenPage_timer.shown,
    "Bar colors is a sub-tab of the Mana regen page")
check(not UncBarsManaColorSection.shown, "The bar colors sub-tab hides its pickers until the toggle is on")
check(UncBarsDB.manaRegen, "The timer strip is on before bar colors are enabled")
UncBarsOption_manaRegenColors:SetChecked(true)
UncBarsOption_manaRegenColors.scripts.OnClick(UncBarsOption_manaRegenColors)
check(not UncBarsDB.manaRegen and not UncBarsOption_manaRegen.checked,
    "Turning on bar colors turns off the timer strip and unchecks it")
check(UncBarsRegenTab_colors.text:find("(on)", 1, true) and not UncBarsRegenTab_timer.text:find("(on)", 1, true),
    "Sub-tab labels follow the active display")
check(UncBarsDB.manaRegenColors and UncBarsManaColorSection.shown and UncBarsManaSuperColor,
    "Toggle saves and reveals four color pickers")
close(fillColor(UncBarsPower)[2], 0.25, "Turning on bar colors starts a fade from the usual mana color")
update(0.15)
close(fillColor(UncBarsPower)[2], 0.465, "Turning on bar colors fades rather than switches")
update(0.2)
close(fillColor(UncBarsPower)[2], 0.68, "Mana below full after the wait uses the faster-regen color")
ns.SetColor("manaWait", 0.9, 0.1, 0.1)
ns.SetColor("manaFull", 0.1, 0.9, 0.1)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
close(fillColor(UncBarsPower)[1], 0.38, "Spending mana starts a fade from the current color")
check(not UncBarsPower.regen.shown, "Color mode replaces the overlaid strip")
update(0.15)
close(fillColor(UncBarsPower)[1], 0.64, "Halfway through the fade the two colors are mixed")
update(0.2)
close(fillColor(UncBarsPower)[1], 0.9, "The fade finishes on the waiting color")
update(2)
close(fillColor(UncBarsPower)[1], 0.9, "Fill keeps the waiting color during the wait")
update(2.75)
close(fillColor(UncBarsPower)[1], 0.9, "Wait expiry starts a fade instead of switching instantly")
update(0.15)
close(fillColor(UncBarsPower)[1], 0.64, "The fade animates without a cast, timer, or power event")
update(0.2)
close(fillColor(UncBarsPower)[2], 0.68, "The fade finishes on the faster-regen color")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[2], 0.9, "Topping off fades to the full color")
mana = 985
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[2], 0.79, "Mana just below full shades between the after-wait and full colors")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
update(0.35)
close(fillColor(UncBarsPower)[2], 0.9, "Full mana keeps the full color during a wait")
mana = 600
secretStats = true
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(rawequal(fillColor(UncBarsPower)[1], secret) and nativeManaColor and math.abs(nativeManaColor.r - 0.9) < 0.001,
    "Restricted mana below full uses the waiting color from the native curve")
mana = 985
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(math.abs(nativeManaColor.g - 0.5) < 0.001, "Restricted mana near full shades toward the full color natively")
mana = 1000
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(math.abs(nativeManaColor.g - 0.9) < 0.001, "Restricted full mana uses the full color without Lua comparisons")
update(4.7)
mana = 600
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(math.abs(nativeManaColor.r - 0.9) < 0.001, "Restricted wait expiry starts its fade from the waiting color")
update(0.15)
check(math.abs(nativeManaColor.r - 0.64) < 0.001, "Restricted mana fades between regen colors in combat")
update(0.2)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "Restricted fade finishes on the faster-regen color")
secretStats = false
event("UNIT_POWER_FREQUENT", "player", "MANA")
activeRegenAuras[29166] = {}
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Innervate fades the fill to the supercharged color")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
close(fillColor(UncBarsPower)[1], 0.55, "Spending mana during Innervate keeps the supercharged color")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Full mana still shows the supercharged color during Innervate")
activeRegenAuras[29166] = nil
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.1, "When supercharged regen ends at full mana, the bar fades to the full color")
activeRegenAuras[29166] = {}
event("UNIT_AURA", "player")
update(0.15)
close(fillColor(UncBarsPower)[1], 0.325, "Supercharged regen starting at full mana fades in")
update(0.2)
close(fillColor(UncBarsPower)[1], 0.55, "The fade finishes on the supercharged color")
secretStats = true
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(nativeManaColor and math.abs(nativeManaColor.r - 0.55) < 0.001,
    "In combat, full mana shows the supercharged color through the native curve")
activeRegenAuras[29166] = nil
event("UNIT_AURA", "player")
update(0.15)
check(math.abs(nativeManaColor.r - 0.325) < 0.001,
    "In combat, the end of supercharged regen at full mana fades rather than switching")
update(0.2)
check(math.abs(nativeManaColor.r - 0.1) < 0.001, "That fade finishes on the full color")
secretStats = false
activeRegenAuras[29166] = {}
event("UNIT_AURA", "player")
update(0.35)
mana = 600
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
activeRegenAuras[29166] = nil
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.9, "Innervate ending fades to the waiting color while time remains")
update(5)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.38, "After the wait the fill returns to the faster-regen color")
-- Supercharged regen can end with no event to redraw the bar.
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
activeRegenAuras[29166] = { expirationTime = now + 1 }
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "A timed Innervate shows the supercharged color")
activeRegenAuras[29166] = nil
update(1)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.1, "Innervate's expiry ends the supercharged color without an aura event")
castingRegen = baseRegen
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "A full casting regen rate shows the supercharged color")
castingRegen = 5
update(0.1)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.1, "A regen rate that drops without an event still ends the supercharged color")
mana = 600
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
-- In combat, Forever's aura lookup returns nothing even while the aura is present.
activeRegenAuras[29166] = { expirationTime = now + 10 }
event("UNIT_AURA", "player")
update(0.35)
combat = true
activeRegenAuras[29166] = nil
event("PLAYER_REGEN_DISABLED")
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "An Innervate known before the pull stays supercharged in combat")
update(10)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.38, "That Innervate still ends at its known expiry in combat")
event("UNIT_SPELLCAST_SENT", "player", "Tester", "inn1", 29166)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "inn1", 29166)
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Innervate cast on yourself in combat shows the supercharged color")
update(20)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.38, "A self-cast Innervate ends after its duration")
-- SENT names the current target even when Innervate lands on the player.
targetName, targetFriendly = "Starving Blisterpaw", false
event("UNIT_SPELLCAST_SENT", "player", "Starving Blisterpaw", "inn3", 29166)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "inn3", 29166)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Innervate sent with an enemy targeted self-casts and supercharges your bar")
update(20)
update(0.35)
-- Seen in game: with an enemy targeted, SENT names the player in full, and
-- Forever's two-part name may come back from UnitName in two values.
playerName, playerSecondName = "Aiori", "Kolahn"
targetName, targetFriendly = "Strigid Screecher", false
event("UNIT_SPELLCAST_SENT", "player", "Aiori Kolahn", "inn4", 29166)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "inn4", 29166)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Innervate sent at your full two-part name supercharges your bar")
update(20)
update(0.35)
event("UNIT_SPELLCAST_SENT", "player", "Aiori Smith", "inn5", 29166)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "inn5", 29166)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.9, "Innervate on someone sharing your first name does not count as yours")
update(5.1)
update(0.35)
playerName, playerSecondName = "Tester", nil
targetName, targetFriendly = "Other", true
event("UNIT_SPELLCAST_SENT", "player", "Other", "inn2", 29166)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "inn2", 29166)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.9, "Innervate cast on someone else starts your wait, not supercharged regen")
targetName, targetFriendly = nil, false
update(5)
combat = false
event("PLAYER_REGEN_ENABLED")
update(0.35)
event("UNIT_SPELLCAST_CHANNEL_START", "player", "evocation", 12051)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "Evocation uses the supercharged color")
event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "evocation", 12051)
update(0.35)
close(fillColor(UncBarsPower)[1], 0.38, "Ending Evocation fades back to the faster-regen color")
castingRegen = baseRegen
event("UNIT_AURA", "player")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.55, "A full casting regen rate counts as supercharged")
castingRegen = 5
event("UNIT_AURA", "player")
update(0.35)
ns.Command("regen")
check(UncBarsDB.manaRegen and not UncBarsDB.manaRegenColors, "/ub regen turns on the timer strip and turns off bar colors")
close(fillColor(UncBarsPower)[1], 0.38, "Leaving bar colors starts a fade from the current color")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.05, "Leaving bar colors fades back to the usual mana color")
UncBarsOption_manaRegen:SetChecked(false)
UncBarsOption_manaRegen.scripts.OnClick(UncBarsOption_manaRegen)
check(not UncBarsDB.manaRegen and not UncBarsDB.manaRegenColors, "Both displays can be off")
ns.SetOption("manaRegenColors", true)
ns.SetOption("manaRegenNumber", true)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "frostbolt", 116)
check(not UncBarsPower.regen.shown and not UncBarsPower.regenText.shown,
    "Bar colors show neither the strip nor its countdown")
ns.SetOption("manaRegenNumber", false)
update(5.1)
update(0.35)
ns.Command("test")
update(0.35)
close(fillColor(UncBarsPower)[1], 0.9, "Sample mode demonstrates the waiting color")
ns.Command("test")
-- Picker without opacity, cancel and reset.
UncBarsManaFastColor.scripts.OnClick(UncBarsManaFastColor)
check(ColorPickerFrame.shown and not ColorPickerFrame.info.hasOpacity and not ColorPickerFrame.info.opacityFunc,
    "Mana color pickers open the native picker without opacity")
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0.5, 0.8, 0.95
ColorPickerFrame.info.swatchFunc()
update(0.35)
close(fillColor(UncBarsPower)[2], 0.8, "Picker changes fade onto the mana fill")
close(UncBarsManaFastColor.swatch.color[2], 0.8, "Mana color swatch follows the selected color")
ColorPickerFrame.info.cancelFunc()
close(UncBarsDB.manaFastGreen, 0.68, "Cancel restores the previous mana color")
UncBarsManaWaitColorReset.scripts.OnClick(UncBarsManaWaitColorReset)
close(UncBarsDB.manaWaitRed, 0.05, "Reset color restores the default waiting color")
close(UncBarsDB.manaFullRed, 0.1, "Resetting one color leaves the others")
ColorPickerFrame:Hide()
ns.ApplyPreset("forever")
check(UncBarsDB.manaRegenColors and UncBarsDB.manaFullRed == 0.1, "Appearance presets preserve mana colors")
start(116)
check(UncBarsPower.cost.shown and UncBarsPower.cost.color[1] == 0.55 and UncBarsPower.cost.color[4] == 1,
    "Regen-state colors keep the same pale blue cost preview")
check(UncBarsPower.cost.level > UncBarsPower.activeFill.level and UncBarsPower.overlay.level > UncBarsPower.cost.level,
    "Cost preview stays above the fill and below the text")
stop()
secretStats = true
start(116)
update(0.35)
check(UncBarsPower.cost.shown and UncBarsPower.cost.color[1] == 0.55 and UncBarsPower.cost.color[4] == 1
    and nativeManaColor and math.abs(nativeManaColor.r - 0.38) < 0.001,
    "Starting a cast in combat keeps the after-wait color, with the overlay unchanged")
update(1.8)
event("UNIT_POWER_FREQUENT", "player", "MANA") -- a regen tick below full
check(math.abs(nativeManaColor.r - 0.38) < 0.001, "Most of a cast in combat keeps the after-wait color")
update(0.15)
update(0.15)
check(math.abs(nativeManaColor.r - 0.215) < 0.001,
    "Near the end of a cast in combat, the bar fades toward the waiting color")
update(0.15)
check(math.abs(nativeManaColor.r - 0.05) < 0.001 and UncBarsPower.cost.shown,
    "The fade finishes as the cast ends, before its mana is spent")
stop()
secretStats = false
login("DRUID", { manaRegenColors = true })
kind = 1
event("UNIT_DISPLAYPOWER", "player")
close(fillColor(UncBarsMana)[2], 0.68, "Shapeshifted druid mana row uses regen colors")
check(fillColor(UncBarsPower)[1] == 1 and fillColor(UncBarsPower)[2] == 0, "Rage keeps its native color")
close(fillColor(UncBarsEnergy)[2], 1, "Energy keeps its native color")
ns.Command("reset")
check(not UncBarsDB.manaRegenColors and UncBarsDB.manaFastGreen == 0.68, "Full reset restores mana color defaults")
-- Spending at full mana must not flash the after-wait color when the power
-- update arrives before the success event. Defaults: full == wait (green 0.25).
login("MAGE", { manaRegenColors = true })
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
start(116)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.1)
close(fillColor(UncBarsPower)[2], 0.25, "A cast's mana drop before its success event goes straight to the waiting color")
check(not UncBarsPower.cost.shown, "The paid cast no longer reserves mana")
stop()
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast1", 116)
update(0.35)
close(fillColor(UncBarsPower)[2], 0.25, "The later success event keeps the waiting color")
update(5)
update(0.35)
close(fillColor(UncBarsPower)[2], 0.68, "The wait started at the mana drop still expires normally")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
event("UNIT_SPELLCAST_SENT", "player", "target", "instant1", 116)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.1)
close(fillColor(UncBarsPower)[2], 0.25, "An instant's mana drop before its success event also skips the after-wait color")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "instant1", 116)
update(5.1)
update(0.35)
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[2], 0.68, "A mana drain without a pending spell does not start the wait")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
event("UNIT_SPELLCAST_SENT", "player", "target", "unknown", 999)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[2], 0.68, "A spell without a known mana cost does not count as a pending spend")
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
secretStats = true
event("UNIT_SPELLCAST_SENT", "player", "target", "instant2", 116)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(nativeManaColor and math.abs(nativeManaColor.g - 0.25) < 0.001,
    "In combat, an instant spent at full mana does not flash the after-wait color")
update(0.15)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "It fades from the full color it showed to the waiting color")
update(0.2)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "That fade finishes on the waiting color")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "instant2", 116)
update(0.35)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "The success event keeps the waiting color in combat")
update(5)
update(0.35)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "The combat wait expires to the after-wait color")
event("UNIT_SPELLCAST_SENT", "player", "target", "instant3", 116)
event("UNIT_SPELLCAST_FAILED", "player", "instant3", 116)
update(0.35)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "A failed instant returns to the after-wait color")
event("UNIT_SPELLCAST_SENT", "player", "target", "instant4", 116)
update(0.6)
update(0.35)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "A sent spell that never reports back stops counting as pending")
-- Spell 205 has a cast time: its SENT and START must not change the color.
event("UNIT_SPELLCAST_SENT", "player", "target", "cast5", 205)
start(205, "cast5")
update(0.1)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "Starting a cast-time spell in combat does not change the color")
update(1)
event("UNIT_POWER_FREQUENT", "player", "MANA") -- a regen tick below full
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "Casting in combat keeps the after-wait color")
update(1.15)
update(0.15)
check(math.abs(nativeManaColor.g - 0.465) < 0.001,
    "The color fades, rather than switches, as the cast nears its end")
update(0.15)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "The fade finishes before the cast spends mana")
stop()
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast5", 205)
update(0.35)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "The completed cast keeps the waiting color")
update(5.1)
update(0.35)
-- A distinct full color shows which color a spend from full fades from.
UncBarsDB.manaFullGreen = 0.5
mana = 1000
event("UNIT_POWER_FREQUENT", "player", "MANA") -- the last regen tick fills the bar
update(0.35)
check(math.abs(nativeManaColor.g - 0.5) < 0.001, "Full restricted mana shows the full color")
update(1.3)
update(1.3) -- no regen tick for 2.5 seconds: restricted mana counts as full
update(0.35)
check(math.abs(nativeManaColor.g - 0.5) < 0.001, "Counting mana as full leaves the shown color alone")
event("UNIT_SPELLCAST_SENT", "player", "target", "instant8", 116)
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(math.abs(nativeManaColor.g - 0.5) < 0.001,
    "In combat, a spend from full starts from the full color shown, not the after-wait color")
update(0.15)
check(math.abs(nativeManaColor.g - 0.375) < 0.001, "It fades from the full color to the waiting color")
update(0.2)
check(math.abs(nativeManaColor.g - 0.25) < 0.001, "That fade finishes on the waiting color")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "instant8", 116)
update(5.1)
event("UNIT_POWER_FREQUENT", "player", "MANA") -- regen ticks: mana is below full
update(0.35)
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "Below full, the after-wait color shows in combat")
event("UNIT_SPELLCAST_SENT", "player", "target", "instant9", 116)
event("UNIT_POWER_FREQUENT", "player", "MANA")
check(math.abs(nativeManaColor.g - 0.68) < 0.001, "A spend below full starts from the after-wait color shown")
update(0.15)
check(math.abs(nativeManaColor.g - 0.465) < 0.001, "and fades to the waiting color")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "instant9", 116)
update(5.1)
update(0.35)
UncBarsDB.manaFullGreen = 0.25
secretStats = false
-- Readable mana: the cast bar can end before its mana and success event arrive.
mana = 1000
event("UNIT_POWER_UPDATE", "player", "MANA")
update(0.35)
start(205, "cast6")
update(2.45)
stop()
mana = 900
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.1)
close(fillColor(UncBarsPower)[2], 0.25, "Mana spent just after the cast bar ends still starts the wait")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast6", 205)
update(5.1)
update(0.35)
close(fillColor(UncBarsPower)[2], 0.68, "That wait expires normally")
start(205, "cast7")
update(0.1)
close(fillColor(UncBarsPower)[2], 0.68, "Starting a cast below full keeps the after-wait color")
update(1)
stop("UNIT_SPELLCAST_INTERRUPTED")
stop()
mana = 850
event("UNIT_POWER_FREQUENT", "player", "MANA")
update(0.35)
close(fillColor(UncBarsPower)[2], 0.68, "A cast canceled partway does not turn a later mana drain into a spend")
login("MAGE", { manaRegen = true, manaRegenColors = true })
check(UncBarsDB.manaRegenColors and not UncBarsDB.manaRegen,
    "Settings saved with both displays on keep bar colors and turn off the strip")
ns.Command("")
check(UncBarsOptions.regenTab == "colors", "Mana regen opens on the bar colors sub-tab while colors are in use")
UncBarsOption_manaRegen:SetChecked(true)
UncBarsOption_manaRegen.scripts.OnClick(UncBarsOption_manaRegen)
check(UncBarsDB.manaRegen and not UncBarsDB.manaRegenColors and not UncBarsOption_manaRegenColors.checked
    and not UncBarsManaColorSection.shown, "Turning on the timer strip turns off bar colors and hides their pickers")
login("MAGE", { manaRegenColors = "bad", manaFastRed = 5, manaWaitGreen = -1 })
check(not UncBarsDB.manaRegenColors and UncBarsDB.manaFastRed == 1 and UncBarsDB.manaWaitGreen == 0,
    "Invalid saved mana colors are repaired and clamped")

-- A successful cast removes its cost preview at once; another spell does not.
login("MAGE")
check(UncBarsPower.spent == nil, "There is no separate spent-mana segment")
secretStats, secretCost = true, true
start(116, "cast1")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "unrelated", 999)
check(UncBarsPower.cost.shown, "An unrelated spell's success leaves the preview")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast1", 116)
check(not UncBarsPower.cost.shown, "The cast's own success removes the preview at once")
stop()
secretStats, secretCost = false, false

-- Combat can restrict spell costs. Like ManaCircle, only spells verified to
-- cost mana start the wait: learned from the spellbook and readable casts.
Enum.SpellBookSpellBank = { Player = 0 }
Enum.SpellBookItemType = { Spell = 1, Flyout = 2 }
local spellbook = { { spellID = 10, itemType = 1 }, { spellID = 4242, itemType = 2 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #spellbook } end,
    GetSpellBookItemInfo = function(slot, bank) assert(bank == 0); return spellbook[slot] end,
}
login("MAGE")
secretCost = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "book", 10)
check(UncBarsPower.regen.shown, "A spellbook spell learned at login starts the wait when its cost is restricted")
update(5.1)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "unseen", 205)
check(not UncBarsPower.regen.shown, "A restricted cost never seen readable does not start the wait")
secretCost = false
event("UNIT_SPELLCAST_SUCCEEDED", "player", "seen", 205)
check(UncBarsPower.regen.shown, "A readable mana cost starts the wait and is learned")
update(5.1)
secretCost = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "learned", 205)
check(UncBarsPower.regen.shown, "A learned spell keeps starting the wait when combat restricts its cost")
update(5.1)
secretCost = false
freeCast = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "clearcast", 205)
check(not UncBarsPower.regen.shown, "A readable free cast does not start the wait")
freeCast = false
secretCost = true
event("UNIT_SPELLCAST_SUCCEEDED", "player", "after-proc", 205)
check(UncBarsPower.regen.shown, "A free-cast proc does not unlearn a spell's mana cost")
update(5.1)
for _, weapon in ipairs({ 75, 5019, 6603, 3018, 2764 }) do
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "weapon", weapon)
end
check(not UncBarsPower.regen.shown, "Weapon attacks never start the wait")
secretCost = false
event("UNIT_SPELLCAST_SUCCEEDED", "player", "nonmana", 998)
check(not UncBarsPower.regen.shown, "Spells with only non-mana costs do not start the wait")
C_SpellBook = nil

-- Blizzard reserves mana while its ground-targeting circle is up, before any
-- cast/channel event. Polling also handles cursor events arriving too early.
login("MAGE", { manaRegenColors = true })
check(UncBarsEvents.events.CURRENT_SPELL_CAST_CHANGED and UncBarsEvents.events.CURSOR_CHANGED,
    "Pending targeting spells are watched alongside ordinary casts")
event("CURSOR_CHANGED")
targetingSpell = 10
update(0.05)
check(UncBarsPower.cost.shown and UncBarsPower.cost.value == 300,
    "Blizzard targeting shows its native upfront mana cost without a cast bar")
close(costSpan(), 78, "Blizzard's targeting preview reserves the correct fraction of mana")
check(UncBarsPower.text.text == "600", "Targeting keeps the actual mana number")
update(6)
close(fillColor(UncBarsPower)[2], 0.68, "Holding Blizzard targeting never starts the regen wait")
check(UncBarsPower.cost.color[1] > fillColor(UncBarsPower)[1]
    and UncBarsPower.cost.color[2] > fillColor(UncBarsPower)[2],
    "Targeting costs remain distinguishable from the default full-regen fill")
ns.SetColor("manaFast", 0.9, 0.2, 0.1)
update(0.35)
close(UncBarsPower.cost.color[2], 0.78, "Custom regen colors do not change the queued mana color")
targetingSpell = 116
event("CURRENT_SPELL_CAST_CHANGED")
close(costSpan(), 6.5, "Switching the selected spell uses its exact cost")
targetingSpell = 10
event("CURSOR_CHANGED")
freeCast = true
event("UNIT_AURA", "player")
check(not UncBarsPower.cost.shown, "A free-cast modifier removes the targeting cost")
freeCast = false
event("UNIT_AURA", "player")
check(UncBarsPower.cost.shown, "Ending the free-cast modifier restores the targeting cost")
ns.SetOption("queue", false)
check(not UncBarsPower.cost.shown, "The mana preview toggle also controls targeting costs")
ns.SetOption("queue", true)
check(UncBarsPower.cost.shown, "Reenabling the preview picks up the current targeting spell")
targetingSpell = nil
update(0.05)
check(not UncBarsPower.cost.shown, "Canceling the targeting cursor clears its cost without another event")
targetingSpell = 10
event("CURSOR_CHANGED")
targetingSpell = nil
event("UNIT_SPELLCAST_CHANNEL_START", "player", "blizzard", 10)
check(not UncBarsPower.cost.shown, "Starting Blizzard's paid channel clears the targeting preview")
event("UNIT_SPELLCAST_CHANNEL_STOP", "player", "blizzard", 10)
targetingSpell = 10
combat, secretStats, secretCost = true, true, true
event("CURSOR_CHANGED")
check(UncBarsPower.cost.shown and rawequal(UncBarsPower.cost.value, secret)
    and rawequal(UncBarsPower.cost.maximum, secret), "Restricted targeting costs and mana reach native setters")
secretTargetSpell = true
event("CURSOR_CHANGED")
check(not UncBarsPower.cost.shown, "An unreadable targeting ID is omitted without comparisons")
secretTargetSpell, secretStats, secretCost, combat = false, false, false, false
targetingSpell = 999
event("CURSOR_CHANGED")
check(not UncBarsPower.cost.shown, "An unknown targeting cost has no preview")
targetingSpell = 998
event("CURSOR_CHANGED")
check(not UncBarsPower.cost.shown, "A targeting spell with no mana cost has no preview")
targetingSpell = 10
dead = true
event("PLAYER_DEAD")
update(0.1)
check(not UncBarsPower.cost.shown, "Death clears targeting costs even while the cursor is stale")
dead, targetingSpell = false, nil
event("PLAYER_ALIVE")
targetingSpell = 10
event("CURSOR_CHANGED")
event("PLAYER_LEAVING_WORLD")
update(0.1)
check(not UncBarsPower.cost.shown, "Leaving the world clears a stale targeting cursor")
targetingSpell = nil
event("PLAYER_ENTERING_WORLD")
login("DRUID")
kind, targetingSpell = 1, 10
event("UNIT_DISPLAYPOWER", "player")
check(UncBarsMana.cost.shown and not UncBarsPower.cost.shown and not UncBarsEnergy.cost.shown,
    "Targeting cost follows the druid mana row without reserving rage or energy")
targetingSpell = nil
update(0.05)
check(not UncBarsMana.cost.shown, "Canceling targeting clears the druid mana row")
print(checks .. " simulated checks passed")

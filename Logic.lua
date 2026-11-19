local _, ns = ...
local L = {}
ns.Logic = L

function L.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Mixes two {r, g, b} colors; progress 0 returns from, 1 returns to.
function L.BlendColor(from, to, progress)
    local t = L.Clamp(progress, 0, 1)
    return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t
end

function L.CostSegment(current, maximum, cost)
    if maximum <= 0 or cost <= 0 or current <= 0 then return end
    local right = L.Clamp(current / maximum, 0, 1)
    return L.Clamp((current - cost) / maximum, 0, right), right
end

function L.HealSegment(current, maximum, amount)
    if maximum <= 0 or amount <= 0 or current <= 0 or current >= maximum then return end
    local left = L.Clamp(current / maximum, 0, 1)
    return left, L.Clamp((current + amount) / maximum, left, 1)
end

function L.AbsorbSegment(current, maximum, amount)
    if maximum <= 0 or amount <= 0 or current <= 0 then return end
    -- Fold overflow back into the bar so a shield remains visible at full HP.
    local width = L.Clamp(amount / maximum, 0, 1)
    local right = L.Clamp((current + amount) / maximum, 0, 1)
    return math.max(0, right - width), right
end

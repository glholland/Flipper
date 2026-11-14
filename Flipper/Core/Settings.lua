-- Every user setting in one list, read and written in one place. The minimap menu, the
-- options page (Esc > Options > AddOns > Flipper), the window's checkbox and the slash
-- commands all go through Get/Set, so they never disagree. No client calls: testable.
local _, ns = ...
local Settings = {}
ns.Settings = Settings

local function minimap()
    FlipperDB.minimap = FlipperDB.minimap or {}
    return FlipperDB.minimap
end

-- kind: "toggle" (boolean), "money" (copper), "percent" (0-1).
Settings.LIST = {
    {key = "showMinimap", kind = "toggle", label = "Show minimap button",
        tip = "The addon menu (top right of the minimap) and /flip minimap still reach Flipper when it's hidden.",
        get = function() return not minimap().hide end,
        set = function(value) minimap().hide = not value end},
    {key = "lockMinimap", kind = "toggle", label = "Lock minimap button",
        tip = "Stops the button being dragged around the minimap.",
        get = function() return minimap().lock and true or false end,
        set = function(value) minimap().lock = value or nil end},
    {key = "tooltip", kind = "toggle", label = "Flipper lines in item tooltips",
        tip = "Verdict, recipe uses and disenchant value on every item tooltip. Hold Shift for prices."},
    {key = "autoQuickScan", kind = "toggle", label = "Quick scan when the auction house opens",
        tip = "Skipped when Auctionator autoscans or prices are under 5 minutes old."},
    {key = "minFlipProfit", kind = "money", label = "Smallest profit worth showing (per item)",
        tip = "Flips, vendor buys and deals earning less than this per item are hidden.",
        presets = {1, 10, 100, 1000, 10000}, min = 1, max = 100000000},
    {key = "dealRatio", kind = "percent", label = "Deals: listed at or below this share of the usual price",
        tip = "Lower finds fewer, bigger bargains.",
        presets = {0.5, 0.6, 0.7, 0.8, 0.9}, min = 0.3, max = 0.95},
}
local BY_KEY = {}
for _, setting in ipairs(Settings.LIST) do BY_KEY[setting.key] = setting end
Settings.BY_KEY = BY_KEY

function Settings.Get(key)
    local setting = BY_KEY[key]
    if not setting or not FlipperDB then return nil end
    if setting.get then return setting.get() end
    local value = FlipperDB[key]
    if value == nil then value = ns.DEFAULTS[key] end
    return value
end

-- Clamps and stores a value. Returns the value stored, or nil if it was refused.
function Settings.Set(key, value)
    local setting = BY_KEY[key]
    if not setting or not FlipperDB then return nil end
    if setting.kind == "toggle" then
        value = value and true or false
    else
        value = tonumber(value)
        if not value or value ~= value then return nil end
        value = math.max(setting.min, math.min(setting.max, value))
        if setting.kind == "money" then value = math.floor(value) end
    end
    if setting.set then setting.set(value) else FlipperDB[key] = value end
    if Settings.OnChanged then Settings.OnChanged(key, value) end
    return value
end

function Settings.Toggle(key) return Settings.Set(key, not Settings.Get(key)) end

-- How a value reads in menus: "10c", "1g", "70%".
function Settings.Format(key, value)
    local setting = BY_KEY[key]
    if value == nil then value = Settings.Get(key) end
    if not setting then return tostring(value) end
    if setting.kind == "money" then return ns.Money.Format(value) end
    if setting.kind == "percent" then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
    return value and "on" or "off"
end

------------------------------------------------------------------------
-- Minimap rim placement (for the button Flipper draws when LibDBIcon isn't loaded).
-- Angles are degrees, 0 = right, counter-clockwise, like LibDBIcon's minimapPos, so a
-- position saved by either kind of button means the same spot.
------------------------------------------------------------------------

function Settings.AngleFrom(dx, dy)
    return math.deg(math.atan2(dy, dx)) % 360
end

-- Offset from the minimap's centre. radius = half the minimap's width plus the overhang.
-- A square minimap pushes the button out to the edge of the square.
function Settings.RimOffset(angle, radius, shape)
    local a = math.rad(angle or 225)
    local x, y = math.cos(a), math.sin(a)
    if shape == "SQUARE" then
        local diagonal = math.sqrt(2) * radius
        x = math.max(-radius, math.min(radius, x * diagonal))
        y = math.max(-radius, math.min(radius, y * diagonal))
        return x, y
    end
    return x * radius, y * radius
end

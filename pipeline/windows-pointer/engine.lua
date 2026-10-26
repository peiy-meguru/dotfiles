-- windows_pointer::Engine — Lua 5.4 port.
--
-- Faithful translation of the upstream C++ engine
-- (github.com/junaga/windows-pointer-linux, src/engine.cpp, BSD-3-Clause).
--
-- Integer semantics that must be preserved exactly:
--   C++ `/`  truncates toward zero   -> tdiv()
--   C++ `%`  takes the dividend sign -> tmod()
--   C++ `>>` on int64 is arithmetic  -> sar()  (== floor division)
--   C++ `<<` on int64 is a multiply  -> shl()  (Lua `<<` is logical, wrong for negatives)
--
-- Lua 5.4 integers are 64-bit signed with wraparound, matching int64_t.
--
-- SANDBOX CONSTRAINT: libinput's Lua plugin sandbox exposes only
--   assert error ipairs next pairs tonumber pcall select print tostring type
--   xpcall table string math _VERSION
-- There is no setmetatable, rawget, io, os, require, or package. This module
-- therefore uses no metatables: methods are plain fields attached to each
-- instance, so `engine:apply(...)` resolves without an __index lookup.

local M = {}

local Q16             = 1 << 16
local MIN_DISPLAY_DPI = 96
local MAX_DISPLAY_DPI = 480
local INT32_MIN       = -2147483648
local INT32_MAX       = 2147483647

local function tdiv(a, b)
    local q = a // b
    if a % b ~= 0 and ((a < 0) ~= (b < 0)) then
        q = q + 1
    end
    return q
end

local function tmod(a, b)
    return a - tdiv(a, b) * b
end

local function sar(a, n)
    return a // (1 << n)
end

local function shl(a, n)
    return a * (1 << n)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function narrow(v)
    return clamp(v, INT32_MIN, INT32_MAX)
end

local function multiply_q16(left, right)
    local whole      = tdiv(left, Q16) * right
    local fractional = tmod(left, Q16) * right
    local remainder  = tdiv(fractional, Q16)

    -- Windows uses an arithmetic right shift here; C++ division truncates
    -- toward zero, so negative fractions need one last nudge toward -inf.
    if fractional < 0 and tmod(fractional, Q16) ~= 0 then
        remainder = remainder - 1
    end

    return whole + remainder
end

local SMOOTH_MOUSE_X_CURVE = { 0x0, 0x6e15, 0x14000, 0x3dc29, 0x280000 }
local SMOOTH_MOUSE_Y_CURVE = { 0x0, 0x111fd, 0x42400, 0x12fc00, 0x1bbc000 }

-- Fixed-point gains for the Windows 11 1-20 speed setting when EPP is off.
local LINEAR_GAINS_Q16 = {
    2048,   -- 0.03125
    4096,   -- 0.0625
    8192,   -- 0.125
    16384,  -- 0.25
    24576,  -- 0.375
    32768,  -- 0.5
    40960,  -- 0.625
    49152,  -- 0.75
    57344,  -- 0.875
    65536,  -- 1.0
    81920,  -- 1.25
    98304,  -- 1.5
    114688, -- 1.75
    131072, -- 2.0
    147456, -- 2.25
    163840, -- 2.5
    180224, -- 2.75
    196608, -- 3.0
    212992, -- 3.25
    229376, -- 3.5
}

local Engine = {}

function Engine.configure(self, pointerSpeed, enhancePointerPrecision)
    if pointerSpeed < 1 or pointerSpeed > 20 then
        error("pointer speed must be between 1 and 20")
    end
    local epp = enhancePointerPrecision and true or false
    if pointerSpeed == self.speed and epp == self.epp then
        return
    end
    self.speed = pointerSpeed
    self.epp   = epp
    self.ballisticsDpi = 0
end

function Engine.reset(self)
    self.enhancedXRemainder = 0
    self.enhancedYRemainder = 0
    self.previousSegment    = 0
    self.linearXRemainder   = 0
    self.linearYRemainder   = 0
end

function Engine.buildCurve(self, displayDpi)
    displayDpi = clamp(displayDpi, MIN_DISPLAY_DPI, MAX_DISPLAY_DPI)

    local dpiFactor   = tdiv(shl(displayDpi, 16), 0x78)
    local speedFactor = tdiv(shl(self.speed, 16), 10)
    local scaledY     = { 0, 0, 0, 0, 0 }

    for i = 1, 5 do
        self.bx[i] = sar(SMOOTH_MOUSE_X_CURVE[i] * 0x38000, 16)
        local dpiScaledY = sar(dpiFactor * SMOOTH_MOUSE_Y_CURVE[i], 16)
        scaledY[i] = sar(dpiScaledY * speedFactor, 16)
    end

    for i = 1, 4 do
        local dx = self.bx[i + 1] - self.bx[i]
        local dy = scaledY[i + 1] - scaledY[i]

        self.slopes[i] = dx == 0 and 0 or tdiv(shl(dy, 16), dx)
        self.intercepts[i] = scaledY[i] - sar(self.slopes[i] * self.bx[i], 16)
    end

    self.ballisticsDpi = displayDpi
end

function Engine.applyEnhanced(self, x, y, displayDpi)
    if x == 0 and y == 0 then
        return 0, 0
    end

    displayDpi = clamp(displayDpi, MIN_DISPLAY_DPI, MAX_DISPLAY_DPI)
    if displayDpi ~= self.ballisticsDpi then
        Engine.buildCurve(self, displayDpi)
    end

    local xFixed = x * Q16
    local yFixed = y * Q16
    local absX   = xFixed >= 0 and xFixed or -xFixed
    local absY   = yFixed >= 0 and yFixed or -yFixed
    local minAbs = absX < absY and absX or absY
    local maxAbs = absX < absY and absY or absX
    local distance = maxAbs + sar(minAbs, 1)

    -- segment is a 0-based C++ curve index; Lua arrays are 1-based, so every
    -- lookup below uses segment + 1.
    local segment = 3
    for i = 0, 2 do
        if distance <= self.bx[i + 2] then
            segment = i
            break
        end
    end

    local gain = self.slopes[segment + 1]
    if distance ~= 0 then
        gain = gain + tdiv(shl(self.intercepts[segment + 1], 16), distance)
    end

    if self.previousSegment < segment then
        local previousGain = self.slopes[self.previousSegment + 1]
        if distance ~= 0 then
            previousGain = previousGain + tdiv(shl(self.intercepts[self.previousSegment + 1], 16), distance)
        end
        gain = sar(gain + previousGain, 1)
    end

    self.previousSegment = segment

    local xTotal = multiply_q16(xFixed, gain) + self.enhancedXRemainder
    local yTotal = multiply_q16(yFixed, gain) + self.enhancedYRemainder
    local outX   = tdiv(xTotal, Q16)
    local outY   = tdiv(yTotal, Q16)

    self.enhancedXRemainder = tmod(xTotal, Q16)
    self.enhancedYRemainder = tmod(yTotal, Q16)

    return narrow(outX), narrow(outY)
end

function Engine.applyLinear(self, x, y)
    local gain   = LINEAR_GAINS_Q16[self.speed]
    local xTotal = x * gain + self.linearXRemainder
    local yTotal = y * gain + self.linearYRemainder
    local outX   = tdiv(xTotal, Q16)
    local outY   = tdiv(yTotal, Q16)

    self.linearXRemainder = tmod(xTotal, Q16)
    self.linearYRemainder = tmod(yTotal, Q16)

    return narrow(outX), narrow(outY)
end

function Engine.apply(self, x, y, displayDpi)
    displayDpi = displayDpi or MIN_DISPLAY_DPI
    if self.epp then
        return Engine.applyEnhanced(self, x, y, displayDpi)
    end
    return Engine.applyLinear(self, x, y)
end

function M.new(pointerSpeed, enhancePointerPrecision)
    pointerSpeed = pointerSpeed or 10
    if enhancePointerPrecision == nil then enhancePointerPrecision = true end
    if pointerSpeed < 1 or pointerSpeed > 20 then
        error("pointer speed must be between 1 and 20")
    end

    -- Methods are attached directly to the instance: no metatable, no __index.
    local self = {
        speed = pointerSpeed,
        epp   = enhancePointerPrecision and true or false,

        -- Ballistics, 1-based: bx[1..5], slopes[1..4], intercepts[1..4]
        bx         = { 0, 0, 0, 0, 0 },
        slopes     = { 0, 0, 0, 0 },
        intercepts = { 0, 0, 0, 0 },
        ballisticsDpi = 0,

        enhancedXRemainder = 0,
        enhancedYRemainder = 0,
        previousSegment    = 0,

        linearXRemainder = 0,
        linearYRemainder = 0,

        configure     = Engine.configure,
        reset         = Engine.reset,
        buildCurve    = Engine.buildCurve,
        applyEnhanced = Engine.applyEnhanced,
        applyLinear   = Engine.applyLinear,
        apply         = Engine.apply,
    }

    return self
end

-- round(scale * 96), clamped to the audited Windows range 96-480 DPI.
function M.displayDpiFromScale(scale)
    if type(scale) ~= "number" or scale ~= scale
        or scale == math.huge or scale == -math.huge or scale <= 1.0 then
        return MIN_DISPLAY_DPI
    end
    local bounded = math.min(scale, MAX_DISPLAY_DPI / MIN_DISPLAY_DPI)
    local v = bounded * MIN_DISPLAY_DPI
    -- lround: round half away from zero
    local r = v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
    return math.floor(r)
end

M.Engine = Engine
M.MIN_DISPLAY_DPI = MIN_DISPLAY_DPI
M.MAX_DISPLAY_DPI = MAX_DISPLAY_DPI

return M

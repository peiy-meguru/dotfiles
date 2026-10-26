---@diagnostic disable: undefined-global
-- `libinput` and `evdev` are provided by the libinput plugin sandbox; `M` is
-- prepended by build.py from engine/engine.lua. None are defined in this file.
--
-- Adapter body for the niri/libinput Lua plugin.
--
-- Prepended by build.py with engine/engine.lua, so the `M` table (the ported
-- windows_pointer::Engine) is already in scope. This file is not a standalone
-- chunk.
--
-- Adapter contract (docs/architecture.md):
--   1. reject or pass through non-physical / absolute / unsupported input
--   2. preserve the original X/Y report as signed integers
--   3. select the display containing the cursor and derive its effective DPI
--   4. call the engine associated with that logical desktop pointer
--   5. replace only the normal accelerated desktop delta
--   6. continue through the platform's ordinary event path
--
-- Known deviation from the upstream contract: a libinput plugin sits *below*
-- libinput, so the deltas it rewrites are also the ones libinput reports as
-- "unaccelerated" to zwp_relative_pointer_v1 clients. Games and pointer-locked
-- applications therefore receive the Windows curve too, whereas on Windows
-- Raw Input bypasses the desktop pointer entirely. Consequence: with EPP on,
-- games get the Windows *desktop* curve; with EPP off (speed 10/20) the output
-- is a constant 1:1, which is exactly what Windows Raw Input would have given.
-- The Hyprland adapter does not have this deviation because it hooks above
-- libinput; a niri patch would be needed to match it exactly.

--------------------------------------------------------------------------
-- configuration
--------------------------------------------------------------------------

-- Windows 11 defaults: 10/20 with Enhance pointer precision on.
local POINTER_SPEED = 10
local ENHANCE_POINTER_PRECISION = true

-- Effective DPI of the display under the cursor.
-- niri exposes no cursor-to-output query to libinput plugins, so this is baked
-- in at build time. 96 == 100% scale, which is what this machine runs.
-- If you change the output scale, rebuild with the new value:
--   displayDpiFromScale(scale) == round(scale * 96), clamped to 96..480
local DISPLAY_DPI = 96

-- Only touch the physical mouse we were asked to fix. A libinput plugin sees
-- every device on the seat, including the virtual pointers other tools create.
local MATCH_VID = 0x04f3 -- Elan Microelectronics (X23 Pro 2.4G receiver)
local MATCH_PID = 0x026f

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------

local function toint(value)
    -- Avoid math.type/math.tointeger: the sandbox's `math` table is not
    -- guaranteed to expose them, and a missing global here would abort the
    -- whole plugin at load time.
    if type(value) ~= "number" then
        return nil
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return nil -- NaN or infinity
    end
    if value % 1 ~= 0 then
        return nil -- fractional report: cannot be represented faithfully
    end
    return math.floor(value)
end

--------------------------------------------------------------------------
-- plugin registration (must be the first libinput call)
--------------------------------------------------------------------------

local version = libinput:register({ 1 })

libinput:log_info(string.format(
    "windows-pointer: loaded (plugin api v%d) speed=%d/20 epp=%s dpi=%d",
    version, POINTER_SPEED, tostring(ENHANCE_POINTER_PRECISION), DISPLAY_DPI))

-- One engine per logical desktop pointer. Windows keeps segment history and
-- subpixel remainders in session input-manager state, shared by every physical
-- mouse driving that cursor, so this is deliberately not per-device.
local engine = M.new(POINTER_SPEED, ENHANCE_POINTER_PRECISION)

--------------------------------------------------------------------------
-- device classification
--------------------------------------------------------------------------

local function is_target_mouse(device)
    local info = device:info()
    if info.vid ~= MATCH_VID or info.pid ~= MATCH_PID then
        return false
    end

    local usages = device:usages()
    if not (usages[evdev.REL_X] and usages[evdev.REL_Y]) then
        return false
    end

    -- Absolute axes mean a touchpad, tablet, or touchscreen wearing a mouse
    -- costume. Those have their own acceleration and must pass through.
    if usages[evdev.ABS_X] or usages[evdev.ABS_Y] then
        return false
    end

    return true
end

--------------------------------------------------------------------------
-- frame transform
--------------------------------------------------------------------------

local function transform(frame)
    -- Windows receives one two-axis integer report. Split X and Y into
    -- separate calls and the gain is selected from the wrong distance.
    local rawX, rawY = 0, 0
    local hasX, hasY = false, false

    for index = 1, #frame do
        local event = frame[index]
        if event.usage == evdev.REL_X then
            local value = toint(event.value)
            if value == nil then
                return nil -- malformed report: pass through untouched
            end
            rawX, hasX = value, true
        elseif event.usage == evdev.REL_Y then
            local value = toint(event.value)
            if value == nil then
                return nil
            end
            rawY, hasY = value, true
        end
    end

    if not hasX and not hasY then
        return nil -- not a motion frame
    end

    local outX, outY = engine:apply(rawX, rawY, DISPLAY_DPI)

    local out = {}
    for index = 1, #frame do
        local event = frame[index]
        if event.usage == evdev.REL_X then
            out[#out + 1] = { usage = evdev.REL_X, value = outX }
        elseif event.usage == evdev.REL_Y then
            out[#out + 1] = { usage = evdev.REL_Y, value = outY }
        else
            out[#out + 1] = event
        end
    end

    -- No synthetic axis is needed for an axis absent from the frame: the
    -- engine's remainder is always |r| < 2^16, so a zero input on that axis
    -- can only ever yield a zero output. Verified in conformance/adapter_test.lua.
    return out
end

--------------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------------

libinput:connect("new-evdev-device", function(device)
    if not is_target_mouse(device) then
        return
    end

    local info = device:info()
    libinput:log_info(string.format(
        "windows-pointer: attached to %q (vid=0x%04x pid=0x%04x)",
        device:name(), info.vid, info.pid))

    device:connect("evdev-frame", function(_, frame)
        -- An input path must never take the seat down. On any unexpected
        -- failure, hand the frame back unmodified.
        local ok, result = pcall(transform, frame)
        if not ok then
            libinput:log_error("windows-pointer: transform failed: " .. tostring(result))
            return nil
        end
        return result
    end)

    device:connect("device-removed", function(dev)
        libinput:log_info("windows-pointer: detached from " .. tostring(dev:name()))
        -- Session state belongs to the pointer, not the hardware, but a
        -- removed device means the seat is changing shape. Start clean.
        engine:reset()
    end)
end)

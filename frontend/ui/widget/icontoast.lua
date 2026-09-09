--[[--
Widget that displays a small, transient, input-transparent icon in the
top left corner of the screen.

A discreet alternative to text popups for transient status updates
(e.g., Wi-Fi connect/disconnect): the icon is stacked on top of
everything (toast), lets input fall through, and vanishes by itself
after an optional timeout.

    local IconToast = require("ui/widget/icontoast")
    IconToast:show("wifi.open.50")          -- persists until hidden
    IconToast:show("wifi.open.100", 3)      -- hides itself after 3s
    IconToast:hide()
]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

-- Icon size and distance from the top left corner, in unscaled pixels
local ICON_SIZE = 32
local ICON_MARGIN = 4

local IconToast = InputContainer:extend{
    toast = true, -- stacked on top, and transparent to input
    -- Input falls through to whatever is underneath, so don't degrade it
    disable_double_tap = false,
    icon = nil,
    timeout = nil, -- in seconds; nil: hides only when replaced or on hide()
    _timeout_func = nil,
    -- Class member: the currently shown instance (so a new toast replaces it)
    _current = nil,
}

function IconToast:init()
    self.frame = FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.small,
        IconWidget:new{
            icon = self.icon,
            width = Screen:scaleBySize(ICON_SIZE),
            height = Screen:scaleBySize(ICON_SIZE),
            alpha = true, -- keep the icon's transparency
        },
    }
    self[1] = self.frame
end

function IconToast:onShow()
    if self.timeout then
        self._timeout_func = function()
            self._timeout_func = nil
            if IconToast._current == self then
                IconToast:hide()
            end
        end
        UIManager:scheduleIn(self.timeout, self._timeout_func)
    end
end

function IconToast:onCloseWidget()
    -- If we were closed early, drop the scheduled timeout
    if self._timeout_func then
        UIManager:unschedule(self._timeout_func)
        self._timeout_func = nil
    end
end

-- Show an icon toast, replacing any previously shown one.
-- icon_name: icon name, as consumed by IconWidget (nil: only hide)
-- timeout_s: in seconds; nil: hide only when replaced or via hide()
-- x: optional horizontal position override (unscaled pixels);
--    nil: the default top left corner margin
function IconToast:show(icon_name, timeout_s, x)
    IconToast:hide()
    if not icon_name then
        return
    end
    local toast = IconToast:new{
        icon = icon_name,
        timeout = timeout_s,
    }
    IconToast._current = toast
    UIManager:show(toast, "ui", nil, x or Screen:scaleBySize(ICON_MARGIN), Screen:scaleBySize(ICON_MARGIN))
end

function IconToast:hide()
    local current = IconToast._current
    if current then
        IconToast._current = nil
        UIManager:close(current, "ui")
    end
end

return IconToast

local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local ReaderFlipping = WidgetContainer:extend{
    -- Icons to show during crengine partial rerendering automation
    rolling_rendering_state_icons = {
        PARTIALLY_RERENDERED = "cre.render.partial",
        FULL_RENDERING_IN_BACKGROUND = "cre.render.working",
        FULL_RENDERING_READY = "cre.render.ready",
        RELOADING_DOCUMENT = "cre.render.reload",
    },
}

function ReaderFlipping:init()
    local icon_size = Screen:scaleBySize(32)
    self.flipping_widget = IconWidget:new{
        icon = "book.opened",
        width = icon_size,
        height = icon_size,
    }
    self.bookmark_flipping_widget = IconWidget:new{
        icon = "bookmark",
        width = icon_size,
        height = icon_size,
    }
    self.long_hold_widget = IconWidget:new{
        icon = "appbar.pokeball",
        width = icon_size,
        height = icon_size,
        alpha = true,
    }
    icon_size = Screen:scaleBySize(36)
    self.select_mode_widget = IconWidget:new{
        icon = "texture-box",
        width = icon_size,
        height = icon_size,
        alpha = true,
    }
    self[1] = LeftContainer:new{
        dimen = Geom:new{w = Screen:getWidth(), h = self.flipping_widget:getSize().h},
        self.flipping_widget,
    }
end

function ReaderFlipping:resetLayout()
    -- NOTE: LeftContainer aligns to the left of its *own* width (and will handle RTL mirroring, so we can't cheat)...
    self[1].dimen.w = Screen:getWidth()
end

-- Wi-Fi status icon (discreet connect feedback): shown below the other
-- icons when one of them is active, and refreshed with a partial "ui"
-- repaint of the corner region, like the rerendering state icons.
function ReaderFlipping:getRefreshRegion()
    -- We can't use self.dimen because of the width/height quirks of Left/RightContainer, so use the IconWidget's...
    -- Also cover the Wi-Fi icon's row, whether it's the one shown, or when it
    -- sits below ours, so state changes on either side erase and repaint
    -- each other cleanly instead of leaving a ghost behind until the next repaint.
    local w = math.max(self[1][1]:getSize().w, Screen:scaleBySize(32))
    local h = self[1].dimen.h + Size.span.horizontal_default + Screen:scaleBySize(32)
    return Geom:new{x = 0, y = 0, w = w, h = h}
end

function ReaderFlipping:setWifiStateIcon(icon_name)
    if icon_name then
        if not self.wifi_state_widget or self.wifi_state_widget.icon ~= icon_name then
            self.wifi_state_widget = IconWidget:new{
                icon = icon_name,
                width = Screen:scaleBySize(32),
                height = Screen:scaleBySize(32),
                alpha = true, -- so bits of text stay visible underneath, like the other icons
            }
        end
    else
        self.wifi_state_widget = nil
    end
    UIManager:setDirty(self.view.dialog, "ui", self:getRefreshRegion())
end

function ReaderFlipping:getRollingRenderingStateIconWidget()
    if not self.rolling_rendering_state_widgets then
        self.rolling_rendering_state_widgets = {}
    end
    local widget = self.rolling_rendering_state_widgets[self.ui.rolling.rendering_state]
    if widget == nil then    -- not met yet
        local icon_size = Screen:scaleBySize(32)
        for k, v in pairs(self.ui.rolling.RENDERING_STATE) do -- known states
            if v == self.ui.rolling.rendering_state then -- current state
                local icon = self.rolling_rendering_state_icons[k] -- our icon (or none) for this state
                if icon then
                    self.rolling_rendering_state_widgets[v] = IconWidget:new{
                        icon = icon,
                        width = icon_size,
                        height = icon_size,
                        alpha = not self.ui.rolling.cre_top_bar_enabled,
                            -- if top status bar enabled, have them opaque, as they
                            -- will be displayed over the bar
                            -- otherwise, keep their alpha so some bits of text is
                            -- visible if displayed over the text when small margins
                    }
                else
                    self.rolling_rendering_state_widgets[v] = false
                end
                break
            end
        end
        widget = self.rolling_rendering_state_widgets[self.ui.rolling.rendering_state]
    end
    return widget or nil -- return nil if cached widget is false
end

function ReaderFlipping:onSetStatusLine()
    -- Reset these widgets: we want new ones with proper alpha/opaque
    self.rolling_rendering_state_widgets = nil
end

function ReaderFlipping:paintTo(bb, x, y)
    local widget
    if self.ui.paging and self.view.flipping_visible then
        -- pdf page flipping or bookmark browsing mode
        widget = self.ui.paging.bookmark_flipping_mode and self.bookmark_flipping_widget or self.flipping_widget
    elseif self.ui.highlight.select_mode then
        -- highlight select mode
        widget = self.select_mode_widget
    elseif self.ui.highlight.long_hold_reached then
        widget = self.long_hold_widget
    elseif self.ui.rolling and self.ui.rolling.rendering_state then
        -- epub rerendering
        widget = self:getRollingRenderingStateIconWidget()
    end
    if widget then
        if self[1][1] ~= widget then
            self[1][1] = widget
        end
        WidgetContainer.paintTo(self, bb, x, y)
    end
    if self.wifi_state_widget then
        -- Below the other icon when one is shown, at the top left otherwise
        self.wifi_state_widget:paintTo(bb, x, y + (widget and self[1][1]:getSize().h + Size.span.horizontal_default or 0))
    end
end

return ReaderFlipping

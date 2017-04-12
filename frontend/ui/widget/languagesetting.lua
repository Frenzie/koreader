--[[--
Network setting widget.

Example:

    local network_list = {
        {
            ssid = "foo",
            signal_level = -58,
            flags = "[WPA2-PSK-CCMP][ESS]",
            signal_quality = 84,
            password = "123abc",
            connected = true,
        },
        {
            ssid = "bar",
            signal_level = -258,
            signal_quality = 44,
            flags = "[WEP][ESS]",
        },
    }
    UIManager:show(require("ui/widget/LanguageSetting"):new{
        network_list = network_list,
        connect_callback = function()
            -- connect_callback will be called when an connect/disconnect
            -- attempt has been made. you can update UI widgets in the
            -- callback.
        end,
    })

]]

local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local ListView = require("ui/widget/listview")
local ImageWidget = require("ui/widget/imagewidget")
local Widget = require("ui/widget/widget")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = Device.screen
local Font = require("ui/font")
local T = require("ffi/util").template
local _ = require("gettext")

local Language = require("ui/language")

local MinimalPaginator = Widget:new{
    width = nil,
    height = nil,
    progress = nil,
}

function MinimalPaginator:getSize()
    return Geom:new{w = self.width, h = self.height}
end

function MinimalPaginator:paintTo(bb, x, y)
    self.dimen = self:getSize()
    self.dimen.x, self.dimen.y = x, y
    -- paint background
    bb:paintRoundedRect(x, y,
                        self.dimen.w, self.dimen.h,
                        Blitbuffer.COLOR_LIGHT_GREY)
    -- paint percentage infill
    bb:paintRect(x, y,
                 math.ceil(self.dimen.w*self.progress), self.dimen.h,
                 Blitbuffer.COLOR_GREY)
end

function MinimalPaginator:setProgress(progress) self.progress = progress end


local LanguageItem = InputContainer:new{
    dimen = nil,
    height = Screen:scaleBySize(44),
    width = nil,
    info = nil,
    background = Blitbuffer.COLOR_WHITE,
}

function LanguageItem:init()
    self.dimen = Geom:new{w = self.width, h = self.height}


    local checked_widget = TextWidget:new{
        text = "√ ",
        face = self.face,
    }
    local unchecked_widget = TextWidget:new{
        text = "",
        face = self.face,
    }

    local horizontal_space = HorizontalSpan:new{width = Screen:scaleBySize(8)}
    self.content_container = OverlapGroup:new{
        dimen = self.dimen:copy(),
        LeftContainer:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                horizontal_space,
            CenterContainer:new{
                dimen = Geom:new{ w = checked_widget:getSize().w },
                item_checked and checked_widget or unchecked_widget
            },
                horizontal_space,
                TextWidget:new{
                    text = self.info.ssid,
                    face = Font:getFace("cfont"),
                },
            },
        }
    }

    self[1] = FrameContainer:new{
        padding = 0,
        margin = 0,
        background = self.background,
        bordersize = 0,
        width = self.width,
        self.content_container,
    }

    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                }
            }
        }
    end
end

function LanguageItem:refresh()
    self:init()
    UIManager:setDirty(self.setting_ui, function() return "ui", self.dimen end)
end

function LanguageItem:connect()
    local connected_item = self.setting_ui:getConnectedItem()
    if connected_item then connected_item:disconnect() end

    local success, err_msg = NetworkMgr:authenticateNetwork(self.info)

    local text
    if success then
        obtainIP()
        self.info.connected = true
        self.setting_ui:setConnectedItem(self)
        text = _("Connected.")
    else
        text = err_msg
    end

    if self.setting_ui.connect_callback then
        self.setting_ui.connect_callback()
    end

    self:refresh()
    UIManager:show(InfoMessage:new{text = text})
end

function LanguageItem:disconnect()
    local info = InfoMessage:new{text = _("Disconnecting…")}
    UIManager:show(info)
    UIManager:forceRePaint()

    NetworkMgr:disconnectNetwork(self.info)
    NetworkMgr:releaseIP()

    UIManager:close(info)
    self.info.connected = nil
    self:refresh()
    self.setting_ui:setConnectedItem(nil)
    if self.setting_ui.connect_callback then
        self.setting_ui.connect_callback()
    end
end

function LanguageItem:onTapSelect(arg, ges_ev)
    if not string.find(self.info.flags, "WPA") then
        UIManager:show(InfoMessage:new{
            text = _("Networks without WPA/WPA2 encryption are not supported.")
        })
        return
    end
    if self.btn_disconnect then
        -- noop if touch is not on disconnect button
        if ges_ev.pos:intersectWith(self.btn_disconnect.dimen) then
            self:disconnect()
        end
    elseif self.info.password then
        if self.btn_edit_nw and ges_ev.pos:intersectWith(self.btn_edit_nw.dimen) then
            self:onEditNetwork()
        else
            self:connect()
        end
    else
        self:onAddNetwork()
    end
    return true
end


local LanguageSetting = InputContainer:new{
    width = nil,
    height = nil,
    -- sample network_list entry: {
    --   bssid = "any",
    --   ssid = "foo",
    --   signal_level = -58,
    --   signal_quality = 84,
    --   frequency = 5660,
    --   flags = "[WPA2-PSK-CCMP][ESS]",
    -- }
    network_list = nil,
    connect_callback = nil,
}

function LanguageSetting:init()
    self.width = self.width or Screen:getWidth() - Screen:scaleBySize(50)
    self.width = math.min(self.width, Screen:scaleBySize(600))

    local gray_bg = Blitbuffer.gray(0.1)
    local items = {}
    table.sort(self.network_list,
               function(l, r) return l.signal_quality > r.signal_quality end)
    for idx,network in ipairs(self.network_list) do
        local bg
        if idx % 2 == 0 then
            bg = gray_bg
        else
            bg = Blitbuffer.COLOR_WHITE
        end
        table.insert(items, LanguageItem:new{
            width = self.width,
            info = network,
            background = bg,
            setting_ui = self,
        })
    end

    self.status_text = TextWidget:new{
        text = "",
        face = Font:getFace("ffont"),
    }
    self.page_text = TextWidget:new{
        text = "",
        face = Font:getFace("ffont"),
    }

    self.pagination = MinimalPaginator:new{
        width = self.width,
        height = Screen:scaleBySize(8),
        percentage = 0,
        progress = 0,
    }

    self.height = self.height or math.min(Screen:getHeight()*3/4,
                                          Screen:scaleBySize(800))
    self.popup = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        padding = 0,
        bordersize = 3,
        VerticalGroup:new{
            align = "left",
            self.pagination,
            ListView:new{
                padding = 0,
                items = items,
                width = self.width,
                height = self.height-self.pagination:getSize().h,
                page_update_cb = function(curr_page, total_pages)
                    self.pagination:setProgress(curr_page/total_pages)
                    -- self.page_text:setText(curr_page .. "/" .. total_pages)
                    UIManager:setDirty(self, function()
                        return "ui", self.dimen
                    end)
                end
            },
        },
    }

    self[1] = CenterContainer:new{
        dimen = {w = Screen:getWidth(), h = Screen:getHeight()},
        self.popup,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        }
    end

    UIManager:nextTick(function()
        local connected_item = self:getConnectedItem()
        if connected_item ~= nil then
            obtainIP()
            UIManager:show(InfoMessage:new{
                text = T(_("Connected to network %1"), connected_item.info.ssid)
            })
            if self.connect_callback then
                self.connect_callback()
            end
        end
    end)
end

function LanguageSetting:setConnectedItem(item)
    self.connected_item = item
end

function LanguageSetting:getConnectedItem()
    return self.connected_item
end

function LanguageSetting:onTapClose(arg, ges_ev)
    if ges_ev.pos:notIntersectWith(self.popup.dimen) then
        UIManager:close(self)
        return true
    end
end

return LanguageSetting

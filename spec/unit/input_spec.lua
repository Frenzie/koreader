describe("input module", function()
    local Input
    local ffi, C
    setup(function()
        require("commonrequire")
        ffi = require("ffi")
        C = ffi.C
        require("ffi/linux_input_h")
        Input = require("device").input
    end)

    describe("handleTouchEvPhoenix", function()
--[[
-- a touch looks something like this (from H2Ov1)
Event: time 1510346968.993890, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346968.994362, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346968.994384, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346968.994399, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346968.994409, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 914
Event: time 1510346968.994420, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346968.994429, -------------- SYN_REPORT ------------
Event: time 1510346969.057898, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.058251, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.058417, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.058436, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346969.058446, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 915
Event: time 1510346969.058456, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.058464, -------------- SYN_REPORT ------------
Event: time 1510346969.066903, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.067102, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.067260, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.067415, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.067433, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.067443, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.067451, -------------- SYN_REPORT ------------
Event: time 1510346969.076230, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.076549, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 0
Event: time 1510346969.076714, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 0
Event: time 1510346969.076869, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.076887, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.076898, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.076908, -------------- SYN_REPORT ------------
]]
        it("should set cur_slot correctly", function()
            local ev
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TRACKING_ID,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TOUCH_MAJOR,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_WIDTH_MAJOR,
                value = 1,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 1012,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_Y,
                value = 914,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)

            -- EV_SYN
            -- depends on gesture_detector
            --[[
            ev = {
                type = C.EV_SYN,
                code = C.SYN_REPORT,
                value = 0,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ]]

            -- this value=2 stuff doesn't happen IRL, just testing logic
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TRACKING_ID,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_TOUCH_MAJOR,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_WIDTH_MAJOR,
                value = 2,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 1012,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
            ev = {
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_Y,
                value = 914,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(2, Input.cur_slot)
        end)
    end)

    describe("text input source tracking", function()
        before_each(function()
            Input.last_text_input_source = nil
            if Input.device then
                Input.device.last_text_input_source = nil
            end
            Input:resetState()
        end)

        it("should classify keyboard and navigation keys separately", function()
            assert.is.same("physical_keyboard", Input:classifyKeyInputSource("A"))
            assert.is.same("physical_keyboard", Input:classifyKeyInputSource("Shift"))
            assert.is.same("other_navigation", Input:classifyKeyInputSource("Up"))
            assert.is.same("other_navigation", Input:classifyKeyInputSource("ScreenKB"))
        end)

        it("should track touch and pen as the last text input source", function()
            Input:handleTouchEv({
                type = C.EV_ABS,
                code = C.ABS_MT_SLOT,
                value = 0,
            })
            Input:handleTouchEv({
                type = C.EV_ABS,
                code = C.ABS_MT_TRACKING_ID,
                value = 1,
            })
            Input:handleTouchEv({
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 10,
            })
            assert.is.same("touch", Input:getLastTextInputSource())

            Input:handleTouchEv({
                type = C.EV_ABS,
                code = C.ABS_MT_TOOL_TYPE,
                value = 1,
            })
            Input:handleTouchEv({
                type = C.EV_ABS,
                code = C.ABS_MT_POSITION_X,
                value = 20,
            })
            assert.is.same("pen", Input:getLastTextInputSource())
        end)
    end)

end)

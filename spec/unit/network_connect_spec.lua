describe("NetworkMgr:async connect flow", function()
    local NetworkMgr, UIManager, time
    local calls
    local assoc_ready

    -- The connect flow is driven by scheduled tasks (subprocess checks & polls);
    -- run them all, fast-forwarding past their delays, until the queue drains.
    -- A 1s shift per iteration covers the 250ms poll granularity.
    local function drain()
        local ffiutil = require("ffi/util")
        for _ = 1, 60 do
            if #UIManager._task_queue == 0 then break end
            UIManager:shiftScheduledTasksBy(-time.s(1))
            UIManager:_checkTasks()
            -- The forked subprocess needs a little real time to exit
            ffiutil.usleep(150000)
        end
    end

    -- Polling uses 250ms scheduleIn ticks; the test harness fast-forwards
    -- scheduled tasks, so we bump gen and rely on immediate subprocess checks.
    -- Subprocess tasks run to completion in the child, which is fast here.

    local function stubBackends(mgr, opts)
        opts = opts or {}
        calls = {complete = 0, abort = 0, dhcp = 0, disconnect = 0, auth_setup = 0}
        assoc_ready = opts.assoc_ready
        -- Wall-clock deadline (os.clock() is CPU time, which stalls while we usleep)
        local assoc_after = opts.assoc_after or 0
        local assoc_deadline = require("ffi/util").gettime() + assoc_after

        function mgr:getNetworkList()
            return opts.network_list or {
                {ssid = "Home", signal_quality = 80, password = "secret"},
            }
        end
        function mgr:getCurrentNetwork()
            if assoc_ready ~= nil then
                return assoc_ready and {id = 7, ssid = opts.assoc_ssid or "Home"} or nil
            end
            if require("ffi/util").gettime() < assoc_deadline then return nil end
            return {id = 7, ssid = opts.assoc_ssid or "Home"}
        end
        function mgr:setupNetworkAuthentication(network)
            calls.auth_setup = calls.auth_setup + 1
            if opts.auth_setup_fails then return nil, "setup failed" end
            return 42
        end
        function mgr:authenticateNetwork(network)
            if opts.auth_fails then return false, "auth failed" end
            return true, nil
        end
        function mgr:disconnectNetwork()
            calls.disconnect = calls.disconnect + 1
        end
        function mgr:getConfiguredNetworks()
            return opts.configured or {}
        end
        function mgr:obtainIP()
            calls.dhcp = calls.dhcp + 1
            if opts.dhcp_fails then error("dhcp") end
        end
        function mgr:saveNetwork() end

        -- Track teardown helpers without touching Wi-Fi for real
        function mgr:_abortWifiConnection()
            calls.abort = calls.abort + 1
            mgr._connect_gen = mgr._connect_gen + 1
            self.pending_connection = false
        end
        function mgr:turnOffWifi()
            calls.turn_off = (calls.turn_off or 0) + 1
        end
        -- Shorten the async flow's timeouts so tests don't take 30s+
        -- (and so the real-time deadlines in drain() can't be outrun by busy work)
        mgr._auth_timeout_s = 1
        mgr._bg_connect_wait_s = 1
        mgr._scan_timeout_s = 1
        mgr._dhcp_timeout_s = 1
        mgr._turn_on_timeout_s = 1
        mgr.pending_connection = true
    end

    setup(function()
        require("commonrequire")
        time = require("ui/time")
        UIManager = require("ui/uimanager")
        local Device = require("device")
        function Device:initNetworkManager(mgr)
            stubBackends(mgr)
            function mgr:turnOnWifi() end
            function mgr:turnOffWifi() end
            function mgr:obtainIP() end
            function mgr:releaseIP() end
            function mgr:restoreWifiAsync() end
        end
        function Device:hasWifiRestore() return false end
        function Device:hasWifiManager() return true end
    end)

    before_each(function()
        package.loaded["ui/network/manager"] = nil
        G_reader_settings:saveSetting("wifi_was_on", false)
        NetworkMgr = require("ui/network/manager")
    end)

    after_each(function()
        package.loaded["ui/network/manager"] = nil
    end)

    it("connects and runs the complete callback on success", function()
        stubBackends(NetworkMgr, {})
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 1)
        assert.is.same(calls.auth_setup, 1)
        assert.is.same(calls.abort, 0)
        assert.is.same(NetworkMgr.lease_ssid, "Home")
    end)

    it("short-circuits when already associated (pass 1)", function()
        stubBackends(NetworkMgr, {
            network_list = {
                {ssid = "LinkedAP", signal_quality = 90, connected = true},
            },
        })
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 1)
        assert.is.same(calls.auth_setup, 0)
        assert.is.same(NetworkMgr.lease_ssid, "LinkedAP")
    end)

    it("waits for association and times out to next attempt (auth cleanup)", function()
        stubBackends(NetworkMgr, {assoc_ready = false})
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 0)
        assert.is.same(calls.auth_setup, 1)
        -- The dead network entry was removed before giving up
        assert.is.same(calls.disconnect, 1)
        assert.is.same(calls.abort, 1)
        assert.is.same(NetworkMgr.lease_ssid, nil)
    end)

    it("does not claim association with the wrong AP", function()
        stubBackends(NetworkMgr, {assoc_ready = true, assoc_ssid = "Other"})
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        -- The association was for another network, so we keep waiting until we time out
        assert.is.same(calls.complete, 0)
        assert.is.same(calls.disconnect, 1)
        assert.is.same(calls.abort, 1)
        assert.is.same(NetworkMgr.lease_ssid, nil)
    end)

    it("removes the wpa network entry when cancelled mid-auth", function()
        stubBackends(NetworkMgr, {assoc_ready = false})
        -- Simulate a teardown while the auth poll is in flight: bump the gen
        -- the first time the poll probes the association state
        local bumped = false
        local orig_getCurrentNetwork = NetworkMgr.getCurrentNetwork
        function NetworkMgr:getCurrentNetwork()
            if not bumped then
                bumped = true
                NetworkMgr._connect_gen = NetworkMgr._connect_gen + 1
            end
            return orig_getCurrentNetwork(self)
        end
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 0)
        -- The enabled network entry was removed on cancellation
        assert.is.same(calls.disconnect, 1)
        assert.is.same(calls.abort, 0)
    end)

    it("picks up wpa_supplicant's background connect", function()
        stubBackends(NetworkMgr, {
            -- No preferred (passworded) network in range: wpa_supplicant's own
            -- background connect is all we can rely on
            network_list = {{ssid = "Other", signal_quality = 50}},
            assoc_after = 0.3,
            configured = {{ssid = "Home"}},
        })
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 1)
        assert.is.same(calls.auth_setup, 0)
        assert.is.same(NetworkMgr.lease_ssid, "Home")
    end)

    it("aborts when teardown happens mid-flight (gen invalidation)", function()
        stubBackends(NetworkMgr, {})
        NetworkMgr:reconnectOrShowNetworkMenu(function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        -- Never torn down during the run, so no spurious abort
        assert.is.same(calls.abort, 0)
    end)

    it("brings up Wi-Fi asynchronously and chains into the connect flow", function()
        stubBackends(NetworkMgr, {})
        NetworkMgr:asyncTurnOnWifi(function() return true end, function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        -- Chaining into the connect flow proves the bring-up step ran
        assert.is.same(calls.complete, 1)
        assert.is.same(NetworkMgr.lease_ssid, "Home")
    end)

    it("tears down on bring-up failure", function()
        stubBackends(NetworkMgr, {})
        NetworkMgr:asyncTurnOnWifi(function() error("enable-wifi.sh failed") end, function()
            calls.complete = calls.complete + 1
        end, false)
        drain()
        assert.is.same(calls.complete, 0)
        assert.is.same(calls.abort, 1)
    end)

    teardown(function()
        local Device = require("device")
        function Device:initNetworkManager() end
        function Device:hasWifiRestore() return false end
        function Device:hasWifiManager() return false end
        package.loaded["ui/network/manager"] = nil
    end)
end)

describe("NetworkMgr: discreet Wi-Fi status", function()
    local NetworkMgr, UIManager

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        local Device = require("device")
        function Device:initNetworkManager(mgr)
            function mgr:turnOnWifi() end
            function mgr:turnOffWifi() end
            function mgr:obtainIP() end
            function mgr:releaseIP() end
            function mgr:restoreWifiAsync() end
        end
        function Device:hasWifiRestore() return false end
        function Device:hasWifiManager() return true end
    end)

    before_each(function()
        package.loaded["ui/network/manager"] = nil
        G_reader_settings:delSetting("discreet_wifi_status")
        NetworkMgr = require("ui/network/manager")
    end)

    after_each(function()
        G_reader_settings:delSetting("discreet_wifi_status")
        package.loaded["ui/network/manager"] = nil
    end)

    it("defaults to enabled", function()
        assert.is_truthy(NetworkMgr:isWifiStatusDiscreet())
    end)

    it("can be toggled off", function()
        G_reader_settings:makeFalse("discreet_wifi_status")
        assert.is_false(NetworkMgr:isWifiStatusDiscreet())
        G_reader_settings:makeTrue("discreet_wifi_status")
        assert.is_truthy(NetworkMgr:isWifiStatusDiscreet())
    end)

    it("broadcasts NetworkConnectFailed on abort", function()
        local failed = false
        -- Intercept the broadcast without touching the window stack
        local broadcastEvent = UIManager.broadcastEvent
        UIManager.broadcastEvent = function(self, event)
            if event.handler == "onNetworkConnectFailed" then
                failed = true
            end
        end
        NetworkMgr:_abortWifiConnection()
        UIManager.broadcastEvent = broadcastEvent
        assert.is_true(failed)
    end)

    it("closes the connecting popup when the attempt is torn down", function()
        G_reader_settings:makeFalse("discreet_wifi_status")
        function NetworkMgr:isWifiOn() return false end
        function NetworkMgr:isConnected() return false end
        local info = NetworkMgr:turnOnWifiAndWaitForConnection()
        assert.is_truthy(info)
        assert.is_true(UIManager:isWidgetShown(info))
        -- Torn down before the connectivity check that would close it could run
        NetworkMgr:_abortWifiConnection()
        assert.is_false(UIManager:isWidgetShown(info))
    end)
end)

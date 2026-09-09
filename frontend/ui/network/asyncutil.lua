--[[--
Non-blocking helpers for long-running network tasks.

`subprocessCall` forks a task into a subprocess and delivers its results via
callback, keeping the UI event loop free in the meantime. `pollUntil` checks a
condition at regular intervals without blocking.

Caveats learned the hard way (do not "simplify" these away):
  * Never drain the pipe with a blocking read (e.g., ffiutil.readAllFromFD):
    Wi-Fi helper scripts spawn daemons (wpa_supplicant -B, dhcpcd) that inherit
    the pipe's write end and never exit, so the read would hang forever. Drain
    only what FIONREAD reports is already buffered.
  * Set FD_CLOEXEC on the child's write fd, for the same reason.
  * Reap terminated subprocesses on a schedule: waitpid() may not succeed right
    after the child exits.
]]

local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local buffer = require("string.buffer")

-- We'll need close/read/fcntl/FIONREAD
require("ffi/posix_h")

local unpack = unpack or table.unpack -- luacheck: ignore
local POLL_INTERVAL = 0.25

local AsyncUtil = {}

-- Run task() in a forked child, deliver its return values to on_done(ok, ...)
-- without ever blocking the UI loop. on_done(false) on task error, spawn
-- failure or timeout; on task error the error string is passed as 2nd arg.
-- is_cancelled, when provided, is polled: if truthy, the subprocess is killed
-- and on_done is NOT called.
function AsyncUtil.subprocessCall(task, timeout_s, on_done, is_cancelled)
    local pid, parent_read_fd = ffiutil.runInSubProcess(function(_, child_write_fd)
        -- Belt: don't leak our pipe into anything the task execs, so daemons
        -- spawned by the task can't hold the write end open (see module notes).
        -- F_SETFD = 2, FD_CLOEXEC = 1 (POSIX; ffi.C.F_SETFD is missing in older releases)
        pcall(function() ffi.C.fcntl(child_write_fd, 2, ffi.cast("int", 1)) end)
        -- pcall returns [ok, ...results]; strip the leading ok flag back out
        local packed = table.pack(pcall(task))
        local ok = packed[1]
        local results = {n = packed.n - 1}
        for i = 2, packed.n do
            results[i - 1] = packed[i]
        end
        -- Encode {ok, results}; a child that dies without writing anything is
        -- indistinguishable from a crash and reported as a failure by the parent.
        local ok_enc, str = pcall(buffer.encode, {ok, results})
        if not ok_enc then
            logger.warn("asyncutil: cannot serialize subprocess result:", str)
            str = buffer.encode({true, {n = 0}})
        end
        ffiutil.writeToFD(child_write_fd, str, true)
    end, true)
    if not pid then
        on_done(false)
        return
    end

    local chunks = {}
    local function closePipe()
        if parent_read_fd then
            ffi.C.close(parent_read_fd)
            parent_read_fd = nil
        end
    end

    -- Reap the zombie after teardown/timeout; the pipe is already closed then.
    local function collect()
        if not ffiutil.isSubProcessDone(pid) then
            UIManager:scheduleIn(1, collect)
        end
    end

    local deadline = time.monotonic() + time.s(timeout_s)
    local function check()
        if is_cancelled and is_cancelled() then
            ffiutil.terminateSubProcess(pid)
            closePipe()
            UIManager:scheduleIn(1, collect)
            return
        end
        if parent_read_fd then
            -- Suspenders: consume data as it comes, so a child writing a result
            -- larger than the pipe buffer can't get stuck (and never exit).
            while true do
                local n = ffiutil.getNonBlockingReadSize(parent_read_fd)
                if not n or n <= 0 then break end
                local buf = ffi.new("char[?]", n)
                local nr = tonumber(ffi.C.read(parent_read_fd, buf, n))
                if not nr or nr <= 0 then break end
                chunks[#chunks + 1] = ffi.string(buf, nr)
            end
        end
        if ffiutil.isSubProcessDone(pid) then
            if parent_read_fd then
                -- Catch bytes written right before exit
                local n = ffiutil.getNonBlockingReadSize(parent_read_fd)
                if n and n > 0 then
                    local buf = ffi.new("char[?]", n)
                    local nr = tonumber(ffi.C.read(parent_read_fd, buf, n))
                    if nr and nr > 0 then
                        chunks[#chunks + 1] = ffi.string(buf, nr)
                    end
                end
                closePipe()
            end
            local ret
            local data = table.concat(chunks)
            if #data > 0 then
                local ok, t = pcall(buffer.decode, data)
                if ok then ret = t end
            end
            if ret and ret[1] == true then
                local results = ret[2]
                on_done(true, unpack(results, 1, results.n))
            elseif ret then
                on_done(false, ret[2] and ret[2][1])
            else
                -- Child died without writing anything: treat as a failure
                on_done(false)
            end
        elseif time.monotonic() > deadline then
            logger.warn("asyncutil: subprocess timed out after", timeout_s, "s")
            ffiutil.terminateSubProcess(pid)
            closePipe()
            UIManager:scheduleIn(1, collect)
            on_done(false)
        else
            UIManager:scheduleIn(POLL_INTERVAL, check)
        end
    end
    UIManager:scheduleIn(POLL_INTERVAL, check)
end

-- Poll check_fn() every 250ms until it returns something truthy or timeout_s
-- elapses. on_result receives the truthy value, or nil on timeout.
-- If is_cancelled turns truthy, polling simply stops (on_result is not called).
function AsyncUtil.pollUntil(check_fn, timeout_s, on_result, is_cancelled)
    local deadline = time.monotonic() + time.s(timeout_s)
    local function tick()
        if is_cancelled and is_cancelled() then
            return
        end
        local res = check_fn()
        if res then
            on_result(res)
        elseif time.monotonic() > deadline then
            on_result(nil)
        else
            UIManager:scheduleIn(POLL_INTERVAL, tick)
        end
    end
    tick()
end

return AsyncUtil

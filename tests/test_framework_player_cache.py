"""Offline test: cached identity/job reads in the qbx_core and qb-core server modules.

Runs the real module files in Lua 5.4 (lupa) against a fake qbx_core / qb-core that
counts every Player read (exports.qbx_core:GetPlayer / QBCore.Functions.GetPlayer) and
returns a copy of the Player each time, like a cross-resource call does.

    uv run --offline --with lupa --python 3.12 python tests/test_framework_player_cache.py

The "before" numbers run the same scenarios against the module files of BASE_REF
(default f7e6c10 = 0.13.18), read with git.
"""

import os
import pathlib
import subprocess
import sys

from lupa import lua54

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE_REF = os.environ.get("BASE_REF", "f7e6c10")
MODULES = {
    "qbx": "modules/framework/qbx_core/server.lua",
    "qb": "modules/framework/qb-core/server.lua",
}
DEFAULT_MODULE = "modules/framework/_default/server.lua"

HARNESS = r"""
local FLAVOR = ...
local clock = 100000
function GetGameTimer() return clock end
function Advance(ms) clock = clock + ms end

Core = { players = {}, reads = 0, fired = {} }

local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
end
Deepcopy = deepcopy

-- events -------------------------------------------------------------------
local handlers = {}
local netSafe = {}
ExternalBefore, ExternalAfter = {}, {}

function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end

function RegisterNetEvent(name, fn)
    netSafe[name] = true
    if fn then AddEventHandler(name, fn) end
end

function TriggerEvent(name, ...)
    table.insert(Core.fired, { name = name, args = table.pack(...) })
    for _, fn in ipairs(ExternalBefore[name] or {}) do fn(...) end
    local saved = source
    source = ''
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    source = saved
    for _, fn in ipairs(ExternalAfter[name] or {}) do fn(...) end
end

function TriggerClientEvent() end

-- a client firing a server event: reaches this resource only if it registered it as a net event
function ClientFires(fromSrc, name, ...)
    if not netSafe[name] then return 'blocked' end
    local saved = source
    source = fromSrc
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
    source = saved
    return 'delivered'
end

function FirePlayerDropped(src)
    local saved = source
    source = src
    for _, fn in ipairs(handlers.playerDropped or {}) do fn('left') end
    source = saved
end

function FiredCount(name)
    local n = 0
    for _, e in ipairs(Core.fired) do if e.name == name then n = n + 1 end end
    return n
end

function FiredArgs(name, index)
    local seen = 0
    for _, e in ipairs(Core.fired) do
        if e.name == name then
            seen = seen + 1
            if seen == index then return e.args[1], e.args[2] end
        end
    end
end

-- handlers this resource (the bridge) registered for an event
function HandlerCount(name)
    return #(handlers[name] or {})
end

-- ClientFires that reports a Lua error instead of raising it into Python
function ClientFiresSafe(...)
    return pcall(ClientFires, ...)
end

-- fake core ----------------------------------------------------------------
local JOBS = {
    unemployed = { label = 'Civilian', defaultDuty = true, grades = { [0] = { name = 'Freelancer' } } },
    police = { label = 'LSPD', defaultDuty = false, grades = { [0] = { name = 'Recruit' }, [1] = { name = 'Officer' }, [2] = { name = 'Chief', isboss = true } } },
    ambulance = { label = 'EMS', defaultDuty = true, grades = { [0] = { name = 'Trainee' } } },
}
local GANGS = { none = { label = 'No Gang' }, ballas = { label = 'Ballas' } }

local function makeJob(name, grade)
    local job, g = JOBS[name], JOBS[name].grades[grade]
    return { name = name, label = job.label, onduty = job.defaultDuty, isboss = g.isboss or false,
             payment = 10, type = 'none', bankAuth = false, grade = { name = g.name, level = grade } }
end

local function find(identifier)
    if identifier == nil then return nil end
    if type(identifier) == 'string' and not tonumber(identifier) then
        for _, p in pairs(Core.players) do
            if p.PlayerData.citizenid == identifier or p.PlayerData.license == identifier then return p end
        end
        return nil
    end
    return Core.players[tonumber(identifier)]
end
Core.find = find

function Core.GetPlayer(src)
    Core.reads = Core.reads + 1
    local p = find(src)
    return p and deepcopy(p) or nil
end

-- Player.Functions.UpdatePlayerData: QBCore:Player:SetPlayerData with the whole PlayerData
function Core.UpdatePlayerData(p)
    TriggerEvent('QBCore:Player:SetPlayerData', deepcopy(p.PlayerData))
end

-- qbx_core 1.23.0 SetPlayerPrimaryJob (server/player.lua:209-211) and qb-core SetJob
-- (server/player.lua:208-210): mutate, UpdatePlayerData (SetPlayerData), then OnJobUpdate
function Core.SetJob(src, name, grade)
    local p = find(src)
    if not p then return false end
    grade = tonumber(grade) or 0
    if not JOBS[name] or not JOBS[name].grades[grade] then
        if FLAVOR == 'qbx' then return false, { code = 'job_not_found', message = 'no job ' .. tostring(name) } end
        return false
    end
    p.PlayerData.job = makeJob(name, grade)
    Core.UpdatePlayerData(p)
    TriggerEvent('QBCore:Server:OnJobUpdate', p.PlayerData.source, deepcopy(p.PlayerData.job))
    return true
end

-- qbx_core 1.23.0 SetPlayerPrimaryGang (server/player.lua:433-435) and qb-core SetGang
-- (server/player.lua:239-241): mutate, UpdatePlayerData (SetPlayerData), then OnGangUpdate
function Core.SetGang(src, name)
    local p = find(src)
    if not p or not GANGS[name] then return false end
    p.PlayerData.gang = { name = name, label = GANGS[name].label, isboss = false, grade = { name = 'none', level = 0 } }
    Core.UpdatePlayerData(p)
    TriggerEvent('QBCore:Server:OnGangUpdate', p.PlayerData.source, deepcopy(p.PlayerData.gang))
    return true
end

-- qbx_core SetJobDuty export (server/player.lua:133): mutate, fire SetDuty, then UpdatePlayerData
function Core.QbxSetJobDuty(identifier, onDuty)
    local p = find(identifier)
    if not p then return end
    p.PlayerData.job.onduty = not not onDuty
    TriggerEvent('QBCore:Server:SetDuty', p.PlayerData.source, p.PlayerData.job.onduty)
    Core.UpdatePlayerData(p)
end

-- qb-core Player.Functions.SetJobDuty (server/player.lua:261): only OnJobUpdate, then UpdatePlayerData
function Core.QbSetJobDuty(src, onDuty)
    local p = find(src)
    p.PlayerData.job.onduty = not not onDuty
    TriggerEvent('QBCore:Server:OnJobUpdate', p.PlayerData.source, deepcopy(p.PlayerData.job))
    Core.UpdatePlayerData(p)
end

-- qb-core QBCore:ToggleDuty (server/events.lua:170)
function Core.QbToggleDuty(src)
    local p = find(src)
    Core.QbSetJobDuty(src, not p.PlayerData.job.onduty)
    TriggerEvent('QBCore:Server:SetDuty', src, p.PlayerData.job.onduty)
end

-- qbx RemovePlayerFromJob (server/player.lua:296): primary job -> unemployed, no OnJobUpdate
function Core.QbxRemovePlayerFromJob(cid, jobName)
    local p = find(cid)
    if p.PlayerData.job.name == jobName then p.PlayerData.job = makeJob('unemployed', 0) end
    TriggerEvent('qbx_core:server:onGroupUpdate', p.PlayerData.source, jobName)
end

-- SetCharInfo / SetPlayerData: no dedicated event
function Core.SetCharInfo(src, key, value)
    find(src).PlayerData.charinfo[key] = value
end

-- Logout: unload event, Wait(200), player removed (qbx then fires playerLoggedOut)
function Core.LogoutBegin(src)
    TriggerEvent('QBCore:Server:OnPlayerUnload', src)
end
function Core.LogoutFinish(src)
    Core.players[src] = nil
    if FLAVOR == 'qbx' then TriggerEvent('qbx_core:server:playerLoggedOut', src) end
end

function Core.AddPlayer(src, cid, first, last, jobName, grade, onduty)
    local self = { Functions = {} }
    self.PlayerData = {
        source = src, citizenid = cid, license = 'license:' .. cid,
        charinfo = { firstname = first, lastname = last, birthdate = '1990-01-' .. (10 + src), phone = '555' .. src,
                     nationality = 'USA', gender = 0, backstory = 'x' },
        job = makeJob(jobName, grade),
        gang = { name = 'none', label = 'No Gang', isboss = false, grade = { name = 'none', level = 0 } },
        items = {}, money = { cash = 100, bank = 5000 },
        metadata = { hunger = 100, thirst = 100, stress = 0, isdead = false, inlaststand = false },
    }
    for i = 1, 40 do self.PlayerData.items[i] = { name = 'item' .. i, amount = i, slot = i, info = { serial = 'S' .. i } } end
    self.PlayerData.job.onduty = onduty and true or false
    self.Functions.SetJob = function(name, g) return Core.SetJob(src, name, g) end
    self.Functions.SetGang = function(name, g) return Core.SetGang(src, name, g) end
    self.Functions.SetJobDuty = function(d)
        if FLAVOR == 'qbx' then return Core.QbxSetJobDuty(src, d) end
        return Core.QbSetJobDuty(src, d)
    end
    self.Functions.SetPlayerData = function(k, v) self.PlayerData[k] = v end
    self.Functions.SetMetaData = function(k, v) self.PlayerData.metadata[k] = v end
    self.Functions.AddMoney = function(t, a) self.PlayerData.money[t] = self.PlayerData.money[t] + a return true end
    self.Functions.RemoveMoney = function(t, a) self.PlayerData.money[t] = self.PlayerData.money[t] - a return true end
    self.Functions.AddItem = function() return true end
    self.Functions.RemoveItem = function() return true end
    for i = 1, 14 do self.Functions['Extra' .. i] = function() end end -- 22 functions like qbx
    Core.players[src] = self
    return self
end

-- FiveM / bridge globals the module files touch ------------------------------
GlobalState = {}
BridgeLateLoad = { Gate = function() return true end, Frameworks = {} }
function GetResourceState(name)
    if FLAVOR == 'qbx' and name == 'qbx_core' then return 'started' end
    if FLAVOR == 'qb' and name == 'qb-core' then return 'started' end
    return 'missing'
end
function IsPlayerAceAllowed() return false end
Math = { Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end }
MySQL = { Sync = { fetchAll = function() return {} end }, query = { await = function() return {} end } }

local qbxExports = {
    GetPlayer = function(_, src) return Core.GetPlayer(src) end,
    GetPlayerByCitizenId = function(_, cid) Core.reads = Core.reads + 1 local p = find(cid) return p and deepcopy(p) or nil end,
    GetQBPlayers = function() local out = {} for s, p in pairs(Core.players) do out[s] = deepcopy(p) end return out end,
    SetJobDuty = function(_, identifier, onDuty) return Core.QbxSetJobDuty(identifier, onDuty) end,
    GetJobs = function() return JOBS end,
    CreateUseableItem = function() end,
}
FakeQBCore = {
    Functions = {
        GetPlayer = function(src) return Core.GetPlayer(src) end,
        GetPlayerByCitizenId = function(cid) Core.reads = Core.reads + 1 local p = find(cid) return p and deepcopy(p) or nil end,
        GetPlayers = function() local out = {} for s in pairs(Core.players) do out[#out + 1] = s end return out end,
        HasPermission = function() return false end,
        CreateUseableItem = function() end,
    },
    Shared = { Jobs = {}, Gangs = {}, Items = {} },
    Commands = { Add = function() end },
}
exports = setmetatable({}, { __index = function(_, res)
    if res == 'qbx_core' then return qbxExports end
    if res == 'qb-core' then return { GetCoreObject = function() return FakeQBCore end } end
end })

-- helpers for Python ----------------------------------------------------------
function Call(name, ...)
    local r = table.pack(pcall(Framework[name], ...))
    return r
end
"""


def git_show(ref, rel):
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:{rel}"],
                             capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.decode("utf-8")


def load(flavor, module_source):
    lua = lua54.LuaRuntime(unpack_returned_tuples=False)
    lua.execute("Framework = nil")
    harness = lua.eval("function(...) " + "local f = load(...) return f end")(HARNESS, "=harness")
    harness(flavor)
    default_src = (ROOT / DEFAULT_MODULE).read_text(encoding="utf-8")
    lua.eval("function(src, name) local f = assert(load(src, name)) return f() end")(default_src, "=" + DEFAULT_MODULE)
    lua.eval("function(src, name) local f = assert(load(src, name)) return f() end")(module_source, "=" + MODULES[flavor])
    return lua


def call(lua, name, *args):
    """Returns ('ok', [values]) or ('error', message)."""
    r = lua.globals().Call(name, *args)
    n = r["n"]
    if not r[1]:
        return ("error", str(r[2]))
    vals = []
    for i in range(2, n + 1):
        v = r[i]
        if lua_type(lua, v) == "table":
            v = {k: v[k] for k in v}
        vals.append(v)
    return ("ok", vals)


def lua_type(lua, v):
    return lua.globals().type(v)


def reads(lua):
    return lua.globals().Core.reads


def seed(lua, n=10):
    core = lua.globals().Core
    for i in range(1, n + 1):
        core.AddPlayer(i, f"CID{i:03d}", f"First{i}", f"Last{i}", "police", 1, i % 2 == 0)


NAN = float("nan")
INF = float("inf")
# sources a cache key is never made for: they read the core uncached, as in 0.13.18
ODD_SOURCES = (NAN, INF, -INF, 0, -1, 1.5, "abc")

HOT_GETTERS = ["GetPlayerIdentifier", "GetPlayerJobData", "GetPlayerDuty", "GetPlayerName", "GetPlayerJob"]
ALL_GETTERS = HOT_GETTERS + ["GetPlayerDob", "GetPlayerPhone", "GetPlayerGang"]


# scenarios: return the number of Player reads they cost ----------------------

def scenario_burst(lua):
    """One tick: a resource walks 10 officers 5 times (MDT feed / unit board / alert fan-out)."""
    seed(lua)
    start = reads(lua)
    for _ in range(5):
        for src in range(1, 11):
            for g in HOT_GETTERS:
                call(lua, g, src)
    return reads(lua) - start


def scenario_alert_fanout(lua):
    """One alert: identifier + job data + duty + name for each of 10 officers, twice (send + MDT access check)."""
    seed(lua)
    start = reads(lua)
    for _ in range(2):
        for src in range(1, 11):
            for g in ("GetPlayerIdentifier", "GetPlayerJobData", "GetPlayerDuty", "GetPlayerName"):
                call(lua, g, src)
    return reads(lua) - start


def scenario_steady(lua):
    """60 s: every officer read (identifier + job data) every 1 s, plus a 3 s GPS loop (identifier + duty)."""
    seed(lua)
    start = reads(lua)
    for second in range(60):
        for src in range(1, 11):
            call(lua, "GetPlayerIdentifier", src)
            call(lua, "GetPlayerJobData", src)
            if second % 3 == 0:
                call(lua, "GetPlayerIdentifier", src)
                call(lua, "GetPlayerDuty", src)
        lua.globals().Advance(1000)
    return reads(lua) - start


SCENARIOS = [
    ("burst: 10 officers x 5 getters x 5 passes, one tick", scenario_burst),
    ("alert fan-out: 10 officers x 4 getters x 2, one tick", scenario_alert_fanout),
    ("steady 60 s: 10 officers, 1 s reads + 3 s GPS loop", scenario_steady),
]


# checks --------------------------------------------------------------------

FAILURES = []


def check(cond, label):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond:
        FAILURES.append(label)


def equivalence(flavor, new_src, old_src):
    """Every getter returns the same values as the 0.13.18 code, in several states."""
    states = []

    def snapshot(lua):
        out = {}
        for src in (1, 2, 3, "2", 99) + ODD_SOURCES:
            for g in ALL_GETTERS:
                res = call(lua, g, src)
                if res[0] == "error":
                    res = ("error", "")
                out[(repr(src), g)] = res
        return out

    def run(src_code):
        lua = load(flavor, src_code)
        seed(lua, 3)
        core = lua.globals().Core
        snaps = [snapshot(lua)]
        core.SetJob(2, "ambulance", 0)
        snaps.append(snapshot(lua))
        core.SetGang(3, "ballas")
        snaps.append(snapshot(lua))
        if flavor == "qbx":
            core.QbxSetJobDuty(1, True)
        else:
            core.QbToggleDuty(1)
        snaps.append(snapshot(lua))
        return snaps

    new, old = run(new_src), run(old_src)
    diffs = []
    for i, (a, b) in enumerate(zip(new, old)):
        for key in a:
            if a[key] != b[key]:
                # 0.13.18 qbx GetPlayerGang raised for a missing player; it now returns nil
                if flavor == "qbx" and key[1] == "GetPlayerGang" and b[key][0] == "error" and a[key] == ("ok", []):
                    continue
                diffs.append((i, key, a[key], b[key]))
    for d in diffs[:10]:
        print("    diff", d)
    check(not diffs, f"[{flavor}] every getter returns what 0.13.18 returned (4 states, srcs 1/2/3/'2'/99 and NaN/inf/-inf/0/-1/1.5/'abc')")

    # spoofed net events with a NaN or inf source, with and without a job table
    def net_outcomes(src_code):
        out = {}
        for event in ("QBCore:Server:OnJobUpdate", "QBCore:Server:OnPlayerLoaded", "QBCore:Server:OnPlayerUnload"):
            for bad in (NAN, INF):
                for with_job in (False, True):
                    lua = load(flavor, src_code)
                    seed(lua, 3)
                    extra = (lua.table_from({"name": "police", "onduty": True}),) if with_job else ()
                    res = lua.globals().ClientFiresSafe(2, event, bad, *extra)
                    out[(event.split(":")[-1], repr(bad), with_job)] = "ok" if res[0] is True else "error: " + str(res[1])
        return out

    new_net, old_net = net_outcomes(new_src), net_outcomes(old_src)
    net_diffs = [(k, new_net[k], old_net[k]) for k in new_net if new_net[k] != old_net[k]]
    for d in net_diffs:
        print("    diff", d)
    for k in new_net:
        if new_net[k] != "ok" and new_net[k] == old_net[k]:
            print(f"    same in 0.13.18 (not from this change): {k[0]}(src={k[1]}, job={'table' if k[2] else 'nil'}) -> {new_net[k]}")
    check(not net_diffs, f"[{flavor}] net events with a NaN or inf source (job table or not): same outcome as 0.13.18")


def invalidation(flavor, src_code):
    lua = load(flavor, src_code)
    seed(lua, 3)
    g = lua.globals()
    core = g.Core

    def r(name, src=1):
        return call(lua, name, src)[1]

    # warm, then a second read is free
    r("GetPlayerJobData")
    before = reads(lua)
    r("GetPlayerJobData"); r("GetPlayerIdentifier"); r("GetPlayerDuty")
    check(reads(lua) == before, f"[{flavor}] warm cache: 3 more getters cost 0 reads")

    # copies: mutating a returned table does not leak into the next call
    jd = call(lua, "GetPlayerJobData", 1)
    lua.eval("function() local t = Framework.GetPlayerJobData(1) t.jobName = 'hacked' t.onDuty = 'x' end")()
    check(r("GetPlayerJobData")[0]["jobName"] == "police", f"[{flavor}] returned job table is a copy")

    # duty changed through the bridge
    core.fired = lua.table()
    was = r("GetPlayerDuty")[0]
    call(lua, "SetPlayerDuty", 1, not was)
    check(r("GetPlayerDuty")[0] == (not was), f"[{flavor}] bridge SetPlayerDuty: next GetPlayerDuty is the new value")
    check(g.FiredCount("QBCore:Server:SetDuty") == 1, f"[{flavor}] bridge SetPlayerDuty: QBCore:Server:SetDuty fired once")
    src_arg, duty_arg = g.FiredArgs("QBCore:Server:SetDuty", 1)
    check(src_arg == 1 and duty_arg == (not was), f"[{flavor}] bridge SetPlayerDuty: SetDuty carries the new value")

    # a listener running before the bridge's own handlers, during a bridge setter
    seen = []
    duty_event = "QBCore:Server:SetDuty" if flavor == "qbx" else "QBCore:Server:OnJobUpdate"
    lua.eval("function(name, sink) ExternalBefore[name] = { function(src) sink(Framework.GetPlayerDuty(src)) end } end")(
        duty_event, lambda v: seen.append(v))
    r("GetPlayerDuty")
    call(lua, "SetPlayerDuty", 1, was)
    check(seen and seen[0] == was, f"[{flavor}] bridge SetPlayerDuty: a listener dispatched before the bridge reads the new duty")
    lua.execute("ExternalBefore = {}")

    # duty changed outside the bridge
    r("GetPlayerDuty")
    if flavor == "qbx":
        core.QbxSetJobDuty("CID001", not was)  # another resource calling exports.qbx_core:SetJobDuty
    else:
        core.QbToggleDuty(1)
    check(r("GetPlayerDuty")[0] == (not was), f"[{flavor}] duty changed by the core directly: next read is fresh")

    # listener after the bridge sees fresh data on a direct core change
    seen.clear()
    lua.eval("function(sink) ExternalAfter['QBCore:Server:OnJobUpdate'] = { function(src) sink(Framework.GetPlayerJobData(src).jobName) end } end")(
        lambda v: seen.append(v))
    r("GetPlayerJobData", 2)
    core.SetJob(2, "ambulance", 0)
    check(seen == ["ambulance"], f"[{flavor}] job changed by the core: OnJobUpdate listener after the bridge reads the new job")
    lua.execute("ExternalAfter = {}")
    check(r("GetPlayerJob", 2)[0] == "ambulance", f"[{flavor}] job changed by the core: GetPlayerJob is the new job")

    # job through the bridge setter, return values passed through
    r("GetPlayerJobData", 3)
    res = call(lua, "SetPlayerJob", 3, "ambulance", 0)
    check(res == ("ok", [True]), f"[{flavor}] bridge SetPlayerJob returns the core's result")
    check(r("GetPlayerJobData", 3)[0]["jobName"] == "ambulance", f"[{flavor}] bridge SetPlayerJob: next read is the new job")
    res = call(lua, "SetPlayerJob", 3, "nosuchjob", 0)
    if flavor == "qbx":
        check(res[0] == "ok" and res[1][0] is False and len(res[1]) == 2,
              "[qbx] bridge SetPlayerJob still returns (false, errorResult) from qbx")
    else:
        check(res == ("ok", [False]), "[qb] bridge SetPlayerJob still returns false for an unknown job")

    # gang
    r("GetPlayerGang", 1)
    core.SetGang(1, "ballas")
    check(r("GetPlayerGang", 1)[0] == "ballas", f"[{flavor}] OnGangUpdate: next GetPlayerGang is the new gang")

    if flavor == "qbx":
        core.SetJob(1, "police", 2)
        r("GetPlayerJobData", 1)
        core.QbxRemovePlayerFromJob("CID001", "police")
        check(r("GetPlayerJobData", 1)[0]["jobName"] == "unemployed",
              "[qbx] RemovePlayerFromJob (only onGroupUpdate): next read is unemployed")

    # TTL safety net for changes without an event
    g.Advance(2000)
    r("GetPlayerName", 2)
    core.SetCharInfo(2, "firstname", "Renamed")
    stale = r("GetPlayerName", 2)[0]
    g.Advance(1999)
    still = r("GetPlayerName", 2)[0]
    g.Advance(1)
    fresh = r("GetPlayerName", 2)[0]
    check(stale == "First2" and still == "First2" and fresh == "Renamed",
          f"[{flavor}] change without an event (SetCharInfo): visible after the 2000 ms TTL, not before")

    # events are never a data source: a client spoofing OnJobUpdate with a fake job
    r("GetPlayerJobData", 2)
    delivered = g.ClientFires(2, "QBCore:Server:OnJobUpdate", 2, lua.table_from({"name": "police", "onduty": True}))
    check(delivered == "delivered" and r("GetPlayerJobData", 2)[0]["jobName"] == "ambulance",
          f"[{flavor}] spoofed QBCore:Server:OnJobUpdate only drops the cache, data still comes from the core")
    check(g.ClientFires(2, "QBCore:Server:SetDuty", 2, True) == "blocked",
          f"[{flavor}] QBCore:Server:SetDuty handler is not net-callable")
    check(g.ClientFires(2, "QBCore:Server:OnJobUpdate", "garbage") == "delivered",
          f"[{flavor}] spoofed OnJobUpdate with a bad source does not error")
    # NaN is truthy and t[NaN] = nil raises "table index is NaN": a client must not be able
    # to raise script errors through the net events with TriggerServerEvent(..., 0/0)
    for event in ("QBCore:Server:OnJobUpdate", "QBCore:Server:OnPlayerLoaded", "QBCore:Server:OnPlayerUnload"):
        results = [g.ClientFiresSafe(2, event, bad) for bad in (NAN, INF)]
        for res in results:
            if res[0] is not True:
                print("    error", event, res)
        check(all(res[0] is True and res[1] == "delivered" for res in results),
              f"[{flavor}] spoofed {event.split(':')[-1]}(NaN) and (inf) do not error")
    # same answer as for a missing player: nil (qb GetPlayerJobData: {} as in 0.13.18)
    res = [(call(lua, name, bad), call(lua, name, 99)) for name in ("GetPlayerIdentifier", "GetPlayerJobData")
           for bad in (NAN, INF)]
    check(all(got == missing and got[0] == "ok" for got, missing in res)
          and res[0][0] == ("ok", []),
          f"[{flavor}] GetPlayerIdentifier / GetPlayerJobData of a NaN or inf source: no error, same as a missing player")
    # a core that did return a player for these sources: never cached, every read goes to the core
    uncached = []
    for odd in (0, -1, 1.5, INF):
        core.AddPlayer(odd, "CIDODD", "Odd", "Source", "unemployed", 0, False)
        before = reads(lua)
        a, b = call(lua, "GetPlayerIdentifier", odd), call(lua, "GetPlayerIdentifier", odd)
        uncached.append(a == b == ("ok", ["CIDODD"]) and reads(lua) - before == 2)
        core.players[odd] = None
    check(all(uncached), f"[{flavor}] sources 0, -1, 1.5 and inf are read uncached (no cache key)")

    # string src that is not a number (license) is never cached
    before = reads(lua)
    call(lua, "GetPlayerIdentifier", "license:CID002")
    call(lua, "GetPlayerIdentifier", "license:CID002")
    check(reads(lua) - before == 2 and call(lua, "GetPlayerIdentifier", "license:CID002")[1] == ["CID002"],
          f"[{flavor}] non-numeric source (license) reads uncached and still works")
    # numeric string shares the numeric entry
    r("GetPlayerIdentifier", 2)
    before = reads(lua)
    call(lua, "GetPlayerIdentifier", "2")
    check(reads(lua) == before, f"[{flavor}] source '2' and 2 share one entry")

    # missing player: nil and not cached
    check(call(lua, "GetPlayerIdentifier", 50) == ("ok", []), f"[{flavor}] missing player -> nil")
    core.AddPlayer(50, "CID050", "New", "Guy", "unemployed", 0, False)
    check(call(lua, "GetPlayerIdentifier", 50)[1] == ["CID050"], f"[{flavor}] player that loads right after a miss is seen at once")
    check(call(lua, "GetPlayerGang", 77) == ("ok", []), f"[{flavor}] GetPlayerGang of a missing player -> nil, no error")

    # logout: unload, 200 ms with the old character still in the core, then gone
    r("GetPlayerIdentifier", 3)
    core.LogoutBegin(3)
    before = reads(lua)
    check(r("GetPlayerIdentifier", 3) == ["CID003"], f"[{flavor}] during logout the core still has the character")
    r("GetPlayerIdentifier", 3)
    check(reads(lua) - before == 2, f"[{flavor}] during logout reads go to the core uncached")
    g.Advance(200)
    core.LogoutFinish(3)
    check(call(lua, "GetPlayerIdentifier", 3) == ("ok", []), f"[{flavor}] after logout GetPlayerIdentifier is nil at once")
    # new character on the same source
    g.Advance(5000)
    core.AddPlayer(3, "CID999", "Other", "Char", "unemployed", 0, False)
    g.ClientFires(3, "QBCore:Server:OnPlayerLoaded")
    check(r("GetPlayerIdentifier", 3) == ["CID999"] and r("GetPlayerName", 3) == ["Other", "Char"],
          f"[{flavor}] new character on the same source is read fresh")
    before = reads(lua)
    r("GetPlayerJobData", 3)
    check(reads(lua) == before, f"[{flavor}] after the bypass window the new character is cached again")

    # drop: bridge handler runs before the core removes the player
    r("GetPlayerIdentifier", 2)
    g.FirePlayerDropped(2)
    check(r("GetPlayerIdentifier", 2) == ["CID002"], f"[{flavor}] playerDropped before the core's own drop handler: still the core's data")
    core.players[2] = None
    check(call(lua, "GetPlayerIdentifier", 2) == ("ok", []), f"[{flavor}] after the core removes a dropped player: nil at once")


def setplayerdata_order(flavor, src_code):
    """Both cores fire QBCore:Player:SetPlayerData BEFORE OnJobUpdate/OnGangUpdate (qbx_core
    1.23.0 server/player.lua:209-211, 433-435; qb-core server/player.lua:208-210, 239-241).
    The bridge deliberately does not listen to SetPlayerData (it carries the whole PlayerData
    and fires on every money/metadata/inventory sync), so a SetPlayerData listener that reads
    job or gang through the bridge gets the cached OLD value when the entry was filled in the
    last 2 s. These checks pin that behaviour down so it stays documented, not hidden."""
    lua = load(flavor, src_code)
    seed(lua, 3)
    g = lua.globals()
    core = g.Core
    check(g.HandlerCount("QBCore:Player:SetPlayerData") == 0,
          f"[{flavor}] the bridge has no QBCore:Player:SetPlayerData handler (no full PlayerData unpack)")

    seen = []
    lua.eval("""function(sink)
        ExternalAfter['QBCore:Player:SetPlayerData'] = { function(pd)
            local jd = Framework.GetPlayerJobData(pd.source)
            sink(jd and jd.jobName, Framework.GetPlayerGang(pd.source), Framework.GetPlayerDuty(pd.source))
        end }
    end""")(lambda *v: seen.append(v))

    def r(name, src=1):
        return call(lua, name, src)[1]

    # job changed by the core, entry filled < 2 s ago: stale inside SetPlayerData, fresh after OnJobUpdate
    r("GetPlayerJobData")
    seen.clear()
    core.SetJob(1, "ambulance", 0)
    check(bool(seen) and seen[0][0] == "police",
          f"[{flavor}] core SetJob, entry filled < 2 s ago: a SetPlayerData listener reads the OLD job (known limit)")
    check(r("GetPlayerJobData")[0]["jobName"] == "ambulance",
          f"[{flavor}] core SetJob: right after OnJobUpdate the bridge reads the new job")

    # same change with an entry older than the TTL: the listener reads the core, so it is fresh
    g.Advance(2000)
    seen.clear()
    core.SetJob(1, "police", 1)
    check(bool(seen) and seen[0][0] == "police" and r("GetPlayerJob")[0] == "police",
          f"[{flavor}] core SetJob, entry older than 2 s: the SetPlayerData listener reads the new job")

    # gang: same order, same limit
    r("GetPlayerGang")
    seen.clear()
    core.SetGang(1, "ballas")
    check(bool(seen) and seen[0][1] == "none" and r("GetPlayerGang")[0] == "ballas",
          f"[{flavor}] core SetGang, entry filled < 2 s ago: SetPlayerData listener reads the OLD gang, fresh after OnGangUpdate")

    # duty: both cores fire the duty event first and SetPlayerData after it, so the listener is fresh
    was = r("GetPlayerDuty")[0]
    seen.clear()
    if flavor == "qbx":
        core.QbxSetJobDuty(1, not was)
    else:
        core.QbSetJobDuty(1, not was)
    check(bool(seen) and seen[-1][2] == (not was),
          f"[{flavor}] duty changed by the core: SetPlayerData fires after the duty event, the listener reads the new duty")

    # changes through the bridge setter: the drop-before means the listener reads the new job
    r("GetPlayerJobData", 2)
    seen.clear()
    call(lua, "SetPlayerJob", 2, "ambulance", 0)
    check(bool(seen) and seen[0][0] == "ambulance",
          f"[{flavor}] bridge SetPlayerJob: the SetPlayerData listener reads the new job")


def invalidation_gaps(flavor, src_code):
    """Checks that fail when one specific invalidation is removed (review of PR #19)."""
    def fresh():
        lua = load(flavor, src_code)
        seed(lua, 3)
        return lua, lua.globals(), lua.globals().Core

    def r(lua, name, src):
        return call(lua, name, src)[1]

    # (a) duty set without OnJobUpdate, only QBCore:Server:SetDuty fired (e.g. SetPlayerData('job') + SetDuty)
    lua, g, core = fresh()
    was = r(lua, "GetPlayerDuty", 1)[0]
    lua.eval("""function(src, d)
        Core.players[src].PlayerData.job.onduty = d
        TriggerEvent('QBCore:Server:SetDuty', src, d)
    end""")(1, not was)
    check(r(lua, "GetPlayerDuty", 1)[0] == (not was),
          f"[{flavor}] only QBCore:Server:SetDuty fired (no OnJobUpdate): next GetPlayerDuty is fresh")

    # (b) qbx: logout slower than the 1 s bypass, entry refilled before the player is removed
    if flavor == "qbx":
        lua, g, core = fresh()
        r(lua, "GetPlayerIdentifier", 3)
        core.LogoutBegin(3)
        g.Advance(1000)
        r(lua, "GetPlayerIdentifier", 3)
        before = reads(lua)
        refilled = r(lua, "GetPlayerIdentifier", 3) == ["CID003"] and reads(lua) == before
        check(refilled, "[qbx] slow logout: after the 1 s bypass the old character is cached again")
        core.LogoutFinish(3)
        check(call(lua, "GetPlayerIdentifier", 3) == ("ok", []),
              "[qbx] slow logout: qbx_core:server:playerLoggedOut drops it, GetPlayerIdentifier is nil at once")

    # (c) character swapped with no unload events and no time passing, then OnPlayerLoaded
    lua, g, core = fresh()
    r(lua, "GetPlayerIdentifier", 2)
    core.AddPlayer(2, "CID777", "Swapped", "Char", "unemployed", 0, False)
    stale = r(lua, "GetPlayerIdentifier", 2)
    g.ClientFires(2, "QBCore:Server:OnPlayerLoaded")
    check(stale == ["CID002"] and r(lua, "GetPlayerIdentifier", 2) == ["CID777"]
          and r(lua, "GetPlayerName", 2) == ["Swapped", "Char"],
          f"[{flavor}] OnPlayerLoaded alone (no unload, no TTL expiry) drops the old character at once")

    # (d) bridge SetPlayerJob: an OnJobUpdate listener dispatched before the bridge's handler
    lua, g, core = fresh()
    r(lua, "GetPlayerJobData", 3)
    seen = []
    lua.eval("""function(sink)
        ExternalBefore['QBCore:Server:OnJobUpdate'] = { function(src) sink(Framework.GetPlayerJobData(src).jobName) end }
    end""")(seen.append)
    call(lua, "SetPlayerJob", 3, "ambulance", 0)
    check(seen == ["ambulance"],
          f"[{flavor}] bridge SetPlayerJob: an OnJobUpdate listener dispatched before the bridge reads the new job")


def compile_check():
    lua = lua54.LuaRuntime()
    loader = lua.eval("function(src, name) local f, err = load(src, name) return f ~= nil, err end")
    for rel in MODULES.values():
        ok, err = loader((ROOT / rel).read_text(encoding="utf-8"), "=" + rel)
        check(bool(ok), f"compiles: {rel}" + ("" if ok else f" ({err})"))


def main():
    print("compile")
    compile_check()

    print("\nframework reads (exports.qbx_core:GetPlayer / QBCore.Functions.GetPlayer)")
    print(f"  {'scenario':58} {'flavor':6} {'before':>7} {'after':>7}")
    for flavor, rel in MODULES.items():
        new_src = (ROOT / rel).read_text(encoding="utf-8")
        old_src = git_show(BASE_REF, rel)
        for label, fn in SCENARIOS:
            after = fn(load(flavor, new_src))
            before = fn(load(flavor, old_src)) if old_src else None
            print(f"  {label:58} {flavor:6} {before if before is not None else '-':>7} {after:>7}")
            if before is not None:
                check(after < before, f"[{flavor}] fewer reads: {label}")
        # double SetDuty in 0.13.18
        if old_src:
            for name, code in (("before", old_src), ("after", new_src)):
                lua = load(flavor, code)
                seed(lua, 1)
                lua.globals().Core.fired = lua.table()
                call(lua, "SetPlayerDuty", 1, True)
                first = lua.globals().FiredArgs("QBCore:Server:SetDuty", 1)
                last = lua.globals().FiredArgs("QBCore:Server:SetDuty", lua.globals().FiredCount("QBCore:Server:SetDuty"))
                print(f"  SetPlayerDuty(1, true) {flavor} {name}: SetDuty fired "
                      f"{lua.globals().FiredCount('QBCore:Server:SetDuty')}x, first onduty={first[1] if isinstance(first, tuple) else first}, "
                      f"last onduty={last[1] if isinstance(last, tuple) else last}")

    print("\nbehaviour")
    for flavor, rel in MODULES.items():
        new_src = (ROOT / rel).read_text(encoding="utf-8")
        old_src = git_show(BASE_REF, rel)
        if old_src:
            equivalence(flavor, new_src, old_src)
        invalidation(flavor, new_src)
        setplayerdata_order(flavor, new_src)
        invalidation_gaps(flavor, new_src)

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        sys.exit(1)
    print("ALL PASSED")


if __name__ == "__main__":
    main()

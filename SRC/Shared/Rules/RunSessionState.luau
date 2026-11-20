--!strict
--[[
	RunSessionState
	Pure state machine for one player's run session (used by RunSessionService).

	  Ranch ──travel──▶ StartingArea ──cross line──▶ Riding ──stamina 0──▶ Collapsed
	    ▲                    │                                                  │
	    └────── return ──────┘◀──────────── after message / respawn / death ────┘

	Invariants (checked by IsValid, enforced by every transition):
	  Ranch        Biome = nil, Run = nil
	  StartingArea Biome set,   Run = nil
	  Riding       Biome set,   Run set
	  Collapsed    Biome set,   Run set
	Every transition changes all fields at once and increments Token, so a delayed callback
	that captured an older Token can tell it is stale. A session can never be Riding with a
	nil Run.
]]

export type State = "Ranch" | "StartingArea" | "Riding" | "Collapsed"

export type Session = {
	State: State,
	Biome: string?,
	Run: any?, -- RunProgress.Run while Riding/Collapsed
	StatsTimer: number,
	Token: number,
	DebugSpeed: number?, -- Studio-only riding speed override; survives transitions
}

local RunSessionState = {}

function RunSessionState.new(): Session
	return { State = "Ranch", Biome = nil, Run = nil, StatsTimer = 0, Token = 0, DebugSpeed = nil }
end

-- Returns (true) if the session satisfies its state's invariant, else (false, reason).
function RunSessionState.IsValid(session: Session): (boolean, string?)
	local state = session.State
	if state == "Ranch" then
		if session.Biome ~= nil or session.Run ~= nil then
			return false, "Ranch must have no biome and no run"
		end
	elseif state == "StartingArea" then
		if session.Biome == nil or session.Run ~= nil then
			return false, "StartingArea needs a biome and no run"
		end
	elseif state == "Riding" or state == "Collapsed" then
		if session.Biome == nil or session.Run == nil then
			return false, `{state} needs a biome and a run`
		end
	else
		return false, `unknown state {tostring(state)}`
	end
	return true
end

-- True if nothing has changed the session since `token` was captured.
function RunSessionState.IsCurrent(session: Session, token: number): boolean
	return session.Token == token
end

local function commit(session: Session, state: State, biome: string?, run: any?)
	session.State = state
	session.Biome = biome
	session.Run = run
	session.StatsTimer = 0
	session.Token += 1
	local ok, reason = RunSessionState.IsValid(session)
	assert(ok, reason)
end

-- Allowed from any state (return button, end of collapse message, respawn, death, recovery).
function RunSessionState.ToRanch(session: Session)
	commit(session, "Ranch", nil, nil)
end

function RunSessionState.ToStartingArea(session: Session, biome: string)
	assert(session.State == "Ranch", `cannot travel from {session.State}`)
	assert(typeof(biome) == "string" and biome ~= "", "biome id required")
	commit(session, "StartingArea", biome, nil)
end

function RunSessionState.ToRiding(session: Session, run: any)
	assert(session.State == "StartingArea", `cannot start a run from {session.State}`)
	assert(run ~= nil, "a run is required to start riding")
	commit(session, "Riding", session.Biome, run)
end

function RunSessionState.ToCollapsed(session: Session)
	assert(session.State == "Riding", `cannot collapse from {session.State}`)
	commit(session, "Collapsed", session.Biome, session.Run)
end

return RunSessionState

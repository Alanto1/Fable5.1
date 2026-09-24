--!nonstrict
-- Effects: the server-side status effects a raider can receive from defenses.
-- Speed is recomputed by RaidService each tick from these plus sack weight; this module only
-- stores the state and applies instantaneous things (damage, fling, root).

local Effects = {}

export type State = {
	slowFactor: number, -- 1 = normal
	slowUntil: number,
	rootUntil: number,
	stunUntil: number,
	lastDamage: number,
}

local states: { [Player]: State } = {}

function Effects.get(player: Player): State
	local state = states[player]
	if not state then
		state = { slowFactor = 1, slowUntil = 0, rootUntil = 0, stunUntil = 0, lastDamage = 0 }
		states[player] = state
	end
	return state
end

function Effects.clear(player: Player)
	states[player] = nil
end

function Effects.damage(player: Player, amount: number, source: string?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
		Effects.get(player).lastDamage = os.clock()
		character:SetAttribute("LastHitSource", source or "")
	end
end

function Effects.slow(player: Player, factor: number, duration: number)
	local state = Effects.get(player)
	local untilTime = os.clock() + duration
	-- The stronger slow wins while it lasts.
	if factor < state.slowFactor or state.slowUntil < os.clock() then
		state.slowFactor = factor
	end
	state.slowUntil = math.max(state.slowUntil, untilTime)
end

function Effects.root(player: Player, duration: number)
	local state = Effects.get(player)
	state.rootUntil = math.max(state.rootUntil, os.clock() + duration)
end

function Effects.stun(player: Player, duration: number)
	local state = Effects.get(player)
	state.stunUntil = math.max(state.stunUntil, os.clock() + duration)
end

-- Launches the character: mostly up, a bit away from `from`.
function Effects.fling(player: Player, from: Vector3, force: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local away = (root.Position - from)
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.5 then
		away = root.CFrame.LookVector * -1
	end
	away = away.Unit
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	root.AssemblyLinearVelocity = away * force * 0.6 + Vector3.new(0, force, 0)
	root.AssemblyAngularVelocity =
		Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)
	task.delay(1.4, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- Speed multiplier from active effects, and whether the player is rooted/stunned.
function Effects.speedMultiplier(player: Player): number
	local state = states[player]
	if not state then
		return 1
	end
	local clock = os.clock()
	if state.rootUntil > clock or state.stunUntil > clock then
		return 0
	end
	if state.slowUntil > clock then
		return state.slowFactor
	end
	state.slowFactor = 1
	return 1
end

return Effects

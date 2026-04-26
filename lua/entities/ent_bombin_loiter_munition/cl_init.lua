include("shared.lua")

-- ================================================================
--  DAMAGE TIER FX  (Bayraktar TB2)
-- ================================================================
game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")
PrecacheParticleSystem("fire_large_01")

-- Tier 1: port & starboard wingtips
-- Tier 2: wingtips + centre fuselage + engine bay
local TIER_OFFSETS = {
	[1] = {
		Vector(0,  90, 0),
		Vector(0, -90, 0),
	},
	[2] = {
		Vector(0,  90, 0),
		Vector(0, -90, 0),
		Vector(0,   0, 0),
		Vector(0, -45, 8),
	},
}

local TIER_PARTICLE = {
	[1] = "fire_medium_02",
	[2] = "fire_large_01",
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 5   }

local LoiterStates = {}

local function BurstAt(pos, tier)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(tier == 3 and math.Rand(0.6, 1.2) or math.Rand(0.3, 0.7))
	ed:SetMagnitude(1)
	ed:SetRadius(tier * 15)
	util.Effect("Explosion", ed)

	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetNormal(Vector(0, 0, 1))
	ed2:SetScale(tier * 0.25)
	ed2:SetMagnitude(tier * 0.35)
	ed2:SetRadius(14)
	util.Effect("ManhackSparks", ed2)

	if tier >= 2 then
		local ed3 = EffectData()
		ed3:SetOrigin(pos)
		ed3:SetNormal(VectorRand())
		ed3:SetScale(0.5)
		util.Effect("ElectricSpark", ed3)
	end
end

local function SpawnBurstFX(ent, count, tier)
	if not IsValid(ent) then return end
	local pos = ent:GetPos()
	local ang = ent:GetAngles()
	for _ = 1, count do
		local localOff = Vector(
			math.Rand(-80, 80),
			math.Rand(-80, 80),
			math.Rand(-10, 20)
		)
		BurstAt(LocalToWorld(localOff, Angle(0,0,0), pos, ang), tier)
	end
end

local function StopParticles(state)
	if not state.particles then return end
	for _, p in ipairs(state.particles) do
		if IsValid(p) then p:StopEmission() end
	end
	state.particles = {}
end

local function ApplyFlameParticles(ent, state, tier)
	StopParticles(state)
	state.tier = tier
	if not IsValid(ent) or tier == 0 then return end

	local offsets = TIER_OFFSETS[math.min(tier, 2)]
	local pname   = TIER_PARTICLE[math.min(tier, 2)] or "fire_medium_02"
	if not offsets then return end

	for _, off in ipairs(offsets) do
		local p = ent:CreateParticleEffect(pname, PATTACH_ABSORIGIN_FOLLOW, 0)
		if IsValid(p) then
			p:SetControlPoint(0, ent:LocalToWorld(off))
			table.insert(state.particles, p)
		end
	end

	state.nextBurst = CurTime() + (TIER_BURST_DELAY[tier] or 4)
end

net.Receive("bombin_loiter_damage_tier", function()
	local idx  = net.ReadUInt(16)
	local tier = net.ReadUInt(2)

	local state = LoiterStates[idx]
	if not state then
		state = { tier = 0, particles = {}, nextBurst = 0 }
		LoiterStates[idx] = state
	end

	if state.tier == tier then return end

	local ent = Entity(idx)
	if IsValid(ent) then
		ApplyFlameParticles(ent, state, tier)
		if tier > 0 then SpawnBurstFX(ent, TIER_BURST_COUNT[tier] or 1, tier) end
	else
		state.tier         = tier
		state.pendingApply = true
	end
end)

hook.Add("Think", "bombin_loiter_damage_fx", function()
	local ct = CurTime()
	for idx, state in pairs(LoiterStates) do
		local ent = Entity(idx)
		if not IsValid(ent) then
			StopParticles(state)
			LoiterStates[idx] = nil
		else
			if state.pendingApply then
				state.pendingApply = false
				ApplyFlameParticles(ent, state, state.tier)
			end

			if state.tier > 0 then
				local pos     = ent:GetPos()
				local ang     = ent:GetAngles()
				local offsets = TIER_OFFSETS[math.min(state.tier, 2)]
				if offsets then
					for i, p in ipairs(state.particles) do
						if IsValid(p) and offsets[i] then
							p:SetControlPoint(0, LocalToWorld(offsets[i], Angle(0,0,0), pos, ang))
						end
					end
				end

				if ct >= state.nextBurst then
					SpawnBurstFX(ent, TIER_BURST_COUNT[state.tier] or 1, state.tier)
					state.nextBurst = ct + (TIER_BURST_DELAY[state.tier] or 4)
				end
			end
		end
	end
end)

function ENT:Initialize()
	local idx = self:EntIndex()
	LoiterStates[idx] = { tier = 0, particles = {}, nextBurst = 0 }
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:OnRemove()
	local idx   = self:EntIndex()
	local state = LoiterStates[idx]
	if state then
		StopParticles(state)
		LoiterStates[idx] = nil
	end
end

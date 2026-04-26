include("shared.lua")

-- ================================================================
--  DAMAGE TIER FX  (Bayraktar TB2)
--  Body: medium-span straight wing (~200u span), pusher engine at
--  rear, EO/IR turret nose. Scatter across GetRight() (wing axis)
--  for wingtip fires, and along fuselage for body hits.
-- ================================================================
game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")
PrecacheParticleSystem("fire_large_01")

-- Tier 1: light damage — port & starboard wingtips only
-- Tier 2: heavy damage — wingtips + centre fuselage + engine bay
local TIER_OFFSETS = {
	[1] = {
		Vector(0,  90, 0),   -- port wingtip
		Vector(0, -90, 0),   -- starboard wingtip
	},
	[2] = {
		Vector(0,  90, 0),   -- port wingtip
		Vector(0, -90, 0),   -- starboard wingtip
		Vector(0,   0, 0),   -- centre fuselage
		Vector(0, -45, 8),   -- engine bay (pusher, rear-right)
	},
}

local TIER_PARTICLE = {
	[1] = "fire_medium_02",
	[2] = "fire_large_01",
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 5   }
-- TB2 is the largest airframe in the family; bump count slightly.

local LoiterStates = {}

local function BurstAt(pos, tier)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(1)
	util.Effect("Explosion", ed, true, true)
	util.Effect("ManhackSparks", ed, true, true)
	if tier >= 2 then
		util.Effect("ElectricSpark", ed, true, true)
	end
end

local function SpawnBurstFX(ent, tier)
	local count = TIER_BURST_COUNT[tier] or 1
	local right = ent:GetRight()
	for i = 1, count do
		-- scatter along wing span axis for a wide UAV
		local offset = right * math.Rand(-80, 80)
		BurstAt(ent:GetPos() + offset, tier)
	end
end

local function ApplyFlameParticles(ent, state, tier)
	-- stop previous emitters
	for _, pname in ipairs(state.particles) do
		ParticleStopEmission(ent, false, pname)
	end
	state.particles = {}
	state.offsets   = {}

	if tier == 0 or tier == 3 then return end

	local offsets = TIER_OFFSETS[math.min(tier, 2)]
	local pname   = TIER_PARTICLE[math.min(tier, 2)] or "fire_medium_02"
	if not offsets then return end

	for _, localOfs in ipairs(offsets) do
		ParticleEffectAttach(
			pname,
			PARTICLE_ATTACH_WORLDSPACE,
			ent,
			ent:GetPos() + ent:LocalToWorld(localOfs) - ent:GetPos()
		)
		table.insert(state.particles, pname)
		table.insert(state.offsets, localOfs)
	end
end

net.Receive("bombin_loiter_damage_tier", function()
	local idx  = net.ReadUInt(16)
	local tier = net.ReadUInt(2)

	local ent = Entity(idx)
	if not IsValid(ent) then
		LoiterStates[idx] = LoiterStates[idx] or { tier = 0, particles = {}, offsets = {}, pendingApply = false }
		LoiterStates[idx].pendingApply = tier
		return
	end

	local state = LoiterStates[idx]
	if not state then
		state = { tier = 0, particles = {}, offsets = {}, pendingApply = false }
		LoiterStates[idx] = state
	end

	state.tier         = tier
	state.nextBurst    = CurTime() + (TIER_BURST_DELAY[tier] or 9999)
	state.pendingApply = false
	ApplyFlameParticles(ent, state, tier)
end)

hook.Add("Think", "bombin_loiter_damage_fx", function()
	local ct = CurTime()
	for idx, state in pairs(LoiterStates) do
		local ent = Entity(idx)

		if not IsValid(ent) then
			for _, pname in ipairs(state.particles) do
				ParticleStopEmission(ent, false, pname)
			end
			LoiterStates[idx] = nil
			continue
		end

		if state.pendingApply ~= false then
			state.tier         = state.pendingApply
			state.nextBurst    = ct + (TIER_BURST_DELAY[state.pendingApply] or 9999)
			state.pendingApply = false
			ApplyFlameParticles(ent, state, state.tier)
		end

		local tier = state.tier
		if tier == 0 then continue end

		if state.nextBurst and ct >= state.nextBurst then
			SpawnBurstFX(ent, tier)
			state.nextBurst = ct + (TIER_BURST_DELAY[tier] or 9999)
		end
	end
end)

function ENT:Initialize()
	local idx = self:EntIndex()
	LoiterStates[idx] = { tier = 0, particles = {}, offsets = {}, pendingApply = false }
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:OnRemove()
	local idx   = self:EntIndex()
	local state = LoiterStates[idx]
	if state then
		for _, pname in ipairs(state.particles) do
			ParticleStopEmission(self, false, pname)
		end
		LoiterStates[idx] = nil
	end
end

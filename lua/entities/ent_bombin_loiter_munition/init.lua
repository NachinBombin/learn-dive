AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

util.AddNetworkString("bombin_loiter_damage_tier")

-- ============================================================
-- SOUNDS
-- ============================================================

local ENGINE_SOUND = "lyutyy/engine_high.wav"
local SHARD_MODEL  = "models/props_c17/FurnitureDrawer001a_Shard01.mdl"
local SHARD_LIFE   = 8

-- ============================================================
-- TUNING
-- ============================================================

ENT.WeaponWindow  = 8
ENT.FadeDuration  = 2.0

ENT.DIVE_Speed         = 1800
ENT.DIVE_TrackInterval = 0.1
ENT.DIVE_GravityMult   = 1.1

-- ============================================================
-- DAMAGE TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
	local pct = hp / maxHP
	if pct > 0.66 then return 0
	elseif pct > 0.33 then return 1
	elseif hp > 0 then return 2
	else return 3 end
end

local function BroadcastTier(ent, tier)
	net.Start("bombin_loiter_damage_tier")
		net.WriteUInt(ent:EntIndex(), 16)
		net.WriteUInt(tier, 2)
	net.Broadcast()
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
	self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
	self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
	self.Lifetime     = self:GetVar("Lifetime",     40)
	self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

	self.DIVE_ExplosionDamage = self:GetVar("DIVE_ExplosionDamage", 350)
	self.DIVE_ExplosionRadius = self:GetVar("DIVE_ExplosionRadius", 600)

	self.MaxHP = 200
	self.DamageTier = 0

	if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
	self.CallDir.z = 0
	self.CallDir:Normalize()

	local ground = self:FindGround(self.CenterPos)
	if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

	local altVariance = self.SkyHeightAdd * 0.25
	self.sky = ground + self.SkyHeightAdd + math.Rand(-altVariance, altVariance)

	self.DieTime   = CurTime() + self.Lifetime
	self.SpawnTime = CurTime()

	local baseRadius = self:GetVar("OrbitRadius", 2500)
	local baseSpeed  = self:GetVar("Speed",        250)
	self.OrbitRadius = baseRadius * math.Rand(0.82, 1.18)
	self.Speed       = baseSpeed  * math.Rand(0.85, 1.15)

	self.OrbitDir    = (math.random(0, 1) == 0) and 1 or -1

	local entryAngle  = math.Rand(0, math.pi * 2)
	local entryOffset = Vector(math.cos(entryAngle), math.sin(entryAngle), 0)
	local spawnPos    = self.CenterPos + entryOffset * (self.OrbitRadius * 1.05)
	spawnPos.z        = self.sky

	if not util.IsInWorld(spawnPos) then
		spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
	end
	if not util.IsInWorld(spawnPos) then
		self:Debug("Spawn position out of world") self:Remove() return
	end

	self:SetModel("models/sw/avia/tb2/tb2.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
	self:SetPos(spawnPos)

	self:SetBodygroup(4, 1)
	self:SetBodygroup(3, 1)
	self:SetBodygroup(5, 2)

	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(255, 255, 255, 0))

	self:SetNWInt("HP",    self.MaxHP)
	self:SetNWInt("MaxHP", self.MaxHP)
	self:SetNWBool("Destroyed", false)

	local tangent = Vector(-entryOffset.y, entryOffset.x, 0) * self.OrbitDir
	local startAng = tangent:Angle()
	self:SetAngles(Angle(0, startAng.y, 0))
	self.ang = self:GetAngles()

	self.SmoothedRoll  = 0
	self.SmoothedPitch = 0
	self.PrevYaw       = self:GetAngles().y

	self.JitterPhase  = math.Rand(0, math.pi * 2)
	self.JitterPhase2 = math.Rand(0, math.pi * 2)
	self.JitterAmp1   = math.Rand(8,  18)
	self.JitterAmp2   = math.Rand(20, 45)
	self.JitterRate1  = math.Rand(0.030, 0.060)
	self.JitterRate2  = math.Rand(0.007, 0.015)

	self.AltDriftCurrent  = self.sky
	self.AltDriftTarget   = self.sky
	self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
	self.AltDriftRange    = 700
	self.AltDriftLerp     = 0.003

	self.BaseCenterPos = Vector(self.CenterPos.x, self.CenterPos.y, self.CenterPos.z)
	self.WanderPhaseX  = math.Rand(0, math.pi * 2)
	self.WanderPhaseY  = math.Rand(0, math.pi * 2)
	self.WanderAmp     = math.Rand(60, 160)
	self.WanderRateX   = math.Rand(0.004, 0.010)
	self.WanderRateY   = math.Rand(0.003, 0.009)

	self.SkyYawBias      = 0
	self.SkyProbeDist    = math.max(1200, self.Speed * 6)
	self.SkyProbeLastHit = 0
	self.ObsLastEval     = 0
	self.ObsYawBias      = 0
	self.ObsAltBias      = 0
	self.ObsConsecHits   = 0

	self.flightYaw     = startAng.y
	self.TurnDelay     = 0

	self.PhysObj = self:GetPhysicsObject()
	if IsValid(self.PhysObj) then
		self.PhysObj:Wake()
		self.PhysObj:EnableGravity(false)
	end

	self.DiveGravityVel = Vector(0, 0, 0)

	-- Single engine loop
	self.EngineLoop = CreateSound(self, ENGINE_SOUND)
	if self.EngineLoop then
		self.EngineLoop:SetSoundLevel(125)
		self.EngineLoop:ChangePitch(100, 0)
		self.EngineLoop:ChangeVolume(1.0, 0.5)
		self.EngineLoop:Play()
	end

	-- Weapon state
	self.CurrentWeapon   = nil
	self.WeaponWindowEnd = 0

	-- Dive state
	self.Diving        = false
	self.DiveTarget    = nil
	self.DiveTargetPos = nil
	self.DiveNextTrack = 0
	self.DiveExploded  = false
	self.DiveAimOffset = Vector(0,0,0)

	self.DiveWobblePhase = 0
	self.DiveWobbleAmp   = 180
	self.DiveWobbleSpeed = 4.5

	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveWobbleAmpV   = 130
	self.DiveWobbleSpeedV = 3.1

	self.DiveSpeedMin     = self.DIVE_Speed * 0.55
	self.DiveSpeedCurrent = self.DIVE_Speed * 0.55
	self.DiveSpeedLerp    = 0.018

	self.DivePitchTelegraph = 0

	-- Death tumble state
	self.Destroyed       = false
	self.DestroyedTime   = nil
	self.TumbleAngVel    = Vector(0,0,0)
	self.ExplodeTimer    = nil
	self.ExplodedAlready = false

	self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDir=" .. self.OrbitDir)
end

-- ============================================================
-- DEATH STATE
-- ============================================================

function ENT:IsDestroyed()
	return self.Destroyed == true
end

function ENT:SpawnDebrisShards()
	local count   = math.random(1, 2)
	local origin  = self:GetPos()
	local baseVel = self:GetVelocity()

	for i = 1, count do
		local shard = ents.Create("prop_physics")
		if not IsValid(shard) then continue end

		shard:SetModel(SHARD_MODEL)
		shard:SetPos(origin + Vector(math.Rand(-30,30), math.Rand(-30,30), math.Rand(-20,20)))
		shard:SetAngles(Angle(math.Rand(0,360), math.Rand(0,360), math.Rand(0,360)))
		shard:Spawn()
		shard:Activate()
		shard:SetColor(Color(15, 10, 10, 255))
		shard:SetMaterial("models/debug/debugwhite")

		local phys = shard:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetVelocity(baseVel * 0.3 + Vector(
				math.Rand(-300, 300),
				math.Rand(-300, 300),
				math.Rand(50,  250)
			))
			phys:AddAngleVelocity(Vector(
				math.Rand(-200, 200),
				math.Rand(-200, 200),
				math.Rand(-200, 200)
			))
		end

		shard:Ignite(SHARD_LIFE, 0)
		timer.Simple(SHARD_LIFE, function()
			if IsValid(shard) then shard:Remove() end
		end)
	end
end

function ENT:SetDestroyed()
	if self.Destroyed then return end
	self.Destroyed = true
	self:SetNWBool("Destroyed", true)
	self.DestroyedTime = CurTime()

	BroadcastTier(self, 3)

	if IsValid(self.PhysObj) then
		self.TumbleAngVel = self.PhysObj:GetAngleVelocity() + Vector(
			math.Rand(-120, 120),
			math.Rand(-120, 120),
			math.Rand(-120, 120)
		)
		self.PhysObj:EnableGravity(true)
		self.PhysObj:AddAngleVelocity(self.TumbleAngVel)
	end

	self:Ignite(20, 0)
	self:SpawnDebrisShards()

	-- Fade engine sound out over 1.5s then hard-stop to guarantee silence
	local FADE = 1.5
	if self.EngineLoop then
		self.EngineLoop:ChangeVolume(0, FADE)
		self.EngineLoop:ChangePitch(55, FADE + 0.5)
		local snd = self.EngineLoop
		self.EngineLoop = nil  -- prevent OnRemove double-stop
		timer.Simple(FADE + 0.2, function()
			if snd then snd:Stop() end
		end)
	end

	local altAboveGround = self:GetPos().z - (self.sky - self.SkyHeightAdd)
	local delay = math.Clamp(altAboveGround / 600, 3, 12)
	self.ExplodeTimer = CurTime() + delay

	if not self.Diving then
		self.CurrentWeapon = nil
	end

	self:Debug("DESTROYED - boom in " .. math.Round(delay,1) .. "s")
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
	if self.ExplodedAlready then return end
	if dmginfo:IsDamageType(DMG_CRUSH) then return end

	local hp = self:GetNWInt("HP", self.MaxHP or 200)
	hp = hp - dmginfo:GetDamage()
	self:SetNWInt("HP", hp)

	local newTier = CalcTier(math.max(hp, 0), self.MaxHP)
	if newTier ~= self.DamageTier then
		self.DamageTier = newTier
		BroadcastTier(self, newTier)
	end

	if hp <= 0 and not self:IsDestroyed() then
		self:Debug("Shot down!")
		self:SetDestroyed()
	end
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
	print("[Bombin Loiter Munition] " .. tostring(msg))
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
	if not self.DieTime or not self.SpawnTime then
		self:NextThink(CurTime() + 0.1)
		return true
	end

	local ct = CurTime()
	if ct >= self.DieTime then self:Remove() return end

	if not IsValid(self.PhysObj) then
		self.PhysObj = self:GetPhysicsObject()
	end
	if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
		self.PhysObj:Wake()
	end

	-- Fade in/out
	if not self:IsDestroyed() then
		local age  = ct - self.SpawnTime
		local left = self.DieTime - ct
		local alpha = 255
		if age < self.FadeDuration then
			alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
		elseif left < self.FadeDuration then
			alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
		end
		self:SetColor(Color(255, 255, 255, math.Round(alpha)))
	end

	if self:IsDestroyed() then
		if self.ExplodeTimer and ct >= self.ExplodeTimer then
			self:CrashExplode(self:GetPos())
			return true
		end
		self:NextThink(ct + 0.05)
		return true
	end

	if self.Diving then
		self:UpdateDive(ct)
	else
		self:HandleWeaponWindow(ct)
	end

	self:NextThink(ct)
	return true
end

-- ============================================================
-- SKY PROBE EVASION (AN-71)
-- ============================================================

function ENT:EvaluateSkyProbes(forward, pos)
	local probeOffsets = { -60, -30, 0, 30, 60 }
	local hitCount     = 0
	local biasSide     = 0

	for _, yawOff in ipairs(probeOffsets) do
		local probeAng = Angle(0, self.flightYaw + yawOff, 0)
		local probeDir = probeAng:Forward()
		probeDir.z     = 0.18
		probeDir:Normalize()

		local trSky = util.TraceLine({
			start  = pos,
			endpos = pos + probeDir * self.SkyProbeDist,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})

		if trSky.Hit and trSky.HitSky then
			hitCount = hitCount + 1
			if yawOff >= 0 then
				biasSide = biasSide - 1
			else
				biasSide = biasSide + 1
			end
		end
		if trSky.Hit and trSky.HitSky and math.abs(yawOff) <= 30 then
			self.SkyProbeLastHit = CurTime()
		end
	end

	if hitCount > 0 then
		local urgency = (CurTime() - self.SkyProbeLastHit < 0.5) and 2.0 or 1.0
		self.SkyYawBias = (biasSide >= 0 and 1 or -1) * 0.25 * urgency * self.OrbitDir
	else
		self.SkyYawBias = self.SkyYawBias * 0.85
		if math.abs(self.SkyYawBias) < 0.001 then self.SkyYawBias = 0 end
	end
end

-- ============================================================
-- OBSTACLE PROBE EVASION (AN-71)
-- ============================================================

function ENT:EvaluateObstacleProbes(forward, pos)
	local ct = CurTime()
	if ct - self.ObsLastEval < 0.08 then return end
	self.ObsLastEval = ct

	local probeDist = math.max(800, self.Speed * 3)
	local yawAngles = { -80, -40, -15, 0, 15, 40, 80 }
	local hitLeft   = 0
	local hitRight  = 0
	local hitFront  = 0

	for _, yawOff in ipairs(yawAngles) do
		local probeAng = Angle(0, self.flightYaw + yawOff, 0)
		local probeDir = probeAng:Forward()
		probeDir.z     = 0

		local tr = util.TraceLine({
			start  = pos,
			endpos = pos + probeDir * probeDist,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})

		if tr.Hit and not tr.HitSky then
			local urgency = 1 + (1 - tr.Fraction) * 2
			if yawOff < -10 then
				hitLeft  = hitLeft  + urgency
			elseif yawOff > 10 then
				hitRight = hitRight + urgency
			else
				hitFront = hitFront + urgency
			end
		end
	end

	local totalHits = hitLeft + hitRight + hitFront
	if totalHits > 0 then
		self.ObsConsecHits = self.ObsConsecHits + 1
	else
		self.ObsConsecHits = 0
	end

	if self.ObsConsecHits >= 4 then
		self.OrbitDir      = -self.OrbitDir
		self.ObsConsecHits = 0
		self:Debug("Obstacle escalation: orbit direction reversed")
	end

	if totalHits > 0 then
		local urgencyScale = (self.ObsConsecHits >= 2) and 2.0 or 1.0
		if hitRight > hitLeft then
			self.ObsYawBias = -0.3 * urgencyScale
		elseif hitLeft > hitRight then
			self.ObsYawBias = 0.3 * urgencyScale
		else
			self.ObsYawBias = self.OrbitDir * 0.3 * urgencyScale
		end
		if hitFront > 1.5 then
			self.ObsAltBias = math.Rand(120, 260)
		end
	else
		self.ObsYawBias = self.ObsYawBias * 0.80
		self.ObsAltBias = self.ObsAltBias * 0.92
		if math.abs(self.ObsYawBias) < 0.001 then self.ObsYawBias = 0 end
		if math.abs(self.ObsAltBias) < 1     then self.ObsAltBias = 0 end
	end
end

-- ============================================================
-- FLIGHT  (AN-71 forward-fly orbit - no teleports)
-- ============================================================

function ENT:PhysicsUpdate(phys)
	if not self.DieTime or not self.sky then return end
	if CurTime() >= self.DieTime then self:Remove() return end

	if self:IsDestroyed() then
		local dt = FrameTime()
		if dt <= 0 then dt = 0.01 end

		local angVel = phys:GetAngleVelocity()
		phys:AddAngleVelocity(angVel * 0.08 * dt * 60)

		local extraG = -600 * (self.DIVE_GravityMult - 1) * phys:GetMass()
		phys:ApplyForceCenter(Vector(0, 0, extraG))

		local pos  = self:GetPos()
		local vel  = phys:GetVelocity()
		local next = pos + vel * dt + Vector(0, 0, -24)
		local tr = util.TraceLine({
			start  = pos,
			endpos = next,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if tr.Hit then self:CrashExplode(tr.HitPos) end
		return
	end

	if self.Diving then return end

	local dt = FrameTime()
	if dt <= 0 then dt = 0.01 end

	local pos     = self:GetPos()
	local forward = self:GetForward()

	self.WanderPhaseX = self.WanderPhaseX + self.WanderRateX
	self.WanderPhaseY = self.WanderPhaseY + self.WanderRateY
	self.CenterPos = Vector(
		self.BaseCenterPos.x + math.sin(self.WanderPhaseX) * self.WanderAmp,
		self.BaseCenterPos.y + math.sin(self.WanderPhaseY) * self.WanderAmp,
		self.BaseCenterPos.z
	)

	self:EvaluateSkyProbes(forward, pos)
	self:EvaluateObstacleProbes(forward, pos)

	local flat2D = Vector(pos.x - self.CenterPos.x, pos.y - self.CenterPos.y, 0)
	local dist2D = flat2D:Length()

	if dist2D > self.OrbitRadius and CurTime() > self.TurnDelay then
		self.flightYaw = self.flightYaw + 0.12 * self.OrbitDir
		self.TurnDelay = CurTime() + 0.02
	end

	self.flightYaw = self.flightYaw
	              + math.deg(self.SkyYawBias) * dt
	              + math.deg(self.ObsYawBias) * dt

	self.JitterPhase  = self.JitterPhase  + self.JitterRate1
	self.JitterPhase2 = self.JitterPhase2 + self.JitterRate2
	local jitter = math.sin(self.JitterPhase)  * self.JitterAmp1
	             + math.sin(self.JitterPhase2) * self.JitterAmp2

	if CurTime() >= self.AltDriftNextPick then
		self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

	local targetZ  = self.AltDriftCurrent + jitter + self.ObsAltBias
	local altError = targetZ - pos.z
	local velZ     = math.Clamp(altError * 2.5, -120, 120)

	local yawRad    = math.rad(self.flightYaw)
	local flatFwd   = Vector(math.cos(yawRad), math.sin(yawRad), 0)
	local vel       = flatFwd * self.Speed
	vel.z           = velZ

	local rawYawDelta = math.NormalizeAngle(self.flightYaw - (self.PrevYaw or self.flightYaw))
	self.PrevYaw      = self.flightYaw

	local targetRoll  = math.Clamp(rawYawDelta * -25, -30, 30)
	local rollLerp    = rawYawDelta ~= 0 and 0.15 or 0.05
	self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

	local forwardSpeed = vel:Dot(flatFwd)
	local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
	local targetPitch  = math.Clamp(speedRatio * 10, -15, 15)
	self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, targetPitch)

	self.ang = Angle(self.SmoothedPitch, self.flightYaw, self.SmoothedRoll)
	self:SetAngles(self.ang)

	if IsValid(phys) then
		phys:SetVelocity(vel)
	end

	if not self:IsInWorld() then
		self:Debug("Out of world - recentering yaw")
		local toCenter = self.CenterPos - pos
		toCenter.z = 0
		if toCenter:LengthSqr() > 1 then
			self.flightYaw = toCenter:Angle().y
		end
	end
end

-- ============================================================
-- TARGET HELPER
-- ============================================================

function ENT:GetPrimaryTarget()
	local closest, closestDist = nil, math.huge
	for _, ply in ipairs(player.GetAll()) do
		if not IsValid(ply) or not ply:Alive() then continue end
		local d = ply:GetPos():DistToSqr(self.CenterPos)
		if d < closestDist then closestDist = d closest = ply end
	end
	return closest
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow(ct)
	if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
		self:PickNewWeapon(ct)
	end

	if self.CurrentWeapon == "dive" then
		self:InitDive(ct)
	end
end

function ENT:PickNewWeapon(ct)
	local roll = math.random(1, 3)
	if roll == 1 then
		self.CurrentWeapon = "peaceful_1"
	elseif roll == 2 then
		self.CurrentWeapon = "peaceful_2"
	else
		self.CurrentWeapon = "dive"
	end

	self.WeaponWindowEnd = ct + self.WeaponWindow
	self:Debug("Behavior slot: " .. self.CurrentWeapon)
end

-- ============================================================
-- SLOT 3 - DIVE
-- ============================================================

function ENT:InitDive(ct)
	if self.Diving then return end

	if not self.DiveCommitTime then
		self.DiveCommitTime = ct + 1.0
		self:Debug("DIVE: locking target in 1s...")
		return
	end

	local commitFraction    = math.Clamp((ct - (self.DiveCommitTime - 1.0)) / 1.0, 0, 1)
	self.DivePitchTelegraph = commitFraction * -60
	self:SetAngles(Angle(self.DivePitchTelegraph, self.ang.y, self.SmoothedRoll))

	if ct < self.DiveCommitTime then return end

	local target = self:GetPrimaryTarget()
	if not IsValid(target) then
		self.CurrentWeapon      = nil
		self.DiveCommitTime     = nil
		self.DivePitchTelegraph = 0
		return
	end

	self.Diving             = true
	self.DiveTarget         = target
	self.DiveTargetPos      = target:GetPos()
	self.DiveNextTrack      = ct
	self.DiveExploded       = false
	self.DiveCommitTime     = nil
	self.DivePitchTelegraph = 0

	self.DiveWobblePhase  = 0
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveSpeedCurrent = self.DiveSpeedMin
	self.DiveGravityVel   = Vector(0, 0, 0)

	self.DiveAimOffset = Vector(
		math.Rand(-400, 400),
		math.Rand(-400, 400),
		0
	)

	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetSolid(SOLID_VPHYSICS)

	if IsValid(self.PhysObj) then
		self.PhysObj:EnableGravity(false)
	end

	self:Debug("DIVE: committed - aim offset " .. tostring(self.DiveAimOffset))
end

function ENT:UpdateDive(ct)
	if self.DiveExploded then return end

	if ct >= self.DiveNextTrack then
		if not self:IsDestroyed() then
			if IsValid(self.DiveTarget) and self.DiveTarget:Alive() then
				local trackJitter = Vector(
					math.Rand(-120, 120),
					math.Rand(-120, 120),
					0
				)
				self.DiveTargetPos = self.DiveTarget:GetPos() + trackJitter
			end
		end
		self.DiveNextTrack = ct + self.DIVE_TrackInterval
	end

	if not self.DiveTargetPos then self:Remove() return end

	local aimPos = self.DiveTargetPos + self.DiveAimOffset
	local myPos  = self:GetPos()
	local dir    = aimPos - myPos
	local dist   = dir:Length()

	if dist < 120 then
		if self:IsDestroyed() then
			self:CrashExplode(myPos)
		else
			self:DiveExplode(myPos)
		end
		return
	end

	dir:Normalize()

	if self:IsDestroyed() then return end

	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()

	self.DiveWobblePhase = self.DiveWobblePhase + self.DiveWobbleSpeed * dt
	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1, 0, 0) end
	flatRight:Normalize()

	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt
	local worldUp = Vector(0, 0, 1)
	local upPerp  = worldUp - dir * dir:Dot(worldUp)
	if upPerp:LengthSqr() < 0.01 then upPerp = Vector(0, 1, 0) end
	upPerp:Normalize()

	local wobbleScale = math.Clamp(dist / 400, 0, 1)

	local wobbleVel =
		flatRight * math.sin(self.DiveWobblePhase)  * self.DiveWobbleAmp  * wobbleScale +
		upPerp    * math.sin(self.DiveWobblePhaseV) * self.DiveWobbleAmpV * wobbleScale

	self.DiveGravityVel = self.DiveGravityVel + Vector(0, 0, -600 * self.DIVE_GravityMult) * dt

	local totalVel = dir * self.DiveSpeedCurrent + wobbleVel + self.DiveGravityVel

	if totalVel:LengthSqr() > 0.01 then
		local travelDir = totalVel:GetNormalized()
		local faceAng   = travelDir:Angle()
		faceAng.r       = 0
		self:SetAngles(faceAng)
		self.ang = faceAng
	end

	local nextPos = myPos + totalVel * dt
	local tr = util.TraceLine({
		start  = myPos,
		endpos = nextPos,
		filter = self,
		mask   = MASK_SOLID,
	})

	if tr.Hit then
		self:DiveExplode(tr.HitPos)
		return
	end

	if IsValid(self.PhysObj) then
		self.PhysObj:SetVelocity(totalVel)
	end
end

-- ============================================================
-- EXPLOSIONS
-- ============================================================

function ENT:DiveExplode(pos)
	if self.DiveExploded then return end
	self.DiveExploded    = true
	self.ExplodedAlready = true

	self:Debug("DIVE: exploding at " .. tostring(pos))

	local ed1 = EffectData()
	ed1:SetOrigin(pos)
	ed1:SetScale(5) ed1:SetMagnitude(5) ed1:SetRadius(500)
	util.Effect("HelicopterMegaBomb", ed1, true, true)

	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetScale(4) ed2:SetMagnitude(4) ed2:SetRadius(400)
	util.Effect("500lb_air", ed2, true, true)

	local ed3 = EffectData()
	ed3:SetOrigin(pos + Vector(0,0,60))
	ed3:SetScale(3) ed3:SetMagnitude(3) ed3:SetRadius(300)
	util.Effect("500lb_air", ed3, true, true)

	sound.Play("weapon_AWP.Single",               pos, 145, 60, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius, self.DIVE_ExplosionDamage)
	self:Remove()
end

function ENT:CrashExplode(pos)
	if self.ExplodedAlready then return end
	self.ExplodedAlready = true

	self:Debug("CRASH: exploding at " .. tostring(pos))

	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(3) ed:SetMagnitude(3) ed:SetRadius(300)
	util.Effect("HelicopterMegaBomb", ed, true, true)

	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetScale(2) ed2:SetMagnitude(2) ed2:SetRadius(200)
	util.Effect("500lb_air", ed2, true, true)

	sound.Play("ambient/explosions/explode_8.wav", pos, 135, 85, 1.0)

	local crashDmg = self.DIVE_ExplosionDamage * 0.3
	local crashRad = self.DIVE_ExplosionRadius * 0.6
	util.BlastDamage(self, self, pos, crashRad, crashDmg)
	self:Remove()
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
	local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
	local endPos     = Vector(centerPos.x, centerPos.y, -16384)
	local filterList = { self }
	local maxIter    = 0

	while maxIter < 100 do
		local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
		if tr.HitWorld then return tr.HitPos.z end
		if IsValid(tr.Entity) then
			table.insert(filterList, tr.Entity)
		else
			break
		end
		maxIter = maxIter + 1
	end

	return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
	-- EngineLoop is nilled out in SetDestroyed after fade starts,
	-- so this only fires for non-death removals (lifetime expiry, etc.)
	if self.EngineLoop then
		self.EngineLoop:Stop()
		self.EngineLoop = nil
	end
end

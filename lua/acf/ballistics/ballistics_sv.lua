local hook        = hook
local ACF         = ACF
local Ballistics  = ACF.Ballistics
local Damage      = ACF.Damage
local Clock       = ACF.Utilities.Clock
local Effects     = ACF.Utilities.Effects
local EventViewer = ACF.EventViewer

Ballistics.Bullets         = Ballistics.Bullets or {}
Ballistics.UnusedIndexes   = Ballistics.UnusedIndexes or {}
Ballistics.HighestIndex    = Ballistics.HighestIndex or 0
Ballistics.SkyboxGraceZone = Ballistics.SkyboxGraceZone or 100

local function GetEventViewerName(Idx) return "Ballistics - Bullet #" .. Idx end


local Bullets      = Ballistics.Bullets
local Unused       = Ballistics.UnusedIndexes
local IndexLimit   = 2000
local SkyGraceZone = Ballistics.SkyboxGraceZone
local FlightTr     = { start = true, endpos = true, filter = true, mask = true }
local GlobalFilter = ACF.GlobalFilter
local ArmorTypes   = ACF.Classes.ArmorTypes

-- This will create, or update, the tracer effect on the clientside
function Ballistics.BulletClient(Bullet, Type, Hit, HitPos)
	if Bullet.NoEffect then return end -- No clientside effect will be created for this bullet

	local IsUpdate = Type == "Update"
	local EffectTable = {
		DamageType = Bullet.Index,
		Start = Bullet.Flight * 0.1,
		Attachment = Bullet.Hide and 0 or 1,
		Origin = (IsUpdate and Hit > 0) and HitPos or Bullet.Pos,
		Scale = (not Bullet.Hide and IsUpdate) and Hit or 0,
		EntIndex = not IsUpdate and Bullet.Crate or nil,
	}

	Effects.CreateEffect("ACF_Bullet_Effect", EffectTable, true, true)
end

function Ballistics.RemoveBullet(Bullet)
	if Bullet.Removed then return end

	local Index = Bullet.Index

	Bullets[Index] = nil
	Unused[Index]  = true

	if Bullet.OnRemoved then
		Bullet:OnRemoved()
	end

	if EventViewer.Enabled() then
		EventViewer.AppendEvent(GetEventViewerName(Index), "Ballistics.RemoveBullet")
	end
	Bullet.Removed = true

	if not next(Bullets) then
		hook.Remove("ACF_OnTick", "ACF Iterate Bullets")
	end
end

function Ballistics.CalcBulletFlight(Bullet)
	local ClockTime = Clock.CurTime

	if Bullet.KillTime and ClockTime >= Bullet.KillTime then
		return Ballistics.RemoveBullet(Bullet)
	end

	if Bullet.PreCalcFlight then
		Bullet:PreCalcFlight()
	end

	local DeltaTime  = ClockTime - Bullet.LastThink
	local Flight     = Bullet.Flight
	local Drag       = Flight:GetNormalized() * (Bullet.DragCoef * Flight:LengthSqr()) / ACF.DragDiv
	local Accel      = Bullet.Accel or ACF.Gravity
	local Correction = 0.5 * (Accel - Drag) * DeltaTime

	Bullet.NextPos   = Bullet.Pos + ACF.Scale * DeltaTime * (Flight + Correction)
	Bullet.TraceTo   = Bullet.Pos + ACF.Scale * (DeltaTime * 2) * (Flight + Correction)
	Bullet.Flight    = Flight + (Accel - Drag) * DeltaTime
	Bullet.LastThink = ClockTime
	Bullet.DeltaTime = DeltaTime

	Ballistics.DoBulletsFlight(Bullet)

	if Bullet.PostCalcFlight then
		Bullet:PostCalcFlight()
	end

	debugoverlay.Line(Bullet.Pos, Bullet.NextPos, 15, Bullet.Color, true)
	Bullet.Pos = Bullet.NextPos
end

function Ballistics.GetBulletIndex()
	if next(Unused) then
		local Index = next(Unused)

		Unused[Index] = nil

		return Index
	end

	local Index = Ballistics.HighestIndex + 1

	if Index > IndexLimit then return end

	Ballistics.HighestIndex = Index

	return Index
end

function Ballistics.IterateBullets()
	for _, Bullet in pairs(Bullets) do
		if not Bullet.HandlesOwnIteration then
			Ballistics.CalcBulletFlight(Bullet)
		end
	end
end


local RequiredBulletDataProperties = {"Pos", "Flight"}
function Ballistics.CreateBullet(BulletData)
	local Index = Ballistics.GetBulletIndex()
	if not Index then return end -- Too many bullets in the air

	-- Validate BulletData, so we can catch these problems easier

	for _, RequiredProp in ipairs(RequiredBulletDataProperties) do
		if not BulletData[RequiredProp] then
			error(("Ballistics.CreateBullet: Expected '%s' to be present in BulletData, got nil!"):format(RequiredProp))
		end
	end

	local Bullet = table.Copy(BulletData)
	Bullet.TypeDef = ACF.Classes.GetSubtypeByName("ACF.Ammunition.BaseAmmo", Bullet.AmmoType)
	if not Bullet.TypeDef then
		error("Bullet.AmmoType was probably wrong, review: " .. tostring(Bullet.AmmoType))
	end

	if not Bullet.Filter then
		Bullet.Filter = IsValid(Bullet.Gun) and { Bullet.Gun } or {}
	end

	Bullet.Index       = Index
	Bullet.LastThink   = Clock.CurTime
	Bullet.Fuze        = Bullet.Fuze and Bullet.Fuze + Clock.CurTime or nil -- Convert Fuze from fuze length to time of detonation
	if Bullet.Caliber then
		Bullet.Mask		= (Bullet.Caliber < 3 and bit.band(MASK_SOLID, MASK_SHOT) or MASK_SOLID) -- I hope CONTENTS_AUX isn't used for anything important? I can't find any references outside of the wiki to it so hopefully I can use this
	else
		Bullet.Mask		= MASK_SOLID
	end

	Bullet.Ricochets   = Bullet.Ricochets or 0
	Bullet.GroundRicos = Bullet.GroundRicos or 0
	Bullet.Color       = ColorRand(100, 255)
	Bullet.Mode        = "Flight" -- Flight follows the ballistic arc, Penetration walks a frozen ray through armor

	-- Purely to allow someone to shoot out of a seat without hitting themselves and dying
	if IsValid(Bullet.Owner) and Bullet.Owner:IsPlayer() and Bullet.Owner:InVehicle() and (Bullet.Gun and Bullet.Gun:GetClass() ~= "acf_gun") then
		Bullet.Filter[#Bullet.Filter + 1] = Bullet.Owner:GetVehicle()
	end

	if EventViewer.Enabled() then
		EventViewer.StartEvent(GetEventViewerName(Index))
		-- Network the whole bullet state when event viewer is active.
		EventViewer.AppendEvent(GetEventViewerName(Index), "Ballistics.CreateBullet", Bullet)
	end

	-- TODO: Make bullets use a metatable instead
	-- Bullet.PenetrationOverride lets standoff-dependent ammo types (HEAT) report their real current penetration instead of the Standoff-less placeholder.
	function Bullet:GetPenetration()
		if Bullet.PenetrationOverride then return Bullet.PenetrationOverride end

		return Bullet.TypeDef:GetPenetration(self)
	end

	if not next(Bullets) then
		hook.Add("ACF_OnTick", "ACF Iterate Bullets", Ballistics.IterateBullets)
	end

	Bullets[Index] = Bullet

	Ballistics.BulletClient(Bullet, "Init", 0)
	Ballistics.CalcBulletFlight(Bullet)

	return Bullet
end

function Ballistics.GetImpactType(Trace, Entity)
	if Trace.HitWorld then return "World" end
	if Entity:IsPlayer() or Entity:IsNPC() or Entity:IsNextBot() then return "Prop" end

	return IsValid(Entity:CPPIGetOwner()) and "Prop" or "World"
end

function Ballistics.OnImpact(Bullet, Trace, Ammo, Type)
	local Func  = Type == "World" and Ammo.WorldImpact or Ammo.PropImpact
	local Retry = Func(Ammo, Bullet, Trace)

	if Retry == "Penetrated" then
		if Bullet.OnPenetrated then
			Bullet.OnPenetrated(Bullet, Trace)
		end

		Ballistics.BulletClient(Bullet, "Update", 2, Trace.HitPos)
		Ballistics.DoBulletsFlight(Bullet)
		if EventViewer.Enabled() then
			EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.OnImpact.Penetrated", Trace.StartPos, Trace.HitPos, Trace)
		end
	elseif Retry == "Ricochet" then
		Ballistics.EndPenetration(Bullet) -- New heading, so the frozen penetration ray no longer applies

		if Bullet.OnRicocheted then
			Bullet.OnRicocheted(Bullet, Trace)
		end

		Ballistics.BulletClient(Bullet, "Update", 3, Trace.HitPos)
		Ballistics.DoBulletsFlight(Bullet)
		if EventViewer.Enabled() then
			EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.OnImpact.Ricochet", Trace.StartPos, Trace.HitPos, Trace)
		end
	else
		Ballistics.EndPenetration(Bullet)

		if Bullet.OnEndFlight then
			Bullet.OnEndFlight(Bullet, Trace)
		end

		Ballistics.BulletClient(Bullet, "Update", 1, Trace.HitPos)
		if EventViewer.Enabled() then
			EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.OnImpact.Unknown", Trace.StartPos, Trace.HitPos, Trace)
		end
		Ammo:OnFlightEnd(Bullet, Trace)
	end
end

-- Marks a single convex of an entity as transparent to this bullet for the rest of its flight.
-- Used when a projectile penetrates a convex so subsequent re-traces advance to the next one.
function Ballistics.FilterConvex(Bullet, Entity, ConvexID)
	local ConvexFilter = Bullet.ConvexFilter

	if not ConvexFilter then
		ConvexFilter = {}
		Bullet.ConvexFilter = ConvexFilter
	end

	local EntFilter = ConvexFilter[Entity]

	if not EntFilter then
		EntFilter = {}
		ConvexFilter[Entity] = EntFilter
	end

	EntFilter[ConvexID] = true
end

function Ballistics.TestFilter(Entity, Bullet)
	if not IsValid(Entity) then return true end

	if GlobalFilter[Entity:GetClass()] then return false end

	if not hook.Run("ACF_OnFilterBullet", Entity, Bullet) then return false end

	local EntTbl = Entity:GetTable()

	if ACF.FilterMakeSpherical and EntTbl._IsSpherical then return false end -- TODO: Remove when damage changes make props unable to be destroyed, as physical props can have friction reduced (good for wheels)
	if EntTbl.ACF_InvisibleToBallistics then return false end
	if EntTbl.ACF_KillableButIndestructible then
		local EntACF = EntTbl.ACF
		if EntACF and EntACF.Health <= 0 then return false end
	end
	if EntTbl.ACF_TestFilter then return EntTbl.ACF_TestFilter(Entity, Bullet) end

	return true
end

-- Every live, unfiltered mesh intersection the ACF-meshed entities along Start -> EndPos present,
-- gathered with a single ents.FindAlongRay. Unsorted; feed it to ACF.ResolveConvexStack.
local function GatherMeshIntersections(Bullet, Start, Direction, EndPos)
	local TraceTo       = EndPos or Bullet.TraceTo
	local FoundEnts     = ents.FindAlongRay(Start, TraceTo) -- bounds discovery to this segment, same as the physics trace already covers
	local MaxDist       = Start:Distance(TraceTo) -- and bounds the mesh rays to match, so convexes past the segment cost nothing
	local Intersections = {}

	for _, Ent in ipairs(FoundEnts) do
		if not Ent.ACF_Volumetric_Mesh then continue end
		if table.HasValue(Bullet.Filter, Ent) then continue end

		if not Ballistics.TestFilter(Ent, Bullet) then
			table.insert(Bullet.Filter, Ent) -- same "filtered for the rest of this bullet's life" semantics as today's whole-entity filter
			continue
		end

		local EntConvexFilter = Bullet.ConvexFilter and Bullet.ConvexFilter[Ent]
		local Hits            = ACF.RayIntersectMesh(Ent, Start, Direction, false, nil, EntConvexFilter, MaxDist)

		for _, Hit in ipairs(Hits) do
			Intersections[#Intersections + 1] = Hit
		end
	end

	return Intersections
end

do -- Obstacle resolution --------------------------
	-- A projectile in flight mode looks ahead with one cheap physics trace. The moment that trace lands on
	-- a meshed entity it switches to penetration mode: the ray is frozen at the impact point, a single
	-- ents.FindAlongRay resolves every convex standing on that line, and the projectile walks the whole
	-- stack in one instant. Nothing advances its position and no gravity is integrated in between, so it
	-- stays exactly on the frozen line until it stops, ricochets, or runs out of stack and returns to flight.
	--
	-- Shared by bullets and spall fragments. Both keep their own motion model and impact handling and use
	-- this only to find what they run into next, so a projectile here is anything carrying Pos, TraceTo,
	-- Flight and Filter.

	local MaxPenetrations = 50 -- Convexes a projectile can cross in one pass before the rest of the line is left for later

	-- Freezes the ray at Trace.HitPos and builds the ordered convex stack the projectile will walk.
	-- Returns false when nothing on the line is left to hit, leaving it in flight mode.
	function Ballistics.BeginPenetration(Projectile, Trace)
		local Direction = Projectile.Flight:GetNormalized()
		local Start     = Trace.HitPos - Direction * 2 -- same backoff ACF.GetConvexHits uses
		local Stack     = ACF.ResolveConvexStack(GatherMeshIntersections(Projectile, Start, Direction), Direction)

		if #Stack == 0 then return false end

		for Index = #Stack, MaxPenetrations + 1, -1 do
			Stack[Index] = nil
		end

		Projectile.Mode     = "Penetration"
		Projectile.PenStack = Stack
		Projectile.PenIndex = 0
		Projectile.PenTrace = Trace -- Reused for every convex so the damage code keeps the physics trace's other fields

		return true
	end

	-- Drops the frozen ray and puts the projectile back on its own flight path.
	function Ballistics.EndPenetration(Projectile)
		Projectile.Mode      = "Flight"
		Projectile.PenStack  = nil
		Projectile.PenIndex  = nil
		Projectile.PenTrace  = nil
		Projectile.ConvexHit = nil
	end

	-- Every live convex on Start -> End across all meshed entities, resolved as one stack so layers see neighbors
	-- in other entities, then grouped per entity in hit order. Used by jets, which resolve armor entity by entity.
	function Ballistics.GetEntityHits(Projectile, Start, End)
		local Direction = (End - Start):GetNormalized()
		local Stack     = ACF.ResolveConvexStack(GatherMeshIntersections(Projectile, Start, Direction, End), Direction)
		local ByEntity  = {}

		for _, Hit in ipairs(Stack) do
			local List = ByEntity[Hit.Entity]

			if not List then
				List = {}
				ByEntity[Hit.Entity] = List
			end

			List[#List + 1] = Hit
		end

		return ByEntity
	end

	-- The next live convex on the frozen ray with the penetration trace spliced onto it, or nil once the
	-- stack is walked out, which retires it and returns the projectile to flight mode.
	local function NextConvex(Projectile)
		local Stack = Projectile.PenStack

		while true do
			local Index = Projectile.PenIndex + 1
			local Hit   = Stack[Index]

			if not Hit then break end

			Projectile.PenIndex = Index

			-- The stack was resolved before the first impact landed, so anything an earlier convex destroyed
			-- on the way through (a killed entity, a spent reactive plate) is transparent by now and skipped.
			local Entity   = Hit.Entity
			local MeshData = IsValid(Entity) and Entity.ACF_Volumetric_Mesh
			local Convex   = MeshData and MeshData.Convexes[Hit.ConvexID]

			if Convex and Convex.Health > 0 then
				-- Splice the resolved hit into the trace so downstream code sees the convex actually struck,
				-- even when it belongs to an entity the physics trace never reported.
				local Trace = Projectile.PenTrace

				Trace.Entity    = Entity
				Trace.HitPos    = Hit.EntryPos
				Trace.HitNormal = Hit.EntryNormal

				return Trace, Hit
			end
		end

		-- Walked the line to its end, so every entity on it is spent. Filtering them lets the resumed
		-- trace reach the world, players and anything else meshless sitting behind them.
		local Filter = Projectile.Filter

		for _, Spent in ipairs(Stack) do
			if not table.HasValue(Filter, Spent.Entity) then
				Filter[#Filter + 1] = Spent.Entity
			end
		end

		Ballistics.EndPenetration(Projectile)
	end

	-- What the projectile runs into next along Pos -> TraceTo, as the trace (hit or not) plus the convex
	-- hit when it landed on armor. Steps the frozen ray while in penetration mode, otherwise traces,
	-- skipping past anything it should ignore and entering penetration mode on the first meshed entity.
	function Ballistics.ResolveNextObstacle(Projectile)
		if Projectile.Mode == "Penetration" then
			local PenTrace, Hit = NextConvex(Projectile)

			if Hit then return PenTrace, Hit end
		end

		-- Every retry adds an entity to the filter, so this drains rather than spinning. Retrying here
		-- instead of next tick matters: letting the projectile advance first would skip anything sitting
		-- behind the entity it just gave up on within the current segment.
		while true do
			FlightTr.mask   = Projectile.Mask
			FlightTr.filter = Projectile.Filter
			FlightTr.start  = Projectile.Pos
			FlightTr.endpos = Projectile.TraceTo

			local Trace = ACF.trace(FlightTr) -- Does not modify the projectile's original filter

			if not Trace.Hit or Trace.HitSky then return Trace end

			local Entity = Trace.Entity

			if not Ballistics.TestFilter(Entity, Projectile) then
				-- Important in case something is embedded in something that shouldn't be hit
				table.insert(Projectile.Filter, Entity)
			elseif not Entity.ACF_Volumetric_Mesh then
				return Trace
			elseif Ballistics.BeginPenetration(Projectile, Trace) then
				local PenTrace, Hit = NextConvex(Projectile)

				if Hit then return PenTrace, Hit end
			else
				table.insert(Projectile.Filter, Entity) -- Nothing live left on its mesh anywhere along the line
			end
		end
	end
end

function Ballistics.DoBulletsFlight(Bullet)
	local CanFly = hook.Run("ACF_PreBulletFlight", Bullet)

	if not CanFly then return end

	if Bullet.SkyLvL then
		if Clock.CurTime - Bullet.LifeTime > 30 then
			return Ballistics.RemoveBullet(Bullet)
		end

		if Bullet.NextPos.z + SkyGraceZone > Bullet.SkyLvL then
			if Bullet.Fuze and Bullet.Fuze <= Clock.CurTime then -- Fuze detonated outside map
				Ballistics.RemoveBullet(Bullet)
			end

			return
		elseif not util.IsInWorld(Bullet.NextPos) then
			return Ballistics.RemoveBullet(Bullet)
		else
			Bullet.SkyLvL = nil
			Bullet.LifeTime = nil

			return
		end
	end

	local traceRes, ConvexHit = Ballistics.ResolveNextObstacle(Bullet)

	if Bullet.Fuze and Bullet.Fuze <= Clock.CurTime then
		if not util.IsInWorld(Bullet.Pos) then -- Outside world, just delete
			return Ballistics.RemoveBullet(Bullet)
		else
			local DeltaTime = Bullet.DeltaTime
			local DeltaFuze = Clock.CurTime - Bullet.Fuze
			local Lerp = DeltaFuze / DeltaTime

			if not traceRes.Hit or Lerp < traceRes.Fraction then -- Fuze went off before running into something
				Ballistics.EndPenetration(Bullet) -- Flight is over, so a stack resolved this tick goes unwalked

				Bullet.Pos       = LerpVector(Lerp, Bullet.Pos, Bullet.NextPos)
				Bullet.DetByFuze = true

				if Bullet.OnEndFlight then
					Bullet.OnEndFlight(Bullet, traceRes)
				end

				Ballistics.BulletClient(Bullet, "Update", 1, Bullet.Pos)

				Bullet.TypeDef:OnFlightEnd(Bullet, traceRes)
				if EventViewer.Enabled() then
					EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.DoBulletsFlight.Fuze")
				end

				return
			end
		end
	end


	if EventViewer.Enabled() then
		if ConvexHit then
			EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.DoPenetration", ConvexHit.EntryPos, ConvexHit.ExitPos)
		else
			EventViewer.AppendEvent(GetEventViewerName(Bullet.Index), "Ballistics.DoBulletsFlight", Bullet.Pos, Bullet.NextPos, FlightTr)
		end
	end

	if traceRes.Hit then
		if traceRes.HitSky then
			if traceRes.HitNormal == -vector_up then
				Bullet.SkyLvL = traceRes.HitPos.z
				Bullet.LifeTime = Clock.CurTime
			else
				Ballistics.RemoveBullet(Bullet)
			end
		else
			-- Stored on the bullet rather than the trace: the EventViewer networks the trace table, and a
			-- convex hit carries its ArmorType (a class object with functions) which can't be serialized.
			Bullet.ConvexHit = ConvexHit

			Ballistics.OnImpact(Bullet, traceRes, Bullet.TypeDef, Ballistics.GetImpactType(traceRes, traceRes.Entity))
		end
	end
end

do -- Terminal ballistics --------------------------
	function Ballistics.GetRicochetVector(Flight, HitNormal)
		local Normal = Flight:GetNormalized()

		return Normal - (2 * Normal:Dot(HitNormal)) * HitNormal
	end

	-- Re-seeds a bullet's flight after a ricochet and resets Pos/NextPos/TraceTo so the immediate
	-- re-trace this tick (triggered by OnImpact's "Ricochet" branch) starts from the ricochet point.
	-- Speed is unscaled (real-world) velocity; Spread is the VectorRand jitter magnitude.
	function Ballistics.ApplyRicochet(Bullet, Position, HitNormal, Speed, Ricochet, Spread, DeltaTime)
		local Direction = Ballistics.GetRicochetVector(Bullet.Flight, HitNormal) + VectorRand() * Spread
		local Flight    = Direction:GetNormalized() * Speed * Ricochet * ACF.Scale

		Bullet.Flight  = Flight
		Bullet.Pos     = Position
		Bullet.NextPos = Position + Flight * DeltaTime
		Bullet.TraceTo = Position + Flight * (DeltaTime * 2)
	end

	local RicochetHardness = 5 -- Degrees the ricochet center shifts per e-fold of face hardness over RHA, clamped to two e-folds

	-- HitAngle (optional) overrides the angle derived from the physical trace; the per-convex impact
	-- path passes the struck convex's entry angle so ricochets evaluate against the real convex face.
	function Ballistics.CalculateRicochet(Bullet, Trace, HitAngle)
		HitAngle = HitAngle or ACF.GetHitAngle(Trace, Bullet.Flight)
		-- Ricochet distribution center
		local sigmoidCenter = Bullet.DetonatorAngle or (Bullet.Ricochet - math.abs(Bullet.Speed / ACF.MeterToInch - Bullet.LimitVel) / 100)

		-- Harder faces turn rounds away at shallower obliquity, soft ones grip them (Hazell 4.3.3)
		local ConvexHit = Bullet.ConvexHit
		if ConvexHit and not Bullet.DetonatorAngle then
			sigmoidCenter = sigmoidCenter - RicochetHardness * math.Clamp(math.log(math.max(ConvexHit.ArmorType.Hardness, 0.01)), -2, 2)
		end

		-- Ricochet probability (sigmoid distribution); up to 5% minimal ricochet probability for projectiles with caliber < 20 mm
		local ricoProb = math.Clamp(1 / (1 + math.exp((HitAngle - sigmoidCenter) / -4)), math.max(-0.05 * (Bullet.Caliber - 2) / 2, 0), 1)

		-- Checking for ricochet
		local Ricochet = 0
		local Loss     = 0
		if ricoProb > math.random() and HitAngle < 90 then
			Ricochet = math.Clamp(HitAngle / 90, 0.05, 1) -- atleast 5% of energy is kept
			Loss     = 0.25 - Ricochet
		end
		return Ricochet, Loss
	end

	function Ballistics.DoRoundImpact(Bullet, Trace)
		local DmgResult, DmgInfo = Damage.getBulletDamage(Bullet, Trace)
		local Speed    = Bullet.Speed
		local Energy   = Bullet.Energy
		local Entity   = Trace.Entity
		local HitRes   = Damage.dealDamage(Entity, DmgResult, DmgInfo)
		local Ricochet = 0

		-- When the impact was resolved against a specific convex, ricochet, knockback and effects
		-- should use that convex's entry face/position instead of the entity's outer physical surface.
		local ConvexHit  = Bullet.ConvexHit
		local ImpactPos  = ConvexHit and ConvexHit.EntryPos or Trace.HitPos
		local HitNormal  = ConvexHit and ConvexHit.EntryNormal or Trace.HitNormal
		local HitAngle   = ConvexHit and ConvexHit.HitAngle or nil

		-- Determine this before ricochetting
		if (HitRes.Kill or (HitRes.Overkill and HitRes.Overkill > 0)) and not Bullet.IsSpall and not Bullet.IsCookOff then
			-- Penetrated or killed plate
			Ballistics.DoSpall(Bullet, Trace, HitRes, Bullet.Flight:Length(), DmgInfo)
		end

		-- Detonate any explosive reactive armor the round struck (guards on round type and kinetic energy internally)
		Ballistics.DoReactiveArmor(Bullet, Trace, DmgInfo)

		-- The round punched through the struck convex; mark it transparent so the flight loop's next
		-- re-trace advances to the convex behind it instead of resolving against this one again.
		if ConvexHit and HitRes.Overkill and HitRes.Overkill > 0 then
			Ballistics.FilterConvex(Bullet, Entity, ConvexHit.ConvexID)
		end

		if HitRes.Loss == 1 then
			-- If the there's more armor than penetration, the bullet ricochets
			Ricochet, HitRes.Loss = Ballistics.CalculateRicochet(Bullet, Trace, HitAngle)
		end

		-- Transfer bullet momentum into target
		if ACF.KEPush then
			ACF.KEShove(
				Entity,
				ImpactPos,
				-Bullet.Flight:GetNormalized(),
				Energy.Kinetic * HitRes.Loss * 1000 * Bullet.ShovePower
			)
		end

		-- If the entity should be killed, kill it
		if HitRes.Kill and IsValid(Entity) then
			ACF.APKill(Entity, Bullet.Flight:GetNormalized(), Energy.Kinetic, DmgInfo)
		end

		HitRes.Ricochet = false

		-- Apply the ricochet for the next bullet iteration if needed
		if Ricochet > 0 and Bullet.Ricochets < 3 then
			Bullet.Ricochets = Bullet.Ricochets + 1

			Ballistics.ApplyRicochet(Bullet, ImpactPos, HitNormal, Speed, Ricochet, 0.025, Bullet.DeltaTime)

			HitRes.Ricochet = true
		end

		return HitRes
	end

	function Ballistics.DoRicochet(Bullet, Trace)
		local HitAngle = ACF.GetHitAngle(Trace, Bullet.Flight)
		local Speed    = Bullet.Flight:Length() / ACF.Scale
		local MinAngle = math.min(Bullet.Ricochet - Speed / ACF.MeterToInch / 30 + 20, 89.9) -- Making the chance of a ricochet get higher as the speeds increase
		local Ricochet = 0

		if HitAngle < 89.9 and HitAngle > math.random(MinAngle, 90) then -- Checking for ricochet
			Ricochet = HitAngle / 90 * 0.75
		end

		if Ricochet > 0 and Bullet.GroundRicos < 2 then
			local DeltaTime = engine.TickInterval()

			Bullet.GroundRicos = Bullet.GroundRicos + 1

			Ballistics.ApplyRicochet(Bullet, Trace.HitPos, Trace.HitNormal, Speed, Ricochet, 0.05, DeltaTime)

			return "Ricochet"
		end

		return false
	end

	-- Spall tuning, kept as locals so this file hot-reloads on its own without a full restart.
	local SpallMassFraction = 0.25 -- Share of the rear crater's mass thrown as fragments, before the material's SpallMul
	local SpallCraterGrowth = 0.25 -- Rear crater radius growth per unit of plate thickness, past the bore radius
	local SpallScabSpeed    = 0.25 -- Floor on core speed as a fraction of impact speed, near the limit a scab still flies off
	local SpallEdgeSpeed    = 0.3  -- Speed of fragments at the cone's edge as a fraction of the core speed
	local SpallMinCone      = 20   -- Degrees, cone half angle at heavy overmatch (Loss near 0)
	local SpallMaxCone      = 60   -- Degrees, cone half angle near the ballistic limit (Loss near 1), Horsfall saw ~40
	local SpallAnglePower   = 2    -- Higher packs more fragments near the cone axis
	local SpallFragsPerMm   = 0.2  -- Traced fragments allowed per mm of bore, so small rounds stay cheap
	local SpallMaxFragCount = 20   -- Hard cap on traced fragments per spall event
	local SpallMinPen       = 0.5  -- mm, fragments that cannot beat this are not worth tracing
	local SpallMinToughness = 0.5  -- MPa*m^0.5, floor so liquids still break into finite droplets

	-- Behind-armor debris from a perforated convex. A fast, heavy core follows the penetrator while lighter, slower
	-- fragments fill the edge of the cone, so a liner narrows the cone but cannot stop its center.
	function Ballistics.DoSpall(Bullet, Trace, HitRes, Speed, DmgInfo)
		local ConvexHits = DmgInfo and DmgInfo:GetConvexHits()
		local LastHit    = ConvexHits and ConvexHits[#ConvexHits]
		local Hit        = LastHit and LastHit.Source -- The convex the round exited through
		if not Hit then return end -- Only meshed armor spalls

		local Type    = Hit.ArmorType
		local Area    = Bullet.DamageArea or Bullet.ProjArea -- cm^2
		local Bore    = (Area / math.pi) ^ 0.5 -- cm, radius
		local Caliber = Bore * 20 -- mm
		local Release = ACF.GetSpallRelease(Hit, Caliber)

		if Release <= 0 then return end -- Backed by a stiffer layer, the rear face is held in compression

		-- Mass comes from the rear crater, a cone widening from the bore through the last caliber or so of the plate.
		local Thick   = Hit.GeoThick * 0.1 -- cm
		local Radius  = Bore + SpallCraterGrowth * Thick
		local Depth   = math.min(Thick, Bore * 2)
		local Density = Type.Density * 1e-6 -- kg/cm^3
		local Mass    = SpallMassFraction * Type.SpallMul * Release * Density * math.pi * Radius ^ 2 * Depth -- kg

		if Mass <= 0 then return end

		-- Grady fragment size (Hazell Eq. 3.61): tough plates break into few heavy pieces, stiff or brittle ones into many fine ones.
		local ImpactSpeed = Speed / ACF.Scale * ACF.InchToMeter -- m/s
		local StrainRate  = math.max(ImpactSpeed, 1) / (Bore * 0.02) -- 1/s, impact speed over bore diameter
		local Toughness   = math.max(Type.Toughness, SpallMinToughness) * 1e6 -- Pa*m^0.5
		local FragSize    = (20 * Toughness / (Type.Density * Type.SoundSpeed * StrainRate)) ^ (2 / 3) * 100 -- cm
		local MeanMass    = Density * math.pi * FragSize ^ 3 / 6 -- kg

		local MaxFrags  = math.Clamp(math.floor(Caliber * SpallFragsPerMm), 1, SpallMaxFragCount)
		local FragCount = math.Clamp(math.ceil(Mass / MeanMass), 1, MaxFrags)

		-- The core follows the residual penetrator, floored by scab speed and capped at a third of the plate's sound speed (Hazell p. 92).
		local Loss      = HitRes.Loss
		local CoreSpeed = math.min(ImpactSpeed * math.max((1 - Loss) ^ 0.5, SpallScabSpeed), Type.SoundSpeed / 3)
		local Cone      = SpallMinCone + (SpallMaxCone - SpallMinCone) * Loss -- Near the limit the plate fails wide, heavy overmatch punches clean

		local FragPos     = Hit.ExitPos
		local FragDirInit = Bullet.Flight:GetNormalized()
		local DirAngle    = FragDirInit:Angle()
		local Right, Up   = DirAngle:Right(), DirAngle:Up()

		-- Fragments skip what the round already bored through, but can still hit the rest of the struck entity, such as a liner.
		local Entity       = Trace.Entity
		local Filter       = {}
		local ConvexFilter = table.Copy(Bullet.ConvexFilter or {})
		local Bored        = ConvexFilter[Entity] or {}

		for _, Ent in ipairs(Bullet.Filter) do
			if Ent ~= Entity then Filter[#Filter + 1] = Ent end
		end

		for _, BoredHit in ipairs(ConvexHits) do
			Bored[BoredHit.ConvexID] = true
		end

		ConvexFilter[Entity] = Bored

		-- Mott masses (m = mu * ln(1/u)^2), with the same draw setting the angle so heavy fragments fly near the axis.
		local Draws, Masses, MassSum = {}, {}, 0
		for I = 1, FragCount do
			local U    = 1 - math.random()
			local Frag = math.Clamp(MeanMass * 0.5 * math.log(1 / U) ^ 2, 1e-7, Mass)

			Draws[I], Masses[I] = U, Frag
			MassSum = MassSum + Frag
		end

		-- Each traced fragment stands in for Weight real ones, so the spalled mass is conserved without tracing every piece.
		local Weight = Mass / MassSum

		for I = 1, FragCount do
			local FragMass  = Masses[I]
			local FragSize  = (6 * FragMass / (Density * math.pi)) ^ (1 / 3) -- cm, sphere of the same mass
			local Angle     = Cone * Draws[I] ^ SpallAnglePower
			local Edge      = (Angle / Cone) ^ 2
			local FragSpeed = CoreSpeed * (1 - (1 - SpallEdgeSpeed) * Edge) -- m/s

			if ACF.Penetration(FragSpeed, FragMass, FragSize * 10) < SpallMinPen then continue end

			local ProjArea     = math.pi * (FragSize * 0.5) ^ 2
			local SpreadRadius = math.tan(math.rad(Angle))
			local SpreadAngle  = math.random() * 2 * math.pi
			local SpreadDir    = Up * SpreadRadius * math.cos(SpreadAngle) + Right * SpreadRadius * math.sin(SpreadAngle)
			local FragDir      = (FragDirInit + SpreadDir):GetNormalized()

			Ballistics.CreateFragment({
				Diameter     = FragSize,
				Owner        = Bullet.Owner,
				Entity       = Bullet.Entity,
				Gun          = Bullet.Gun,
				Pos          = FragPos,
				ProjArea     = ProjArea,
				ProjMass     = FragMass,
				DragCoef     = ProjArea * 0.0001 / FragMass, -- Same as the AP ammo definition
				Flight       = FragDir * (FragSpeed * ACF.MeterToInch * ACF.Scale),
				Filter       = Filter,
				ConvexFilter = ConvexFilter,
				Weight       = Weight,
			})
		end
	end

	-- Explosive Reactive Armor: when a round carrying enough kinetic energy passes through an explosive
	-- armor convex, that convex detonates. The spent convex is zeroed out (becoming transparent to ballistics)
	-- and its filler is set off as an HE blast at the impact point.
	function Ballistics.DoReactiveArmor(Bullet, Trace, DmgInfo)
		if Bullet.IsSpall or Bullet.IsCookOff then return end -- Neither carries a warhead that could set the plate off

		local Entity = Trace.Entity
		if not IsValid(Entity) then return end

		local MeshData = Entity.ACF_Volumetric_Mesh
		if not MeshData or not MeshData.HasReactiveArmor then return end -- Nothing reactive on this entity; bail before any work

		local ConvexHits = DmgInfo and DmgInfo.GetConvexHits and DmgInfo:GetConvexHits()
		if not ConvexHits then return end

		local KE = Bullet.Energy and Bullet.Energy.Kinetic or 0

		for _, Hit in ipairs(ConvexHits) do
			local Convex = MeshData.Convexes[Hit.ConvexID]
			if not Convex or not Convex.IsExplosive or Convex.Detonated then continue end

			local ArmorType = ArmorTypes.Get(Convex.Material)
			if not ArmorType then continue end
			if KE < (ArmorType.ExplosiveThreshold or math.huge) then continue end

			-- Spend the convex; zero health makes it transparent to subsequent projectiles
			Convex.Detonated = true
			Convex.Health    = 0
			Damage.NetworkConvex(Entity, Hit.ConvexID)

			local Filler = Convex.Mass * (ArmorType.ExplosiveFiller or 0)
			-- print("Filler", 	Filler)
			if Filler <= 0 then continue end

			local FragMass  = math.max(Convex.Mass - Filler)
			local Position  = (Bullet.ConvexHit and Bullet.ConvexHit.EntryPos) or Trace.HitPos
			local BlastInfo = Damage.Objects.DamageInfo(Bullet.Owner, Bullet.Gun)

			Damage.createExplosion(Position, Filler, FragMass, { Entity }, BlastInfo)
			Damage.explosionEffect(Position, nil, Filler)
		end
	end
end

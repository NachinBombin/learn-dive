-- ============================================================
-- CONTRAIL SYSTEM  --  ent_bombin_loiter_munition
-- 3 beam trails: center rear fuselage + both wingtip trailing edges.
-- Model uses Y axis for wingspan (offsets mirror TIER_OFFSETS).
-- Unique hook names to avoid collision with other entities.
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )
local SAMPLE_RATE    = 0.025   -- 40 fps sampling

-- Y = wingspan on this model (matches TIER_OFFSETS convention).
-- Center rear: negative X (rear of fuselage).
-- Wingtips: trailing edge of each wing at +/-90 Y.
local TRAIL_OFFSETS = {
    Vector( -60,   0, 0 ),   -- [1] center rear / exhaust
    Vector( -15,  90, 0 ),   -- [2] starboard (right) wingtip trailing edge
    Vector( -15, -90, 0 ),   -- [3] port (left) wingtip trailing edge
}

local CONTRAIL_CFG = {
    r         = 255,
    g         = 255,
    b         = 255,
    a         = 130,
    startSize = 5,
    endSize   = 28,
    lifetime  = 6,
}

local LoiterTrails = {}

local function EnsureRegistered( entIndex )
    if LoiterTrails[entIndex] then return end
    local trails = {}
    for i = 1, #TRAIL_OFFSETS do
        trails[i] = { nextSample = 0, positions = {} }
    end
    LoiterTrails[entIndex] = trails
end

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove( positions, i )
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial( TRAIL_MATERIAL )
    render.StartBeam( n )
    for _, pd in ipairs( positions ) do
        local Scale = math.Clamp( (pd.time + lt - Time) / lt, 0, 1 )
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam( pd.pos, size, pd.time * 50,
            Color( cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale ) )
    end
    render.EndBeam()
end

hook.Add( "Think", "bombin_loiter_contrail_update", function()
    local Time = CurTime()

    for _, ent in ipairs( ents.FindByClass( "ent_bombin_loiter_munition" ) ) do
        EnsureRegistered( ent:EntIndex() )
    end

    for entIndex, trails in pairs( LoiterTrails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then
            LoiterTrails[entIndex] = nil
            continue
        end

        local pos = ent:GetPos()
        local ang = ent:GetAngles()

        for i, state in ipairs( trails ) do
            if Time < state.nextSample then continue end
            state.nextSample = Time + SAMPLE_RATE

            local wpos = LocalToWorld( TRAIL_OFFSETS[i], Angle(0,0,0), pos, ang )
            table.insert( state.positions, { time = Time, pos = wpos } )
            table.sort( state.positions, function( a, b ) return a.time > b.time end )
        end
    end
end )

hook.Add( "PostDrawTranslucentRenderables", "bombin_loiter_contrail_draw", function( bDepth, bSkybox )
    if bSkybox then return end
    for _, trails in pairs( LoiterTrails ) do
        for _, state in ipairs( trails ) do
            DrawBeam( state.positions, CONTRAIL_CFG )
        end
    end
end )

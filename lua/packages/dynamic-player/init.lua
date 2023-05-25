require( "packages/player-extensions", "https://github.com/Pika-Software/player-extensions" )
require( "packages/glua-extensions", "https://github.com/Pika-Software/glua-extensions" )

-- Libraries
local promise = promise
local math = math
local util = util

-- Variables
local packageName = gpm.Package:GetIdentifier()
local table_insert = table.insert
local WorldToLocal = WorldToLocal
local string_lower = string.lower
local ents_Create = ents.Create
local IsValid = IsValid
local ipairs = ipairs
local Vector = Vector
local select = select

do

    local CurTime = CurTime
    local ENT = {}

    ENT.Type = "anim"
    ENT.AutomaticFrameAdvance = true

    function ENT:Initialize()
        self:AddEFlags( EFL_SERVER_ONLY )
        self:SetNoDraw( true )
    end

    function ENT:SetCrouching( bool )
        self.Crouching = bool
    end

    function ENT:Think()
        local seqID = self:LookupSequence( self.Crouching and "cidle_all" or "idle_all_01" )
        if seqID > 0 then
            self:SetSequence( seqID )
        end

        self:SetCycle( 1 )
        self:NextThink( CurTime() )
        return true
    end

    scripted_ents.Register( ENT, "dynamic-player-dummy" )

end

local function calcByEntity( ent )
    local playerPos, playerAng = ent:GetPos(), ent:GetAngles()
    local mins, maxs = Vector(), Vector()

    for hboxset = 0, ent:GetHitboxSetCount() - 1 do
        for hitbox = 0, ent:GetHitBoxCount( hboxset ) - 1 do
            local bone = ent:GetHitBoxBone( hitbox, hboxset )
            if bone < 0 then continue end

            local bonePos, boneAng = ent:GetLocalBonePosition( bone )
            local boneMins, boneMaxs = ent:GetHitBoxBounds( hitbox, hboxset )
            local localBonePos = WorldToLocal( bonePos, boneAng, playerPos, playerAng )

            boneMins = boneMins + localBonePos
            boneMaxs = boneMaxs + localBonePos

            for i = 1, 3 do
                if boneMins[i] < mins[i] then
                    mins[i] = boneMins[i]
                end
            end

            for i = 1, 3 do
                if boneMaxs[i] > maxs[i] then
                    maxs[i] = boneMaxs[i]
                end
            end
        end
    end

    maxs[1] = math.floor( ( ( maxs[1] - mins[1] ) + ( maxs[2] - mins[2] ) ) / 4 )
    maxs[3] = math.floor( maxs[3] )
    maxs[2] = maxs[1]

    local floorMins = math.floor( mins[3] )
    mins[3] = math.abs( floorMins ) >= maxs[3] and floorMins or 0
    mins[1] = -maxs[1]
    mins[2] = mins[1]

    return mins, maxs
end

local function fastCalcByModel( model )
    local mins, maxs = Vector(), Vector()

    local verticies = {}
    for _, tbl in ipairs( util.GetModelMeshes( model, 0, 0 ) ) do
        for __, point in ipairs( tbl.verticies ) do
            table_insert( verticies, point )
        end
    end

    for num, point in ipairs( verticies ) do
        local pos = point.pos
        for i = 1, 3 do
            if pos[i] < mins[i] then
                mins[i] = pos[i]
            end
        end

        for i = 1, 3 do
            if pos[i] > maxs[i] then
                maxs[i] = pos[i]
            end
        end
    end

    maxs[1] = math.floor( ( ( maxs[1] - mins[1] ) + ( maxs[2] - mins[2] ) ) / 4 )
    maxs[3] = math.floor( maxs[3] )
    maxs[2] = maxs[1]

    local floorMins = math.floor( mins[3] )
    mins[3] = math.abs( floorMins ) >= maxs[3] and floorMins or 0
    mins[1] = -maxs[1]
    mins[2] = mins[1]

    return mins, maxs
end

local function getEyePosition( ent )
    local bone = ent:FindBone( ".+Head.+" )
    if bone then
        local mins, maxs = ent:GetHitBoxBoundsByBone( bone )
        if mins and maxs then
            return ent:GetLocalBonePosition( bone ) + ( maxs - mins ) / 2
        end
    end

    local eyes = ent:GetAttachmentByName( "eyes" )
    if eyes then return eyes.Pos end

    return ent:EyePos()
end

local PLAYER = FindMetaTable( "Player" )
local modelCache = {}

PLAYER.SetupModelBounds = promise.Async( function( self )
    local model = string_lower( self:GetModel() )

    local mins, maxs, duckHeight, eyeHeightDuck, eyeHeight
    local cache = modelCache[ model ]
    if cache then
        mins, maxs, duckHeight, eyeHeightDuck, eyeHeight = cache[1][1], cache[1][2], cache[2], cache[3][1], cache[3][2]
    end

    if self:GetBoneCount() > 1 then
        if not cache then
            local dummy = ents_Create( "dynamic-player-dummy" )
            dummy:SetModel( Model( model ) )
            dummy:Spawn()

            promise.Sleep( 0.25 )
            if not IsValid( dummy ) then return end

            -- Hull calc
            mins, maxs = calcByEntity( dummy )

            -- Eyes height calc
            eyeHeight = math.Round( dummy:WorldToLocal( getEyePosition( dummy ) )[3] )

            -- Ducking dummy
            dummy:SetCrouching( true )

            promise.Sleep( 0.25 )
            if not IsValid( dummy ) then return end

            -- Duck height calc
            duckHeight = select( -1, calcByEntity( dummy ) )[3]

            -- Shitty models fix
            if duckHeight < 5 then
                duckHeight = maxs[3] / 2
            end

            -- Duck eyes height calc
            eyeHeightDuck = math.Round( dummy:WorldToLocal( getEyePosition( dummy ) )[3] )

            -- Dummy remove
            dummy:Remove()

            -- Eye position correction
            eyeHeight = math.floor( math.max( eyeHeight - 5, 5 ) )
            eyeHeightDuck = math.floor( math.max( 5, eyeHeightDuck, ( maxs[3] - mins[3] ) * 0.6 ) )

            -- Height correction
            duckHeight = math.floor( math.max( 5, duckHeight, eyeHeightDuck + 5 ) )
            maxs[3] = math.floor( math.max( maxs[3], eyeHeight + 5 ) )

            -- Saving results in cache
            modelCache[ model ] = { { mins, maxs }, duckHeight, { eyeHeightDuck, eyeHeight } }
        end

        -- Selecting eyes level
        self:SetViewOffset( Vector( 0, 0, eyeHeight ) )
        self:SetViewOffsetDucked( Vector( 0, 0, math.min( eyeHeight * 0.6, eyeHeightDuck ) ) )
    else
        if not cache then
            -- Hulls calc
            mins, maxs = fastCalcByModel( model )
            duckHeight = maxs[3] * 0.7

            -- Eyes calc
            eyeHeight = math.Round( ( maxs[3] - mins[3] ) * 0.9 )
            eyeHeightDuck = math.Round( eyeHeight * 0.7 )

            -- Saving results in cache
            modelCache[ model ] = { { mins, maxs }, duckHeight, { eyeHeight, eyeHeightDuck } }
        end

        -- Selecting eyes level
        self:SetViewOffsetDucked( Vector( 0, 0, eyeHeightDuck ) )
        self:SetViewOffset( Vector( 0, 0, eyeHeight ) )
    end

    -- Setuping hulls
    self:SetHullDuck( mins, Vector( maxs[1], maxs[2], duckHeight ) )
    self:SetHull( mins, maxs )

    -- Setuping step size
    self:SetStepSize( math.min( math.floor( ( maxs[3] - mins[3] ) / 3.6 ), 4095 ) )

    -- Dev hook
    hook.Run( "UpdatedPlayerDynamic", self )

    -- Position fix
    if mins[3] >= 0 or self:InVehicle() then return end
    self:SetPos( self:GetPos() + Vector( 0, 0, math.abs( mins[3] ) ) )
end )

hook.Add( "OnPlayerModelChange", packageName, function( ply )
    util.NextTick( function()
        if IsValid( ply ) then
            ply:SetupModelBounds()
        end
    end )
end )
install( "packages/player-extensions", "https://github.com/Pika-Software/player-extensions" )
install( "packages/glua-extensions", "https://github.com/Pika-Software/glua-extensions" )

-- Libraries
local promise = promise
local math = math
local util = util

-- Variables
local table_insert = table.insert
local WorldToLocal = WorldToLocal
local string_lower = string.lower
local ents_Create = ents.Create
local vector_zero = vector_zero
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

local function calcByEntity( entity )
    local playerPos, playerAng = entity:GetPos(), entity:GetAngles()
    local mins, maxs = Vector(), Vector()
    local pelvisFix = false

    for hboxset = 0, entity:GetHitboxSetCount() - 1 do
        for hitbox = 0, entity:GetHitBoxCount( hboxset ) - 1 do
            local bone = entity:GetHitBoxBone( hitbox, hboxset )
            if bone < 0 then continue end

            local boneMins, boneMaxs = entity:GetHitBoxBounds( hitbox, hboxset )
            local bonePos, boneAng = entity:GetLocalBonePosition( bone )

            local localBonePos = WorldToLocal( bonePos, boneAng, playerPos, playerAng )
            boneMins, boneMaxs = boneMins + localBonePos, boneMaxs + localBonePos

            if not pelvisFix and localBonePos[ 3 ] < 0 then
                pelvisFix = true
            end

            for axis = 1, 3 do
                if boneMins[ axis ] < mins[ axis ] then
                    mins[ axis ] = boneMins[ axis ]
                end

                if boneMaxs[ axis ] > maxs[ axis ] then
                    maxs[ axis ] = boneMaxs[ axis ]
                end
            end
        end
    end

    if pelvisFix then
        maxs[ 3 ] = maxs[ 3 ] - mins[ 3 ]
        mins[ 3 ] = 0
    end

    maxs[ 1 ] = math.floor( ( ( maxs[ 1 ] - mins[ 1 ] ) + ( maxs[ 2 ] - mins[ 2 ] ) ) / 4 )
    maxs[ 3 ] = math.floor( maxs[ 3 ] )
    maxs[ 2 ] = maxs[ 1 ]

    local floorMins = math.floor( mins[ 3 ] )
    mins[ 3 ] = math.abs( floorMins ) >= maxs[ 3 ] and floorMins or 0
    mins[ 1 ] = -maxs[ 1 ]
    mins[ 2 ] = mins[ 1 ]

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

        for axis = 1, 3 do
            if pos[ axis ] >= mins[ axis ] then continue end
            mins[ axis ] = pos[ axis ]
        end

        for axis = 1, 3 do
            if pos[ axis ] <= maxs[ axis ] then continue end
            maxs[ axis ] = pos[ axis ]
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

local function getEyePosition( entity )
    local bone = entity:FindBone( "Head" )
    if not bone then
        local highestBone
        for i = 0, entity:GetBoneCount() do
            local pos = entity:GetBonePosition( i )
            if not pos then continue end
            if not highestBone or highestBone[ 2 ] < pos[ 3 ]  then
                highestBone = { i, pos[ 3 ] }
            end
        end

        if highestBone then
            bone = highestBone[ 1 ]
        end
    end

    if bone then
        local mins, maxs = entity:GetHitBoxBoundsByBone( bone )
        if mins and maxs then
            local pos = entity:GetLocalBonePosition( bone )

            local pelvisPos = entity:GetLocalBonePosition( 0 )
            if pelvisPos and pelvisPos[ 3 ] < 0 then
                return pos + ( maxs - mins * 2 )
            end

            return pos + ( maxs - mins ) / 2
        end

        return entity:GetLocalBonePosition( bone )
    end

    local eyes = entity:GetAttachmentByName( "eyes" )
    if eyes then
        return entity:WorldToLocal( eyes.Pos )
    end

    return vector_zero
end

local PLAYER = FindMetaTable( "Player" )
local modelCache = {}

PLAYER.SetupModelBounds = promise.Async( function( self )
    local model = string_lower( self:GetModel() )
    if hook.Run( "OnPlayerUpdateModelBounds", self, model ) then return end

    local mins, maxs, duckHeight, eyeHeightDuck, eyeHeight
    local cache = modelCache[ model ]
    if cache then
        mins, maxs, duckHeight, eyeHeightDuck, eyeHeight = cache[ 1 ][ 1 ], cache[ 1 ][ 2 ], cache[ 2 ], cache[ 3 ][ 1 ], cache[ 3 ][ 2 ]
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
            eyeHeight = math.Round( dummy:WorldToLocal( getEyePosition( dummy ) )[ 3 ] )

            -- Ducking dummy
            dummy:SetCrouching( true )

            promise.Sleep( 0.25 )
            if not IsValid( dummy ) then return end

            -- Duck height calc
            duckHeight = select( -1, calcByEntity( dummy ) )[ 3 ]

            -- Shitty models fix
            if duckHeight < 5 then
                duckHeight = maxs[ 3 ] / 2
            end

            -- Duck eyes height calc
            eyeHeightDuck = math.Round( dummy:WorldToLocal( getEyePosition( dummy ) )[ 3 ] )

            -- Dummy remove
            dummy:Remove()

            -- Eye position correction
            eyeHeight = math.floor( math.max( eyeHeight - 5, 5 ) )
            eyeHeightDuck = math.floor( math.max( 5, eyeHeightDuck, ( maxs[ 3 ] - mins[ 3 ] ) * 0.6 ) )

            -- Height correction
            duckHeight = math.floor( math.max( 5, duckHeight, eyeHeightDuck + 5 ) )
            maxs[ 3 ] = math.floor( math.max( maxs[ 3 ], eyeHeight + 5 ) )

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
            duckHeight = maxs[ 3 ] * 0.7

            -- Eyes calc
            eyeHeight = math.Round( ( maxs[ 3 ] - mins[ 3 ] ) * 0.9 )
            eyeHeightDuck = math.Round( eyeHeight * 0.7 )

            -- Saving results in cache
            modelCache[ model ] = { { mins, maxs }, duckHeight, { eyeHeight, eyeHeightDuck } }
        end

        -- Selecting eyes level
        self:SetViewOffsetDucked( Vector( 0, 0, eyeHeightDuck ) )
        self:SetViewOffset( Vector( 0, 0, eyeHeight ) )
    end

    -- Setuping hulls
    self:SetHullDuck( mins, Vector( maxs[ 1 ], maxs[ 2 ], duckHeight ) )
    self:SetHull( mins, maxs )

    -- Setuping step size
    self:SetStepSize( math.min( math.floor( ( maxs[ 3 ] - mins[ 3 ] ) / 3.6 ), 4095 ) )

    hook.Run( "PlayerUpdatedModelBounds", self, model )

    -- Position fix
    if mins[ 3 ] >= 0 or self:InVehicle() then return end
    self:SetPos( self:GetPos() + Vector( 0, 0, math.abs( mins[ 3 ] ) ) )
end )

hook.Add( "PlayerInitialized", "PlayerInitialized", PLAYER.SetupModelBounds )
hook.Add( "PlayerModelChanged", "ModelChanged", PLAYER.SetupModelBounds )
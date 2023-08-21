install( "packages/player-extensions", "https://github.com/Pika-Software/player-extensions" )
install( "packages/glua-extensions", "https://github.com/Pika-Software/glua-extensions" )
install( "packages/config.lua", "https://raw.githubusercontent.com/Pika-Software/config/main/lua/packages/config.lua")

-- Libraries
local promise = promise
local math = math
local util = util

-- Variables
local table_insert = table.insert
local string_lower = string.lower
local ents_Create = ents.Create
local IsValid = IsValid
local ipairs = ipairs
local Vector = Vector

local function calcByEntity( entity )
    local eyes, mins, maxs = Vector(), Vector(), Vector()

    local bounds = {}
    for hboxset = 0, entity:GetHitboxSetCount() - 1 do
        for hitbox = 0, entity:GetHitBoxCount( hboxset ) - 1 do
            bounds[ entity:GetHitBoxBone( hitbox, hboxset ) ] = { entity:GetHitBoxBounds( hitbox, hboxset ) }
        end
    end

    for bone = 0, entity:GetBoneCount() do
        local bonePos = entity:GetLocalBonePosition( bone )
        if not bonePos then continue end

        local boneName = entity:GetBoneName( bone )
        local data = bounds[ bone ]
        if not data then
            if boneName and string.find( boneName, "Head" ) and bonePos[ 3 ] > eyes[ 3 ] then
                eyes[ 3 ] = bonePos[ 3 ]
            end

            continue
        end

        local boneMins, boneMaxs = bonePos + data[ 1 ], bonePos + data[ 2 ]
        if boneName and string.find( boneName, "Head" ) or string.find( boneName, "Eyes" ) then
            local eyePos = ( boneMaxs + boneMins ) / 2
            if eyePos[ 3 ] > eyes[ 3 ] then
                eyes[ 3 ] = eyePos[ 3 ]
            end
        end

        for axis = 1, 3 do
            if bonePos[ axis ] < mins[ axis ] then
                mins[ axis ] = bonePos[ axis ]
            end

            if bonePos[ axis ] > maxs[ axis ] then
                maxs[ axis ] = bonePos[ axis ]
            end

            if boneMins[ axis ] < mins[ axis ] then
                mins[ axis ] = boneMins[ axis ]
            end

            if boneMaxs[ axis ] > maxs[ axis ] then
                maxs[ axis ] = boneMaxs[ axis ]
            end
        end
    end

    maxs[ 1 ] = math.Round( ( ( maxs[ 1 ] - mins[ 1 ] ) + ( maxs[ 2 ] - mins[ 2 ] ) ) / 4 )
    maxs[ 2 ] = maxs[ 1 ]

    mins[ 1 ] = -maxs[ 1 ]
    mins[ 2 ] = mins[ 1 ]

    maxs[ 3 ] = math.Round( maxs[ 3 ] + math.abs( mins[ 3 ] ) )
    mins[ 3 ] = 0

    if eyes[ 3 ] < 1 then
        eyes[ 3 ] = ( maxs[ 3 ] - mins[ 3 ] ) * 0.9
    end

    eyes[ 3 ] = math.Round( eyes[ 3 ] )

    return {
        ["Eyes"] = eyes,
        ["Mins"] = mins,
        ["Maxs"] = maxs
    }
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

local sourceVents = CreateConVar( "dp_source_vents_support", "0", FCVAR_ARCHIVE, "Enables source vents support by limiting max player crouch height.", 0, 1 )
local configFile = config.Create( "dynamic-player" )
local PLAYER = FindMetaTable( "Player" )

PLAYER.SetupModelBounds = promise.Async( function( self )
    local model = string_lower( self:GetModel() )
    if hook.Run( "OnPlayerUpdateModelBounds", self, model ) then return end

    local modelData = configFile:Get( model )
    if not modelData then
        modelData = {}

        if self:GetBoneCount() > 1 then
            local dummy = ents_Create( "dp_dummy" )
            dummy:SetModel( Model( model ) )
            dummy:Spawn()

            promise.Sleep( 0.25 )

            if not IsValid( dummy ) then return end
            local standing = calcByEntity( dummy )

            dummy.Crouching = true
            promise.Sleep( 0.25 )

            if not IsValid( dummy ) then return end
            local crouching = calcByEntity( dummy )

            if IsValid( dummy ) then
                dummy:Remove()
            end

            local smaxs, cmaxs = standing.Maxs, crouching.Maxs
            if smaxs[ 1 ] < cmaxs[ 1 ] then
                cmaxs[ 1 ] = smaxs[ 1 ]
                cmaxs[ 2 ] = smaxs[ 2 ]
            else
                smaxs[ 1 ] = cmaxs[ 1 ]
                smaxs[ 2 ] = cmaxs[ 2 ]
            end

            local smins, cmins = standing.Mins, crouching.Mins
            if smins[ 1 ] > cmins[ 1 ] then
                cmins[ 1 ] = smins[ 1 ]
                cmins[ 2 ] = smins[ 2 ]
            else
                smins[ 1 ] = cmins[ 1 ]
                smins[ 2 ] = cmins[ 2 ]
            end

            local zOffset = ( standing.Mins[ 3 ] + crouching.Mins[ 3 ] ) / 2
            standing.Mins[ 3 ] = zOffset
            crouching.Mins[ 3 ] = zOffset

            for axis = 1, 2 do
                local offset = ( standing.Eyes[ axis ] + crouching.Eyes[ axis ] ) / 2
                standing.Eyes[ axis ] = offset
                crouching.Eyes[ axis ] = offset
            end

            modelData.Standing = standing
            modelData.Crouching = crouching
        else
            local mins, maxs = fastCalcByModel( model )
            local eyeHeight = math.Round( ( maxs[ 3 ] - mins[ 3 ] ) * 0.9 )
            modelData.Standing = {
                ["Eyes"] = Vector( 0, 0, eyeHeight ),
                ["Mins"] = mins:Copy(),
                ["Maxs"] = maxs:Copy()
            }

            maxs[ 3 ] = maxs[ 3 ] * 0.7

            modelData.Crouching = {
                ["Eyes"] = Vector( 0, 0, math.Round( eyeHeight * 0.7 ) ),
                ["Mins"] = mins,
                ["Maxs"] = maxs
            }
        end

        -- Height correction
        local standing, crouching = modelData.Standing, modelData.Crouching
        standing.Maxs[ 3 ] = math.max( 10, standing.Maxs[ 3 ], standing.Eyes[ 3 ] + 5 )
        crouching.Maxs[ 3 ] = math.max( 5, crouching.Maxs[ 3 ], crouching.Eyes[ 3 ] + 5 )

        -- Eyes correction
        local sEyes, cEyes = standing.Eyes[ 3 ], crouching.Eyes[ 3 ]
        standing.Eyes[ 3 ] = math.max( 15, sEyes, cEyes )
        crouching.Eyes[ 3 ] = math.max( 10, math.min( sEyes, cEyes ) )

        -- Fucked models fix
        local min, max = math.min( standing.Maxs[ 3 ], crouching.Maxs[ 3 ] ), math.max( standing.Maxs[ 3 ], crouching.Maxs[ 3 ] )
        crouching.Maxs[ 3 ], standing.Maxs[ 3 ] = min, max

        modelData.StepSize = math.min( math.floor( ( standing.Maxs[ 3 ] - standing.Mins[ 3 ] ) / 3.6 ), 4095 )
        configFile:Set( model, modelData )
    end

    local standing, crouching = modelData.Standing, modelData.Crouching

    -- Selecting eyes level
    self:SetViewOffsetDucked( crouching.Eyes )
    self:SetViewOffset( standing.Eyes )

    -- Shitty hack for source vents support
    if sourceVents:GetBool() then
        crouching.Maxs[ 3 ] = math.min( 48, crouching.Maxs[ 3 ] )
    end

    self:SetHullDuck( crouching.Mins, crouching.Maxs )
    self:SetHull( standing.Mins, standing.Maxs )
    self:SetStepSize( modelData.StepSize )

    hook.Run( "PlayerUpdatedModelBounds", self, model, modelData )

    -- Position fix
    if standing.Mins[ 3 ] >= 0 or self:InVehicle() then return end
    self:SetPos( self:GetPos() + Vector( 0, 0, math.abs( standing.Mins[ 3 ] ) ) )
end )

hook.Add( "PlayerInitialized", "PlayerInitialized", PLAYER.SetupModelBounds )
hook.Add( "PlayerModelChanged", "ModelChanged", PLAYER.SetupModelBounds )
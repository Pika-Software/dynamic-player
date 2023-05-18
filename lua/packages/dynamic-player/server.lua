import( gpm.PackageExists( "packages/glua-extensions" ) and "packages/glua-extensions" or "https://github.com/Pika-Software/glua-extensions" )

local promise = promise
local math = math
local util = util

local packageName = gpm.Package:GetIdentifier()
local timer_Simple = timer.Simple
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

local function createDummy( model, isCrouching )
    local ent = ents_Create( "dynamic-player-dummy" )
    ent:SetCrouching( isCrouching )
    ent:SetModel( Model( model ) )
    ent:Spawn()
    return ent
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

    maxs[1] = math.floor( ( ( maxs[1] - mins[1] ) + ( maxs[2] - mins[2] ) ) / 6 )
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

local function calcByModel( model )
    local mins, maxs = Vector(), Vector()

    local meshInfo, bodyParts = util.GetModelMeshes( model, 0, 0 )
    local modelInfo = util.GetModelInfo( model )

    local verticies = {}
    for _, tbl in ipairs( meshInfo ) do
        for __, point in ipairs( tbl.verticies ) do
            table_insert( verticies, point )
        end
    end

    local bones = {}
    for _, data in ipairs( util.KeyValuesToTablePreserveOrder( modelInfo.KeyValues ) ) do

        if data.Key == "animatedfriction" then
            PrintTable( data.Value )
            return
        end

        if data.Key ~= "solid" then continue end

        local boneData = {}
        for num, bone in ipairs( data.Value ) do
            boneData[ bone.Key ] = bone.Value
        end

        local matrix = nil
        for i = 0, #bodyParts do
            local part = bodyParts[ i ]
            if part.parent == boneData.index then
                matrix = part.matrix
                break
            end
        end

        table_insert( bones, {
            ["index"] = boneData.index,
            ["name"] = boneData.name,
            ["matrix"] = matrix
        } )
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

    if #bones > 1 then
        maxs[1] = math.floor( ( ( maxs[1] - mins[1] ) + ( maxs[2] - mins[2] ) ) / 6 )
        maxs[3] = math.floor( maxs[3] * 0.98 )
    else
        maxs[1] = math.floor( ( ( maxs[1] - mins[1] ) + ( maxs[2] - mins[2] ) ) / 4 )
        maxs[3] = math.floor( maxs[3] )
    end

    local floorMins = math.floor( mins[3] )
    mins[3] = math.abs( floorMins ) >= maxs[3] and floorMins or 0
    mins[1] = -maxs[1]
    mins[2] = mins[1]
    maxs[2] = maxs[1]

    return mins, maxs
end

local function calcStepSize( mins, maxs )
    return math.min( math.floor( ( maxs[3] - mins[3] ) / 3.6 ), 4095 )
end

local function fixPlayerPosition( ply, mins, maxs )
    if mins[3] >= 0 or ply:InVehicle() then return end
    ply:SetPos( ply:GetPos() + Vector( 0, 0, math.abs( mins[3] ) ) )
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

local modelCache = {}

local setupPlayer = promise.Async( function( ply, model )
    if ply:GetModel() ~= string_lower( model ) then return end

    local mins, maxs, duckHeight, eyeHeight, eyeHeightDuck

    -- Loading from cache
    local cache = modelCache[ model ]
    if cache then
        mins, maxs, duckHeight, eyeHeight, eyeHeightDuck = cache[1][1], cache[1][2], cache[2], cache[3][1], cache[3][2]
    end

    if ply:GetBoneCount() > 1 then
        if not cache then
            -- Hull Dummy
            local dummy = createDummy( model, false )
            promise.Delay( 0.025 ):Await()

            -- Hull Calc
            mins, maxs = calcByEntity( dummy )

            -- Eyes Height Calc
            eyeHeight = math.Round( dummy:WorldToLocal( getEyePosition( dummy ) )[3] )

            -- Duck Hull Dummy
            local crouchingDummy = createDummy( model, true )
            promise.Delay( 0.025 ):Await()

            -- Duck Height Calc
            duckHeight = select( -1, calcByEntity( crouchingDummy ) )[3]
            if duckHeight < 5 then
                duckHeight = maxs[3] / 2
            end

            -- Duck Eyes Height Calc
            eyeHeightDuck = math.Round( crouchingDummy:WorldToLocal( getEyePosition( dummy ) )[3] )
            promise.Delay( 0.025 ):Await()

            crouchingDummy:Remove()
            dummy:Remove()

            -- Eye position correction
            eyeHeight = math.floor( math.max( eyeHeight - 5, 5 ) )
            eyeHeightDuck = math.floor( math.max( 5, eyeHeightDuck, (maxs[3] - mins[3]) * 0.6 ) )

            -- Height correction
            duckHeight = math.floor( math.max( duckHeight, eyeHeightDuck + 5 ) )
            maxs[3] = math.floor( math.max( maxs[3], eyeHeight + 5 ) )

            -- Saving results in cache
            modelCache[ model ] = { { mins, maxs }, duckHeight, { eyeHeight, eyeHeightDuck } }
        end

        -- Selecting Eyes Level
        ply:SetViewOffset( Vector( 0, 0, eyeHeight ) )
        ply:SetViewOffsetDucked( Vector( 0, 0, math.min( eyeHeight * 0.6, eyeHeightDuck ) ) )
    else
        if not cache then
            -- Hulls Calc
            mins, maxs = fastCalcByModel( model )
            duckHeight = maxs[3] * 0.7

            -- Eyes Calc
            eyeHeight = math.Round( ( maxs[3] - mins[3] ) * 0.9 )
            eyeHeightDuck = math.Round( eyeHeight * 0.7 )

            -- Saving results in cache
            modelCache[ model ] = { { mins, maxs }, duckHeight, { eyeHeight, eyeHeightDuck } }
        end

        -- Selecting Eyes Level
        ply:SetViewOffsetDucked( Vector( 0, 0, eyeHeightDuck ) )
        ply:SetViewOffset( Vector( 0, 0, eyeHeight ) )
    end

    -- Setuping Hulls
    ply:SetHullDuck( mins, Vector( maxs[1], maxs[2], duckHeight ) )
    ply:SetHull( mins, maxs )

    -- Setuping Step Size & Pos Fix
    ply:SetStepSize( calcStepSize( mins, maxs ) )
    fixPlayerPosition( ply, mins, maxs )
end )

hook.Add( "PlayerModelChanged", packageName, function( ply, model )
    timer_Simple( 0, function()
        if not IsValid( ply ) then return end
        setupPlayer( ply, model )
    end )
end )
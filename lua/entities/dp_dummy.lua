AddCSLuaFile()

local EFL_SERVER_ONLY = EFL_SERVER_ONLY
local ACT_HL2MP_IDLE = ACT_HL2MP_IDLE
local CurTime = CurTime

ENT.Type = "anim"
ENT.AutomaticFrameAdvance = true

local ENTITY = FindMetaTable( "Entity" )

function ENT:Initialize()
    ENTITY.AddEFlags( self, EFL_SERVER_ONLY )
end

if SERVER then

    function ENT:Think()
        local act = ACT_HL2MP_IDLE
        if self.Crouching then
            act = act + 3
        end

        ENTITY.SetSequence( self, ENTITY.SelectWeightedSequence( self, act ) )
        ENTITY.NextThink( self, CurTime() )
        ENTITY.SetCycle( self, 1 )
        return true
    end

end

if CLIENT then
    local debug_fempty = debug.fempty
    ENT.DrawTranslucent = debug_fempty
    ENT.Think = debug_fempty
    ENT.Draw = debug_fempty
end
AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )

include( "shared.lua" )

duplicator.RegisterEntityClass( "base_glide_aircraft", Glide.VehicleFactory, "Data" )

DEFINE_BASECLASS( "base_glide" )

--- Implement the base class `OnPostInitialize` function.
function ENT:OnPostInitialize()
    -- Setup variables used on all aircraft
    self.altitude = 0
    self.powerResponse = 0.2

    self.inputPitch = 0
    self.inputRoll = 0
    self.inputYaw = 0

    -- Setup damage variables
    self.engineDamageCD = -1
    self.engineDamageSoundCD = -1

    -- Landing gear system
    self.landingGearState = 0
    self.landingGearExtend = 1
end

local TriggerOutput = Either( WireLib, WireLib.TriggerOutput, nil )

--- Override the base class `SetupWirePorts` function.
function ENT:SetupWirePorts()
    if not TriggerOutput then return end

    WireLib.CreateSpecialOutputs( self,
        { "MaxChassisHealth", "ChassisHealth", "EngineHealth", "Power", "Altitude", "WeaponCount" },
        { "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" }
    )

    WireLib.CreateSpecialInputs( self,
        { "Ignition", "Pitch", "Yaw", "Roll", "Throttle", "Fire", "WeaponIndex" },
        { "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" },
        {
            "1: Turn the engine on\n0: Turn the engine off",
            "A value between -1.0 and 1.0",
            "A value between -1.0 and 1.0",
            "A value between -1.0 and 1.0",
            "A value between 0.0 and 1.0",
            "When greater than 0, fires the current weapon,\nif this helicopter has one",
            "If this vehicle has weapons, this will set which one to use.\nStarts at index 1. Check the 'WeaponCount' output to see the max. value."
        }
    )

    TriggerOutput( self, "Power", 0 )
    TriggerOutput( self, "Altitude", 0 )
    TriggerOutput( self, "WeaponCount", self.weaponCount )
end

function ENT:SetLandingGearState( state )
    self.landingGearState = state

    -- Remember the original suspension spring length
    if not self.landingGearLength then
        self.landingGearLength = self.wheelParams.suspensionLength
    end

    local anim = self.LandingGearAnims[state]

    if anim then
        self:ResetSequence( anim )
    end

    if state == 1 then
        -- Move the gear up
        self.landingGearExtend = 1
        self.wheelsEnabled = true
        self:EmitSound( "glide/aircraft/gear_down.wav", 90, 100, 0.5 )

    elseif state == 2 then
        -- Set the gear up now
        self.landingGearExtend = 0
        self.wheelsEnabled = false
        self.wheelParams.suspensionLength = 0

    elseif state == 3 then
        -- Move the gear down
        self.landingGearExtend = 0
        self.wheelsEnabled = true
        self:EmitSound( "glide/aircraft/gear_down.wav", 90, 90, 0.5 )

    else
        -- Set the gear down now
        self.landingGearExtend = 1
        self.wheelsEnabled = true
        self.wheelParams.suspensionLength = self.landingGearLength
    end
end

function ENT:LandingGearThink( dt )
    local state = self.landingGearState

    if state == 1 then -- Is it moving up?
        self.landingGearExtend = self.landingGearExtend - dt
        self.wheelParams.suspensionLength = self.landingGearLength * self.landingGearExtend

        if self.landingGearExtend < 0 then
            self:SetLandingGearState( 2 ) -- Set fully up
        end

    elseif state == 3 then -- Is it moving down?
        self.landingGearExtend = self.landingGearExtend + dt
        self.wheelParams.suspensionLength = self.landingGearLength * self.landingGearExtend

        if self.landingGearExtend > 1 then
            self:SetLandingGearState( 0 ) -- Set fully down
        end
    end
end

--- Implement the base class `OnSeatInput` function.
function ENT:OnSeatInput( seatIndex, action, pressed )
    -- Toggle landing gear
    if pressed and self.HasLandingGear and action == "landing_gear" and seatIndex < 2 then
        local state = self.landingGearState

        if state == 0 then -- Is it down?
            self:SetLandingGearState( 1 ) -- Move up

        elseif state == 2 then -- Is it up?
            self:SetLandingGearState( 3 ) -- Move down
        end

        return true
    end
end

--- Implement the base class `OnPostThink` function.
function ENT:OnPostThink( dt )
    -- Find the altitude
    self:UpdateAltitude()

    -- Update landing gear
    if self.HasLandingGear then
        self:LandingGearThink( dt )
    end
end

do
    local RandomInt = math.random
    local PlaySoundSet = Glide.PlaySoundSet

    --- Process damage-over-time effects.
    function ENT:DamageThink( dt )
        local health = self:GetEngineHealth()
        if health > 0.5 then return end

        local power = self:GetPower()

        -- Emit random gear grinding noises at low health
        if health < 0.3 and power > 0.2 then
            self.engineDamageSoundCD = self.engineDamageSoundCD - dt

            if self.engineDamageSoundCD < 0 then
                self.engineDamageSoundCD = RandomInt( 1, 5 )
                PlaySoundSet( "Glide.Damaged.GearGrind", self, 0.3 - health )
            end
        end

        -- Periodically lower the engine health once below a threshold
        self.engineDamageCD = self.engineDamageCD - dt
        if self.engineDamageCD > 0 then return end

        self.engineDamageCD = RandomInt( 20, 25 )
        self:TakeEngineDamage( 0.04 )

        health = self:GetEngineHealth()

        if health > 0 then
            self:SetPower( power * ( health < 0.05 and 0.2 or ( health > 0.15 and 0.45 or 0.3 ) ) )
            PlaySoundSet( "Glide.Damaged.AircraftEngine", self, 1 - health )
        end
    end
end

--[[
    This file contains functions to simulate planes and helicopters.

    Instead of being on separate children classes, they are here
    to allow hybrid vehicles, such as VTOL aircraft.

    ATTENTION: These use some variables/functions that are not
    available on this base class. Check their descriptions for a list.
]]

local WORLD_UP = Vector( 0, 0, 1 )
local TraceLine = util.TraceLine

function ENT:UpdateAltitude()
    local mins = self:OBBMins()
    mins[1] = 0
    mins[2] = 0

    local traceStart = self:GetPos() + mins * 0.9
    local tr = TraceLine( self:GetTraceData( traceStart, traceStart - WORLD_UP * 10000 ) )

    self.altitude = tr.Hit and tr.Fraction * 10000 or 10000

    if TriggerOutput then
        TriggerOutput( self, "Altitude", self.altitude )
    end
end

local Cos = math.cos
local Abs = math.abs
local Clamp = math.Clamp

local CurTime = CurTime
local GetGravity = physenv.GetGravity

local mass, up, fw, rt
local vel, localVel, effectiveness

local function AddForce( out, f )
    out[1] = out[1] + f[1] * mass * effectiveness
    out[2] = out[2] + f[2] * mass * effectiveness
    out[3] = out[3] + f[3] * mass * effectiveness
end

local function LimitInputWithAngle( value, ang, maxAng )
    if ang > maxAng then
        value = value * ( 1 - Clamp( ( ang - maxAng ) / 20, 0, 1 ) )
    end

    return value
end

--- Simulate helicopter physics.
--- Uses these extra ENT functions and variables:
---
--- > boolean = self:GetOutOfControl()
---
function ENT:SimulateHelicopter( phys, params, effective, outLin, outAng )
    effectiveness = effective
    mass = phys:GetMass()

    up = self:GetUp()
    fw = self:GetForward()
    rt = self:GetRight()

    vel = phys:GetVelocity()
    localVel = self:WorldToLocal( phys:GetPos() + vel )

    -- Drag
    AddForce( outLin,
        ( -fw * Clamp( localVel[1], -params.maxFowardDrag, params.maxFowardDrag ) * params.drag[1] ) +
        ( rt * Clamp( localVel[2], -params.maxSideDrag, params.maxSideDrag ) * params.drag[2] ) +
        ( -up * localVel[3] * params.drag[3] )
    )

    -- Lift & keep upright forces
    local align = up:Dot( WORLD_UP )
    local gravity = -GetGravity()[3]
    local inputMult = self:IsEngineOn() and 1 or 0

    AddForce( outLin, gravity * up )
    AddForce( outLin, gravity * ( 0.75 - Clamp( Abs( align ), 0, 0.75 ) ) * WORLD_UP )
    AddForce( outLin, params.pushUpForce * self:GetInputFloat( 1, "throttle" ) * inputMult * up )

    -- Input control forces
    local angles = self:GetAngles()
    local inputPitch = LimitInputWithAngle( self.inputPitch, Abs( angles[1] ), params.maxPitch - 20 )
    local inputRoll = LimitInputWithAngle( self.inputRoll, Abs( angles[3] ), params.maxRoll - 20 )

    outAng[1] = outAng[1] + inputRoll * params.rollForce * inputMult * effectiveness * mass
    outAng[2] = outAng[2] + inputPitch * params.pitchForce * inputMult * effectiveness * mass
    outAng[3] = outAng[3] - self.inputYaw * params.yawForce * inputMult * effectiveness * mass

    -- Keep upright force
    outAng[1] = outAng[1] + rt:Dot( WORLD_UP ) * params.uprightForce * ( 1 - Abs( inputPitch ) ) * effectiveness * mass
    outAng[2] = outAng[2] + fw:Dot( WORLD_UP ) * params.uprightForce * ( 1 - Abs( inputRoll ) ) * effectiveness * mass

    -- Forward input force & speed limit
    local speed = localVel[1]

    if speed < params.maxSpeed and speed > -params.maxSpeed then
        AddForce( outLin, self.inputPitch * params.pushForwardForce * fw )
    end

    -- Stick to the ground
    if self.altitude < 25 and self:GetInputFloat( 1, "throttle" ) < 0.1 then
        AddForce( outLin, WORLD_UP * -200 )
    else
        -- Turbulance
        local t = CurTime()
        outAng[1] = outAng[1] + Cos( t * 2 ) * params.turbulanceForce * mass
        outAng[2] = outAng[2] + Cos( t * 1.5 ) * params.turbulanceForce * 0.5 * mass
    end
end

local Pow = math.pow
local Min = math.Min
local Remap = math.Remap

local power, speed

--- Simulate plane physics.
--- Uses these extra ENT functions and variables:
---
--- > number = self:GetPower()
--- > boolean = self.isGrounded
---
function ENT:SimulatePlane( phys, dt, params, effective, outLin, outAng )
    effectiveness = effective
    power = self:GetPower()
    mass = phys:GetMass()

    fw = self:GetForward()
    rt = self:GetRight()
    up = self:GetUp()

    vel = phys:GetVelocity()
    localVel = self:WorldToLocal( phys:GetPos() + vel )
    speed = localVel[1]

    local lift = Clamp( Abs( speed ) / params.liftSpeed, 0, 1 )

    lift = Pow( lift, 2 )

    -- Drag forces
    AddForce( outLin, -fw * Clamp( speed, -500, 500 ) * params.liftForwardDrag * lift )
    AddForce( outLin, rt * localVel[2] * params.liftSideDrag * lift )

    local drag = params.liftAngularDrag
    local angVel = phys:GetAngleVelocity()

    outAng[1] = outAng[1] + angVel[1] * drag[1] * mass * lift * effective
    outAng[2] = outAng[2] + angVel[2] * drag[2] * mass * lift * effective
    outAng[3] = outAng[3] + angVel[3] * drag[3] * mass * lift * effective

    -- Lift force
    AddForce( outLin, ( -localVel[3] * lift * params.liftFactor * up ) / dt )

    -- Try to align the plane towards the direction of movement
    vel:Normalize()

    outAng[2] = outAng[2] - vel:Dot( up ) * params.alignForce * mass * effective
    outAng[3] = outAng[3] - vel:Dot( rt ) * params.alignForce * mass * effective

    -- Slight yaw force when rolling left/right
    outAng[3] = outAng[3] + WORLD_UP:Dot( rt ) * params.yawForce * mass * 0.2

    -- Forward speed limit
    local maxSpeed = Remap( power, 0, 2, params.liftSpeed, params.maxSpeed )

    --[[if speed > maxSpeed then
        AddForce( outLin, -fw * params.engineForce * 2 )
    end]]

    -- Engine force
    local throttleInput = self:GetInputFloat( 1, "throttle" )

    -- Keep the plane going while off ground without any input
    if not self.isGrounded and Abs( throttleInput ) < 0.1 then
        throttleInput = Min( power, 1 )
    end

    if throttleInput > 0 and speed < maxSpeed then
        -- Forward acceleration
        AddForce( outLin, fw * params.engineForce * power * throttleInput )

    elseif throttleInput < 0 and speed > params.liftSpeed * 0.8 then
        -- Forward deceleration
        AddForce( outLin, fw * params.engineForce * Min( power, 1 ) * throttleInput )
    end

    local controllability = Clamp( Abs( speed * 0.5 ) / params.controlSpeed, 0, 1 )

    -- Rotate input forces
    outAng[1] = outAng[1] + self.inputRoll * params.rollForce * mass * controllability * effective
    outAng[2] = outAng[2] + self.inputPitch * params.pitchForce * mass * controllability * effective
    outAng[3] = outAng[3] - self.inputYaw * params.yawForce * mass * controllability * effective
end

function ENT:TriggerInput( name, value )
    if name == "Ignition" then
        local isOn = value > 0

        -- Avoid continous triggers
        if self.wireIsOn ~= isOn then
            self.wireIsOn = isOn

            if isOn then
                self:TurnOn()
            else
                self:TurnOff()
            end
        end

    elseif name == "Pitch" then
        self:SetInputFloat( 1, "pitch", Clamp( value, -1, 1 ) )

    elseif name == "Yaw" then
        self:SetInputFloat( 1, "rudder", Clamp( value, -1, 1 ) )

    elseif name == "Roll" then
        self:SetInputFloat( 1, "roll", Clamp( value, -1, 1 ) )

    elseif name == "Throttle" then
        self:SetInputFloat( 1, "throttle", Clamp( value, -1, 1 ) )

    elseif name == "Fire" then
        self:SetInputBool( 1, "attack", value > 0 )

    elseif name == "WeaponIndex" and self.weaponCount > 0 then
        self:SelectWeaponIndex( Clamp( value, 1, self.weaponCount ) )
    end
end
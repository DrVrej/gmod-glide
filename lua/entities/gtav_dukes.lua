-- Example car class
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_glide_car"
ENT.PrintName = "Dukes"

ENT.GlideCategory = "Default"
ENT.ChassisModel = "models/gta5/vehicles/dukes/chassis.mdl"

if CLIENT then
    ENT.CameraOffset = Vector( -270, 0, 50 )
    ENT.CameraFirstPersonOffset = Vector( 10, 0, 5 )

    ENT.ExhaustOffsets = {
        { pos = Vector( -128, 22, -7 ) },
        { pos = Vector( -128, -22, -7 ) }
    }

    ENT.EngineSmokeStrips = {
        { offset = Vector( 108, 0, -2 ), angle = Angle(), width = 40 }
    }

    ENT.EngineFireOffsets = {
        { offset = Vector( 75, 0, 5 ), angle = Angle() }
    }

    ENT.Headlights = {
        { offset = Vector( 102, 25, 2 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { offset = Vector( 102, -25, 2 ), color = Glide.DEFAULT_HEADLIGHT_COLOR }
    }

    ENT.LightSprites = {
        { type = "brake", offset = Vector( -125, 13, 5 ), dir = Vector( -1, 0, 0 ) },
        { type = "brake", offset = Vector( -125, -13, 5 ), dir = Vector( -1, 0, 0 ) },
        { type = "reverse", offset = Vector( -125, 21, 5 ), dir = Vector( -1, 0, 0 ) },
        { type = "reverse", offset = Vector( -125, -21, 5 ), dir = Vector( -1, 0, 0 ) },
        { type = "headlight", offset = Vector( 106, 29, -1 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 106, 22, -1 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 106, -29, -1 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR },
        { type = "headlight", offset = Vector( 106, -22, -1 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR }
    }

    function ENT:OnCreateEngineStream( stream )
        stream:LoadPreset( "dukes" )
    end
end

if SERVER then
    duplicator.RegisterEntityClass( "gtav_dukes", Glide.VehicleFactory, "Data" )

    ENT.SpawnPositionOffset = Vector( 0, 0, 40 )

    ENT.LightBodygroups = {
        { type = "brake", bodyGroupId = 19, subModelId = 1 },
        { type = "reverse", bodyGroupId = 20, subModelId = 1 },
        { type = "headlight", bodyGroupId = 21, subModelId = 1 }, -- Tail lights
        { type = "headlight", bodyGroupId = 22, subModelId = 1 }  -- Headlights
    }

    function ENT:CreateFeatures()
        self:CreateSeat( Vector( -26, 18, -13 ), Angle( 0, 270, -5 ), Vector( 40, 80, 0 ), true )
        self:CreateSeat( Vector( -8, -18, -18 ), Angle( 0, 270, 5 ), Vector( -40, -80, 0 ), true )

        -- Front left
        self:CreateWheel( Vector( 66.5, 37, -5 ), {
            model = "models/gta5/vehicles/dukes/wheel.mdl",
            modelAngle = Angle( 0, 90, 0 ),
            steerMultiplier = 1
        } )

        -- Front right
        self:CreateWheel( Vector( 66.5, -37, -5 ), {
            model = "models/gta5/vehicles/dukes/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 ),
            steerMultiplier = 1
        } )

        -- Rear left
        self:CreateWheel( Vector( -67, 37, -5 ), {
            model = "models/gta5/vehicles/dukes/wheel.mdl",
            modelAngle = Angle( 0, 90, 0 ),
            modelScale = Vector( 0.35, 1, 1 ),
            isPowered = true
        } )

        -- Rear right
        self:CreateWheel( Vector( -67, -37, -5 ), {
            model = "models/gta5/vehicles/dukes/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 ),
            modelScale = Vector( 0.35, 1, 1 ),
            isPowered = true
        } )

        self:ChangeWheelRadius( 15 )
    end
end
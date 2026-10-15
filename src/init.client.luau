--[[
    Telekenisis Demo
--]]

--[[ SERVICES ]]--
--#region

local UserInputService = game:GetService("UserInputService")

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Players = game:GetService("Players")

--#endregion

--[[ TYPE DEFINITIONS ]]--
--#region

--#endregion

--[[ SETTINGS ]]--
--#region

local CONFIG = {
    -- Configuration for grip mechanic
    grip = { 
        -- Maximum amount of objects that can be gripped at once.
        maximum = 4,


    }
}

local BINDS = {
    -- Start a new grip
    grip = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX }
}

--#endregion

--[[ CONSTANTS ]]--
--#region

local Camera = workspace.CurrentCamera

-- Player
local Player = Players.LocalPlayer
local Character = Player.Character 
local Humanoid: Humanoid = Character:FindFirstChildWhichIsA("Humanoid") or Character:WaitForChild("Humanoid")

-- RayCast Parameters
local GripCastParams = RaycastParams.new()
GripCastParams.CollisionGroup = { workspace.Grippable }
GripCastParams.FilterType = Enum.RaycastFilterType.Include

local WorldCastParams = RaycastParams.new()
WorldCastParams.CollisionGroup = { workspace.Collidable }
WorldCastParams.FilterType = Enum.RaycastFilterType.Include

--#endregion

--[[ FUNCTIONS ]]--
--#region

local function getAimRay()
    local input_type = UserInputService:GetLastInputType().Name -- Check if console or mobile
    local use_center = input_type:find("^Gamepad") or input_type == "Touch"

    local point = if use_center
        then Camera.ViewportSize/2 -- Use middle of screen for console
        else UserInputService:GetMouseLocation() -- Use mouse location for PC

    return Camera:ViewportPointToRay(point.X, point.Y)
end

--#endregion

--[[ GRIP OBJECT ]]--
--#region

local active_grips = {}
local grip = {}

function grip.new(obj: BasePart)
    local this = {
        object = obj
    }

    active_grips[obj] = this
    return this
end

function grip.has(obj: BasePart)
    return active_grips[obj] ~= nil; end
function grip.release(obj: BasePart)
    active_grips[obj] = nil; end

--#endregion

--[[ LOGIC ]]--
--#region

--[ Initialization ]--
--#region

--#endregion

--[ Inputs ]--
--#region

-- Table including logic for each input, "pressed" & "released" events.
local actions = {
    grip = { 
        pressed = function()
            if #active_grips>=CONFIG.grip.maximum then
                return end

            local aimRay = getAimRay() -- Generates a ray object based on platform (MKB or Console/Mobile)
            local aimCast = workspace:Raycast(aimRay.Origin, aimRay.Direction, GripCastParams)
            if not aimCast then return end

            local aimObj = aimCast.Instance
            if grip.has(aimObj) then
                grip.release(aimObj)
            else
                grip.new(aimObj)
            end
        end
    }
}

-- Translate actions into inverted tables for pressed & released with their
-- defined input for O(1) lookups.
local pressed, released = {}, {} 
for name, inputs in BINDS do
    for _, input in inputs do
        assert(not pressed[input] and not released[input], `Keybind {name} has a conflicting keybind "{input.Name}!" Please ensure bindings do not overlap.`)
        
        pressed[input]  = actions[name].pressed
        released[input] = actions[name].released
    end
end

-- Custom input dispatcher, I chose this system over CAS because to me, it
-- is more extendable than multiple CAS bindings, centralizing where actions
-- logic is and cleaning everything up.
local function dispatch(handlers, input, gp)
    -- We check KeyCode & UserInputType, as keyboard/controller uses KeyCode, and mouse/touch uses UserInputType
    local handler = handlers[input.KeyCode] or handlers[input.UserInputType]
    if handler then handler(); end
end

local input_connections = {
    began = UserInputService.InputBegan:Connect(function(i, gp)
        if not gp then dispatch(pressed, i); end
    end),
    ended = UserInputService.InputEnded:Connect(function(i, gp)
        dispatch(released, i)
    end)
}

--#endregion

--[ Runtime ]--
--#region



--#endregion

--#endregion
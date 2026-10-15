--[[
    Telekenisis Demo
--]]

--[[ SERVICES ]]--
--#region

local UserInputService = game:GetService("UserInputService")

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

        -- How many studs away an object can be gripped from.
        distance = 100
    }
}

local BINDS = {
    -- Start a new grip
    grip = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
    move = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }
}

--#endregion

--[[ CONSTANTS ]]--
--#region

local GrippableObjects = workspace.Grippable :: Folder & { [string]: BasePart }
local CollidableObjects = workspace.Collidable :: Folder & { [string]: BasePart }
local DebrisObjects = workspace.Debris :: Folder & { [string]: BasePart }

local Camera = workspace.CurrentCamera

-- Player
local Player = Players.LocalPlayer
local Character = Player.Character 
local Humanoid: Humanoid = Character:FindFirstChildWhichIsA("Humanoid") or Character:WaitForChild("Humanoid")

-- RayCast Parameters
local GripCastParams = RaycastParams.new()
GripCastParams.FilterDescendantsInstances = { GrippableObjects }
GripCastParams.FilterType = Enum.RaycastFilterType.Include

local WorldCastParams = RaycastParams.new()
WorldCastParams.FilterDescendantsInstances = { CollidableObjects }
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

function grip.new(root: BasePart, obj: BasePart)
    -- Generate attachments & constraint
    local baseAtt = Instance.new("Attachment", obj)

    local alignPos = Instance.new("AlignPosition", obj)
    alignPos.ApplyAtCenterOfMass = true
    alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
    alignPos.Attachment0 = baseAtt

    -- Compile grip object
    local diff = root.Position - obj.Position
    local this = {
        object = obj,
        root = root,

        dist = diff.Magnitude,
        dir = diff.Unit,

        att = {baseAtt},
        align = alignPos
    }

    obj:AddTag("Gripped")
    active_grips[obj] = this
    return this
end

function grip.has(obj: BasePart)
    return active_grips[obj] ~= nil; end
function grip.get(obj: BasePart)
    return active_grips[obj]; end

function grip.release(obj: BasePart)
    -- Get grip_obj
    local grip_obj = grip.get(obj)
    if not grip_obj then return end
    
    -- Destroy instances & cleanup
    grip_obj.align:Destroy()
    for _, att in grip_obj.att do
        att:Destroy()
    end

    obj:RemoveTag("Gripped")
    active_grips[obj] = nil
end

--#endregion

--[[ LOGIC ]]--
--#region

--[ Initialization ]--
--#region

local dragging

--#endregion

--[ Inputs ]--
--#region

-- Table including logic for each input, "pressed" & "released" events.
local actions: {[keyof<typeof(BINDS)>]: {pressed: (() -> ())?, released: (() -> ())?}} = {
    ["grip"] = { 
        pressed = function()
            if #active_grips>=CONFIG.grip.maximum then
                return end

            local aimRay = getAimRay() -- Generates a ray object based on platform (MKB or Console/Mobile)
            local aimCast = workspace:Raycast(aimRay.Origin, aimRay.Direction*CONFIG.grip.distance, GripCastParams)
            if not aimCast then return end

            local aimObj = aimCast.Instance
            if grip.has(aimObj) then
                grip.release(aimObj)
                print("Grip released")
            else
                grip.new(Humanoid.RootPart, aimObj)
                print(`New grip made`)
            end
        end
    },

    ["move"] = {
        pressed = function()
            local aimRay = getAimRay()
            local aimCast = workspace:Raycast(aimRay.Origin, aimRay.Direction*CONFIG.grip.distance, GripCastParams)
            if not aimCast then return end

            local aimObj = aimCast.Instance
            dragging = grip.get(aimObj)
        end,

        released = function()
            dragging = nil
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

local runtime = RunService.RenderStepped:Connect(function()
    for obj, grip in active_grips do
        local root_cf = grip.root.CFrame
        local offset_pos = root_cf + (grip.dir*grip.dist)

        grip.align.Position = offset_pos.Position
    end
end)

--#endregion

--[ Cleanup ]--
--#region

Humanoid.Died:Once(function()
    -- Cleanup grip objects to free all grips
    for obj in active_grips do
        grip.release(obj)
    end

    -- Cleanup inputs to avoid new logic being handled
    for i, conn in input_connections do
        conn:Disconnect()
        input_connections[i] = nil
    end

    -- Finally cleanup runtime to prevent errors
    runtime:Disconnect(); runtime = nil
end)

--#endregion

--#endregion
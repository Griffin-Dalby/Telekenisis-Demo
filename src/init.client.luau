--[[
    Telekenisis Demo
--]]

--[[ SERVICES ]]--
--#region

local ContextActionService = game:GetService("ContextActionService")
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
        distance = 100,

        -- Determines how sensitive the drag mechanic is. (studs/pixel)
        sensitivity = .005
    },

    debug = {
        gizmo = {
            -- Visualizes grip AlignPos targets
            grip_targets = true
        }
    }
}

local BINDS = {
    -- Start a new grip
    grip = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },

    -- Moves a telepathic grip
    move = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },

    -- Brings a telepathic grip closer/further
    distance = { Enum.UserInputType.MouseWheel }
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

    local targetP = Instance.new("Part", DebrisObjects)
    targetP.Name = "GripTarget"
    targetP.Size = Vector3.one/2
    targetP.Transparency = CONFIG.debug.gizmo.grip_targets and 0 or 1
    targetP.Color, targetP.Material = Color3.new(0, 1, 0), Enum.Material.Neon
    targetP.Anchored, targetP.CanCollide = true, false

    local targetAtt = Instance.new("Attachment", targetP)

    local alignPos = Instance.new("AlignPosition", obj)
    alignPos.ApplyAtCenterOfMass = true
    alignPos.Attachment0 = baseAtt
    alignPos.Attachment1 = targetAtt

    -- Compile grip object
    local diff = root.Position - obj.Position
    local local_dir = root.CFrame:VectorToObjectSpace(diff.Unit)
    local this = {
        object = obj,
        root = root,

        dist = diff.Magnitude,
        yaw = math.atan2(local_dir.X, local_dir.Z),
        pitch = math.asin(math.clamp(local_dir.Y, -1, 1)),

        att = {baseAtt, targetP},
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

local dragging -- Updated to whatever grip is currently being dragged
local scroll_delta = 0 -- Added to when scroll happens, and gets reset each time it's consumed & updated.

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
    if not actions[name] then continue end -- Skip inputs that have other/no handlers

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

ContextActionService:BindAction("telepath_scroll", function(_, state, input)
    if not dragging then return Enum.ContextActionResult.Pass end

    scroll_delta += input.Position.Z
    return Enum.ContextActionResult.Sink
end, false, table.unpack(BINDS.distance))

local last_mouse_position = UserInputService:GetMouseLocation()
local runtime = RunService.RenderStepped:Connect(function()
    --> Poll mouse delta
    local this_mouse_position = UserInputService:GetMouseLocation()

    local raw_mouse_delta = (this_mouse_position-last_mouse_position)
    local mouse_delta = raw_mouse_delta*CONFIG.grip.sensitivity

    last_mouse_position = this_mouse_position

    --> Update dragging grip
    if dragging then
        dragging.yaw -= mouse_delta.X -- Orbit around the character
        dragging.pitch = math.clamp(dragging.pitch+mouse_delta.Y, -math.pi/2, math.pi/2)

        dragging.dist += scroll_delta -- Add scroll_delta to distance
        scroll_delta = 0 -- Reset scroll_delta each frame for fresh accumulation
    end

    --> Update position targets
    for obj, grip in active_grips do
        local root_cf = grip.root.CFrame
        local last_pos = grip.att[2].Position
        
        -- Calculate new position
        local pitch_cos = math.cos(grip.pitch)
        local local_dir = Vector3.new(
            pitch_cos*math.sin(grip.yaw),
            math.sin(grip.pitch),
            pitch_cos*math.cos(grip.yaw)
        )
        
        local world_dir = root_cf:VectorToWorldSpace(local_dir)
        local grip_pos = grip.root.Position-(world_dir*grip.dist)

        grip.att[2].Position = grip_pos -- Update TargetP position (AlignPos Attachment1's parent)
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
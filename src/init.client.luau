-- Discord: griff2blurryy | Roblox: InfEnv
--[[
    Telekinesis Demo
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

        -- Determines how sensitive the drag mechanic is. (rads/pixel)
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

local GrippableObjects = workspace:WaitForChild("Grippable") :: Folder & { [string]: BasePart }
local CollidableObjects = workspace:WaitForChild("Collidable") :: Folder & { [string]: BasePart }
local DebrisObjects = workspace:WaitForChild("Debris") :: Folder & { [string]: BasePart }

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

local function getAimObj()
    local mouseLocation = UserInputService:GetMouseLocation()
    local aimRay = Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

    local aimCast = workspace:Raycast(
        aimRay.Origin,
        aimRay.Direction*CONFIG.grip.distance, -- Cap ray length to what's defined in config
        GripCastParams
    )
    if not aimCast then return end

    return aimCast.Instance -- Returns what got hit
end

--#endregion

--[[ GRIP OBJECT ]]--
--#region

--[ Type Definition ]--
--#region

type grip_fields = {
    object: BasePart,
    root: BasePart,

    dist: number,
    yaw: number,
    pitch: number,

    att: {Instance},
    align: AlignPosition
}
type grip_methods = {
    release: (self: GripObject) -> (),
}

type GripObject = grip_fields & grip_methods

--#endregion

local active_grips = {}
local grip = {} :: {
    new: (root: BasePart, obj: BasePart) -> GripObject,

    has: (obj: BasePart) -> boolean,
    get: (obj: BasePart) -> GripObject
} & grip_methods
grip.__index = grip

-- Constructor
function grip.new(root: BasePart, obj: BasePart)
    -- Generate attachments & constraint
    local base_att = Instance.new("Attachment")
    base_att.Parent = obj

    local target_p = Instance.new("Part")
    target_p.Name = "GripTarget"
    target_p.Size = Vector3.one/2
    target_p.Transparency = CONFIG.debug.gizmo.grip_targets and 0 or 1
    target_p.Color, target_p.Material = Color3.new(0, 1, 0), Enum.Material.Neon
    target_p.Anchored, target_p.CanCollide = true, false
    target_p.Parent = DebrisObjects

    local target_att = Instance.new("Attachment")
    target_att.Parent = target_p

    local align_pos = Instance.new("AlignPosition")
    align_pos.ApplyAtCenterOfMass = true
    align_pos.Attachment0 = base_att
    align_pos.Attachment1 = target_att
    align_pos.Parent = obj

    -- Compile grip object
    local diff = root.Position - obj.Position
    local local_dir = root.CFrame:VectorToObjectSpace(diff.Unit)
    local this: GripObject = setmetatable({
        object = obj,
        root = root,

        dist = diff.Magnitude,
        yaw = math.atan2(local_dir.X, local_dir.Z),
        pitch = math.asin(math.clamp(local_dir.Y, -1, 1)),

        att = {base_att, target_p},
        align = align_pos,
    }, grip)

    obj:AddTag("Gripped")
    active_grips[obj] = this
    return this
end

-- Top-level methods
function grip.has(obj: BasePart)
    return active_grips[obj] ~= nil; end
function grip.get(obj: BasePart)
    return active_grips[obj]; end

-- Class methods
function grip:release()
    -- Get grip_obj
    local obj = self.object
    
    -- Destroy instances & cleanup
    self.align:Destroy()
    for _, att in self.att do
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

            local aim_obj = getAimObj()
            if not aim_obj then return end

            if grip.has(aim_obj) then
                grip.get(aim_obj):release()
            else
                grip.new(Humanoid.RootPart, aim_obj)
            end
        end
    },

    ["move"] = {
        pressed = function()
            local aim_obj = getAimObj()
            if not aim_obj then return end

            dragging = grip.get(aim_obj)
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
        dragging.yaw -= mouse_delta.X -- Orbit left/right around the character
        dragging.pitch = math.clamp(dragging.pitch+mouse_delta.Y, -math.pi/2, math.pi/2) -- Orbit up/down around character (wrapped -90 to +90 degs)

        dragging.dist = math.clamp(dragging.dist+scroll_delta, 5, CONFIG.grip.distance) -- Add scroll_delta to distance
        scroll_delta = 0 -- Reset scroll_delta each frame for fresh accumulation
    end

    --> Update position targets
    for obj, grip in active_grips do
        local root_cf = grip.root.CFrame
        
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
    for _, grip in active_grips do
        grip:release()
    end

    -- Cleanup inputs to avoid new logic being handled
    for i, conn in input_connections do
        conn:Disconnect()
        input_connections[i] = nil
    end

    ContextActionService:UnbindAction("telepath_scroll")

    -- Finally cleanup runtime to prevent errors
    runtime:Disconnect(); runtime = nil
end)

--#endregion

--#endregion
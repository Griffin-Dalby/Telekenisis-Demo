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

type HighlightSettings = {
    Adornee: Instance?,
    DepthMode: Enum.HighlightDepthMode?,
    Color: {Outline: Color3?, Fill: Color3?}?,
    Transparency: {Outline: number?, Fill: number?}?,
}

--#endregion

--[[ SETTINGS ]]--
--#region

local CONFIG = {
    -- Configuration for grip mechanic
    grip = { 
        -- Maximum amount of objects that can be gripped at once.
        maximum = 4,

        -- How many studs away an object can be gripped from.
        distance = 50,

        -- Determines how sensitive the drag mechanic is. (rads/pixel)
        sensitivity = .005,

        -- Adjusts properties of the AlignPosition constraint
        constraint = {
            -- Mass*Acceleration(this) to get AlignPos MaxForce
            acceleration = 500,

            -- Maximum velocity of constraint
            max_velocity = 55,

            -- Responsiveness of constraint
            responsiveness = 15
        }
    },

    -- Configuration for debugging
    debug = {
        -- Small items that visualize what's happening
        gizmo = {
            -- Visualizes grip AlignPos targets
            grip_targets = true
        }
    }
}

-- Aiming is desktop-only by design.
local BINDS = {
    -- Start a new grip
    grip = { Enum.KeyCode.E },

    -- Moves a grip
    move = { Enum.UserInputType.MouseButton1 },

    -- Brings a grip closer/further
    distance = { Enum.UserInputType.MouseWheel }
}

--#endregion

--[[ CONSTANTS ]]--
--#region

local GrippableObjects = workspace:WaitForChild("Grippable") :: Folder & { [string]: BasePart }
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

--#endregion

--[[ FUNCTIONS ]]--
--#region

local function getAimObj()
    local mouseLocation = UserInputService:GetMouseLocation()
    local aimRay = Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

    local aimCast = workspace:Raycast(
        aimRay.Origin,
        aimRay.Direction*(CONFIG.grip.distance+5), -- Cap ray length to what's defined in config (add small buffer so it doesn't get stuck @ max)
        GripCastParams
    )
    if not aimCast then return end

    return aimCast.Instance -- Returns what got hit
end

local function generateHighlight(settings: HighlightSettings)
    local highlight = Instance.new("Highlight")
    if settings.Color and settings.Color.Outline then highlight.OutlineColor = settings.Color.Outline; end
    if settings.Color and settings.Color.Fill then highlight.FillColor = settings.Color.Fill; end

    if settings.Transparency and settings.Transparency.Outline then highlight.OutlineTransparency = settings.Transparency.Outline; end
    if settings.Transparency and settings.Transparency.Fill then highlight.FillTransparency = settings.Transparency.Fill; end

    if settings.DepthMode then highlight.DepthMode = settings.DepthMode; end
    highlight.Parent = DebrisObjects
    highlight.Adornee = settings.Adornee

    return highlight
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

    att: {from: Attachment, to: BasePart & {Attachment: Attachment}},
    align: AlignPosition,
    highlight: Highlight,
}
type grip_methods = {
    release: (self: GripObject) -> (),
}

type GripObject = grip_fields & grip_methods

--#endregion

local active_grip_count = 0
local active_grips = {}

local highlight_pool = {}

local grip = {} :: {
    new: (root: BasePart, obj: BasePart) -> GripObject,
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

    align_pos.MaxForce = obj.AssemblyMass*CONFIG.grip.constraint.acceleration
    align_pos.MaxVelocity = CONFIG.grip.constraint.max_velocity
    align_pos.Responsiveness = CONFIG.grip.constraint.responsiveness

    align_pos.Parent = obj

    -- Generate highlight
    local this_highlight = highlight_pool[1] or generateHighlight{
        Color = {
            Outline = Color3.new(.2, .8, 1),
            Fill = Color3.new(0, .2, .8),
        },
        Transparency = {
            Outline = .2,
            Fill = .4
        },
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }
    this_highlight.Adornee = obj

    -- Compile grip object
    local diff = root.Position - obj.Position
    local local_dir = root.CFrame:VectorToObjectSpace(diff.Unit)
    local this: GripObject = setmetatable({
        object = obj,
        root = root,

        dist = diff.Magnitude,
        yaw = math.atan2(local_dir.X, local_dir.Z),
        pitch = math.asin(math.clamp(local_dir.Y, -1, 1)),

        att = {from=base_att, to=target_p},
        align = align_pos,
        highlight = this_highlight
    }, grip)

    obj:AddTag("Gripped")
    active_grips[obj] = this
    active_grip_count += 1
    return this
end

-- Top-level methods
function grip.get(obj: BasePart)
    return active_grips[obj]; end

-- Class methods
function grip:release()
    -- Destroy instances & cleanup
    self.align:Destroy()
    for _, att in self.att do
        att:Destroy()
    end

    self.object:RemoveTag("Gripped")
    active_grips[self.object] = nil
    active_grip_count -= 1

    self.highlight.Adornee = nil
    table.insert(highlight_pool, self.highlight)
end

--#endregion

--[[ LOGIC ]]--
--#region

--[ Initialization ]--
--#region

local hovering: BasePart? -- Updated to whatever grippable object is currently being hovered
local dragging: GripObject? -- Updated to whatever grip is currently being dragged
local scroll_delta = 0 -- Added to when scroll happens, and gets reset each time it's consumed & updated.

local hover_highlight = generateHighlight{
    Color = {
        Outline = Color3.new(.2, .5, 1),
        Fill = Color3.new(0, 0, .5),
    },
    Transparency = {
        Outline = .4,
        Fill = .85
    },
    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
}

--#endregion

--[ Inputs ]--
--#region

-- Table including logic for each input, "pressed" & "released" events.
local actions: {[keyof<typeof(BINDS)>]: {pressed: (() -> ())?, released: (() -> ())?}} = {
    ["grip"] = { 
        pressed = function()
            if not hovering then return end
            local grip_obj = grip.get(hovering)

            if grip_obj then
                grip_obj:release()
            else
                if active_grip_count>=CONFIG.grip.maximum then
                    return end
                grip.new(Humanoid.RootPart, hovering)
            end
        end
    },

    ["move"] = {
        pressed = function()
            if not hovering then return end
            dragging = grip.get(hovering)

            if dragging then
                dragging.highlight.Enabled = false  
                hover_highlight.Adornee = dragging.object
            end
        end,

        released = function()
            if not dragging then return end
            dragging.highlight.Enabled = true
            hover_highlight.Adornee = nil

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

-- The exception is for the scroll wheel, which is polled in a CAS binding
-- below.
local function dispatch(handlers, input, gp)
    -- We check KeyCode & UserInputType, as keyboard uses KeyCode, and mouse uses UserInputType
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

ContextActionService:BindAction("telekinesis_scroll", function(_, state, input)
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
        dragging.pitch = math.clamp(dragging.pitch+mouse_delta.Y, -math.pi/2, math.pi/2) -- Orbit up/down around character (clamped -90 to +90 degs)

        dragging.dist = math.clamp(dragging.dist+scroll_delta, 5, CONFIG.grip.distance) -- Add scroll_delta to distance
        scroll_delta = 0 -- Reset scroll_delta each frame for fresh accumulation
    end

    --> Update position targets
    for obj, this in active_grips do
        local root_cf = this.root.CFrame
        
        -- Calculate new position
        -- Use spherical coordinates here to move positions around the
        -- root in a half-sphere, and push the target in/out originating
        -- from the root point.

        local pitch_cos = math.cos(this.pitch)
        local local_dir = Vector3.new(
            pitch_cos*math.sin(this.yaw),
            math.sin(this.pitch),
            pitch_cos*math.cos(this.yaw)
        )
        
        local world_dir = root_cf:VectorToWorldSpace(local_dir)
        local grip_pos = this.root.Position-(world_dir*this.dist)

        this.att.to.Position = grip_pos -- Update TargetP position (AlignPos Attachment1's parent)
    end
end)

local visuals = RunService.Heartbeat:Connect(function()
    -- Each frame hovering gets reset in this heartbeat, and it is used
    -- everywhere else when AimObj is needed. I do this so I can update
    -- visuals here, and have this raycast centralized to avoid
    -- unnecessary casts. 
    hovering = getAimObj()
    if not dragging then
        hover_highlight.Adornee = hovering
    end
end)

--#endregion

--[ Cleanup ]--
--#region

Humanoid.Died:Once(function()
    -- Cleanup grip objects to free all grips
    for _, this in active_grips do
        this:release()
    end

    -- Cleanup inputs to avoid new logic being handled
    for i, conn in input_connections do
        conn:Disconnect()
        input_connections[i] = nil
    end

    ContextActionService:UnbindAction("telekinesis_scroll")

    -- Finally cleanup runtimes to prevent errors
    runtime:Disconnect(); runtime = nil
    visuals:Disconnect(); visuals = nil
end)

--#endregion

--#endregion
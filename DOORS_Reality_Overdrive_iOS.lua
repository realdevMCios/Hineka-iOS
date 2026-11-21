--[[
    DOORS: REALITY OVERDRIVE — iOS Executor Edition
    Version: 2.0

    Features
      * Live FPS + frame-time HUD
      * Door tracking through ReplicatedStorage.GameData.LatestRoom
      * Graphics upgrade every 10 rooms (up to level 10)
      * Bloom, color grading, sun rays, atmosphere, depth-of-field
      * Locally enhanced lighting / PBR specular response where supported
      * Milestone notifications
      * Adaptive graphics quality when FPS drops
      * Draggable, collapsible mobile HUD
      * Cleanup function to restore modified Lighting settings

    Notes
      * This is a client-side visual filter, not hardware ray tracing.
      * Roblox/iOS and individual executors may restrict some properties.
      * FPS is measured from RenderStepped; the script does not unlock FPS.
]]

--// ENVIRONMENT / CLEANUP OLD INSTANCE
local ENV = _G
pcall(function()
    if typeof(getgenv) == "function" then
        ENV = getgenv()
    end
end)

if type(ENV.ROD_Cleanup) == "function" then
    pcall(ENV.ROD_Cleanup)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[REALITY OVERDRIVE] LocalPlayer not found.")
    return
end

local alive = true
local connections = {}
local ownedInstances = {}
local originalProperties = {}
local borrowedAtmosphere = nil
local createdAtmosphere = false

local function trackConnection(connection)
    table.insert(connections, connection)
    return connection
end

local function safeGet(instance, property)
    local ok, value = pcall(function()
        return instance[property]
    end)
    if ok then return value end
    return nil
end

local function safeSet(instance, property, value)
    if not instance then return false end
    return pcall(function()
        instance[property] = value
    end)
end

local function remember(instance, properties)
    for _, property in ipairs(properties) do
        local value = safeGet(instance, property)
        if value ~= nil then
            originalProperties[instance] = originalProperties[instance] or {}
            originalProperties[instance][property] = value
        end
    end
end

local function makeEffect(className, name)
    local ok, object = pcall(function()
        local effect = Instance.new(className)
        effect.Name = name
        effect.Parent = Lighting
        return effect
    end)
    if ok and object then
        table.insert(ownedInstances, object)
        return object
    end
    return nil
end

--// SAVE ORIGINAL LIGHTING STATE
remember(Lighting, {
    "Brightness",
    "ExposureCompensation",
    "Ambient",
    "OutdoorAmbient",
    "ColorShift_Top",
    "ColorShift_Bottom",
    "GlobalShadows",
    "ShadowSoftness",
    "EnvironmentDiffuseScale",
    "EnvironmentSpecularScale",
})

--// POST-PROCESSING EFFECTS
local Bloom = makeEffect("BloomEffect", "ROD2_Bloom")
local ColorGrade = makeEffect("ColorCorrectionEffect", "ROD2_ColorGrade")
local SunRays = makeEffect("SunRaysEffect", "ROD2_SunRays")
local DepthOfField = makeEffect("DepthOfFieldEffect", "ROD2_DepthOfField")
local SoftBlur = makeEffect("BlurEffect", "ROD2_SoftLens")

-- Reuse the game's Atmosphere if one already exists; otherwise create our own.
for _, child in ipairs(Lighting:GetChildren()) do
    if child:IsA("Atmosphere") then
        borrowedAtmosphere = child
        break
    end
end

if borrowedAtmosphere then
    remember(borrowedAtmosphere, {
        "Density", "Offset", "Color", "Decay", "Glare", "Haze"
    })
else
    local ok, atmosphere = pcall(function()
        local object = Instance.new("Atmosphere")
        object.Name = "ROD2_Atmosphere"
        object.Parent = Lighting
        return object
    end)
    if ok and atmosphere then
        borrowedAtmosphere = atmosphere
        createdAtmosphere = true
        table.insert(ownedInstances, atmosphere)
    end
end

--// STATE
local doorsOpened = 0
local lastRoomSeen = -1
local currentFPS = 0
local frameTimeMs = 0
local qualityScale = 1
local fpsAccumulator = 0
local fpsFrames = 0
local hud = nil
local tierLabel, fpsLabel, frameLabel, doorLabel, nextLabel, barFill
local notificationToken = 0
local lastAppliedTier = -1

local tierNames = {
    [0] = "BASE REALITY",
    [1] = "LUMEN BLOOM",
    [2] = "CINEMATIC HDR",
    [3] = "SHADOW DEPTH",
    [4] = "SPECULAR SURFACE",
    [5] = "CINEMATIC LIGHT",
    [6] = "VOLUMETRIC AIR",
    [7] = "PRISMATIC GLOW",
    [8] = "OPTICAL DEPTH",
    [9] = "EXTREME MATERIAL",
    [10] = "REALITY OVERDRIVE",
}

local tierColors = {
    [0] = Color3.fromRGB(135, 157, 180),
    [1] = Color3.fromRGB(74, 223, 255),
    [2] = Color3.fromRGB(92, 190, 255),
    [3] = Color3.fromRGB(111, 156, 255),
    [4] = Color3.fromRGB(154, 124, 255),
    [5] = Color3.fromRGB(190, 111, 255),
    [6] = Color3.fromRGB(224, 105, 255),
    [7] = Color3.fromRGB(255, 111, 203),
    [8] = Color3.fromRGB(255, 146, 112),
    [9] = Color3.fromRGB(255, 190, 91),
    [10] = Color3.fromRGB(255, 232, 123),
}

local function getTier()
    return math.clamp(math.floor(doorsOpened / 10), 0, 10)
end

local function getProgressToNextTier()
    if doorsOpened >= 100 then return 1 end
    return (doorsOpened % 10) / 10
end

--// GRAPHICS PROFILE
local function applyGraphics(force)
    if not alive then return end

    local tier = getTier()
    local progress = math.clamp(doorsOpened / 100, 0, 1)
    local power = progress * qualityScale
    local tint = tierColors[tier] or tierColors[10]

    if not force and tier == lastAppliedTier then
        -- Reapply only when adaptive quality changes; tier settings otherwise stay stable.
        return
    end
    lastAppliedTier = tier

    -- Bloom: increasingly vivid highlights, with a controlled threshold.
    if Bloom then
        Bloom.Enabled = tier >= 1
        Bloom.Intensity = (0.35 + power * 1.55) * qualityScale
        Bloom.Size = 22 + power * 34
        Bloom.Threshold = 1.15 - power * 0.30
    end

    -- Cinematic color grade.
    if ColorGrade then
        ColorGrade.Enabled = true
        ColorGrade.Brightness = -0.025 + power * 0.035
        ColorGrade.Contrast = 0.08 + power * 0.32
        ColorGrade.Saturation = -0.12 + power * 0.34
        ColorGrade.TintColor = Color3.new(
            1 - (power * 0.035),
            1 - (power * 0.015),
            1
        ):Lerp(tint:Lerp(Color3.new(1, 1, 1), 0.78), power * 0.26)
    end

    -- Rays become visible at higher tiers; keep them subtle in dark rooms.
    if SunRays then
        SunRays.Enabled = tier >= 3
        SunRays.Intensity = (0.025 + power * 0.13) * qualityScale
        SunRays.Spread = 0.82 + power * 0.16
    end

    -- Atmosphere: enhance an existing game atmosphere instead of wiping it.
    if borrowedAtmosphere then
        local atmospherePower = tier >= 6 and power or 0
        if createdAtmosphere then
            safeSet(borrowedAtmosphere, "Density", atmospherePower * 0.17)
            safeSet(borrowedAtmosphere, "Offset", 0.08 - atmospherePower * 0.12)
            safeSet(borrowedAtmosphere, "Color", Color3.fromRGB(190, 211, 255):Lerp(tint, atmospherePower * 0.22))
            safeSet(borrowedAtmosphere, "Decay", Color3.fromRGB(75, 82, 125):Lerp(tint, atmospherePower * 0.14))
            safeSet(borrowedAtmosphere, "Glare", atmospherePower * 0.20)
            safeSet(borrowedAtmosphere, "Haze", atmospherePower * 2.1)
        else
            local base = originalProperties[borrowedAtmosphere] or {}
            local baseDensity = base.Density or 0
            local baseOffset = base.Offset or 0
            local baseColor = base.Color or Color3.fromRGB(199, 199, 199)
            local baseDecay = base.Decay or Color3.fromRGB(106, 112, 125)
            local baseGlare = base.Glare or 0
            local baseHaze = base.Haze or 0
            safeSet(borrowedAtmosphere, "Density", math.clamp(baseDensity + atmospherePower * 0.10, 0, 1))
            safeSet(borrowedAtmosphere, "Offset", math.clamp(baseOffset - atmospherePower * 0.08, -1, 1))
            safeSet(borrowedAtmosphere, "Color", baseColor:Lerp(tint, atmospherePower * 0.18))
            safeSet(borrowedAtmosphere, "Decay", baseDecay:Lerp(tint, atmospherePower * 0.12))
            safeSet(borrowedAtmosphere, "Glare", math.clamp(baseGlare + atmospherePower * 0.12, 0, 10))
            safeSet(borrowedAtmosphere, "Haze", math.clamp(baseHaze + atmospherePower * 1.5, 0, 10))
        end
    end

    -- Depth-of-field only at the final tiers so normal gameplay remains readable.
    if DepthOfField then
        DepthOfField.Enabled = tier >= 8 and qualityScale >= 0.75
        DepthOfField.FocusDistance = 28
        DepthOfField.InFocusRadius = 70
        DepthOfField.NearIntensity = tier >= 9 and 0.035 * qualityScale or 0
        DepthOfField.FarIntensity = tier >= 8 and 0.045 * qualityScale or 0
    end

    -- Very mild lens softness at max tier; disabled automatically on weaker FPS.
    if SoftBlur then
        SoftBlur.Enabled = tier >= 10 and qualityScale >= 0.9
        SoftBlur.Size = 1.1
    end

    -- Improve Roblox's local ambient/specular response where the client permits it.
    local originalDiffuse = originalProperties[Lighting] and originalProperties[Lighting].EnvironmentDiffuseScale
    local originalSpecular = originalProperties[Lighting] and originalProperties[Lighting].EnvironmentSpecularScale
    local originalSoftness = originalProperties[Lighting] and originalProperties[Lighting].ShadowSoftness
    local originalExposure = originalProperties[Lighting] and originalProperties[Lighting].ExposureCompensation
    local originalAmbient = originalProperties[Lighting] and originalProperties[Lighting].Ambient
    local originalOutdoor = originalProperties[Lighting] and originalProperties[Lighting].OutdoorAmbient

    if originalDiffuse ~= nil then
        safeSet(Lighting, "EnvironmentDiffuseScale", math.clamp(originalDiffuse + power * 0.35, 0, 1))
    end
    if originalSpecular ~= nil then
        safeSet(Lighting, "EnvironmentSpecularScale", math.clamp(originalSpecular + power * 0.65, 0, 1))
    end
    if originalSoftness ~= nil then
        safeSet(Lighting, "ShadowSoftness", math.clamp(originalSoftness + power * 0.22, 0, 1))
    end
    if originalExposure ~= nil then
        safeSet(Lighting, "ExposureCompensation", originalExposure + power * 0.18)
    end
    if originalAmbient then
        safeSet(Lighting, "Ambient", originalAmbient:Lerp(Color3.fromRGB(72, 81, 120), power * 0.20))
    end
    if originalOutdoor then
        safeSet(Lighting, "OutdoorAmbient", originalOutdoor:Lerp(Color3.fromRGB(95, 111, 155), power * 0.18))
    end
    safeSet(Lighting, "GlobalShadows", true)
end

--// HUD HELPERS
local function newInstance(className, props, parent)
    local object = Instance.new(className)
    for property, value in pairs(props or {}) do
        pcall(function() object[property] = value end)
    end
    object.Parent = parent
    return object
end

local function addCorner(object, radius)
    newInstance("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, object)
end

local function addStroke(object, color, thickness, transparency)
    return newInstance("UIStroke", {
        Color = color or Color3.fromRGB(65, 220, 255),
        Thickness = thickness or 1,
        Transparency = transparency or 0.2,
    }, object)
end

local function addLabel(parent, name, text, size, position, font, textSize, color, alignment)
    return newInstance("TextLabel", {
        Name = name,
        BackgroundTransparency = 1,
        Text = text,
        Size = size,
        Position = position,
        Font = font or Enum.Font.GothamSemibold,
        TextSize = textSize or 12,
        TextColor3 = color or Color3.fromRGB(230, 242, 255),
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = false,
    }, parent)
end

local function createHUD()
    local screen = newInstance("ScreenGui", {
        Name = "RealityOverdriveHUD_v2",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    local guiParent
    pcall(function()
        if type(gethui) == "function" then
            guiParent = gethui()
        end
    end)
    if not guiParent then guiParent = CoreGui end

    local parentOK = pcall(function() screen.Parent = guiParent end)
    if not parentOK then
        screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    hud = screen

    local panel = newInstance("Frame", {
        Name = "Panel",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0, 12, 0, 82),
        Size = UDim2.fromOffset(252, 145),
        BackgroundColor3 = Color3.fromRGB(8, 13, 25),
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
    }, screen)
    addCorner(panel, 13)
    addStroke(panel, Color3.fromRGB(69, 218, 255), 1.35, 0.12)

    newInstance("UIGradient", {
        Rotation = 35,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 43, 71)),
            ColorSequenceKeypoint.new(0.52, Color3.fromRGB(12, 20, 38)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 10, 34)),
        }),
    }, panel)

    local topLine = newInstance("Frame", {
        Name = "TopAccent",
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = Color3.fromRGB(63, 226, 255),
        BorderSizePixel = 0,
    }, panel)
    newInstance("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(52, 222, 255)),
            ColorSequenceKeypoint.new(0.52, Color3.fromRGB(122, 112, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 89, 198)),
        }),
    }, topLine)

    local header = addLabel(
        panel, "Header", "R E A L I T Y   O V E R D R I V E",
        UDim2.new(1, -56, 0, 23), UDim2.fromOffset(11, 7),
        Enum.Font.GothamBold, 10, Color3.fromRGB(205, 224, 255)
    )

    local minimize = newInstance("TextButton", {
        Name = "Minimize",
        Text = "—",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = Color3.fromRGB(220, 238, 255),
        BackgroundColor3 = Color3.fromRGB(39, 57, 83),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(27, 22),
        Position = UDim2.new(1, -36, 0, 6),
    }, panel)
    addCorner(minimize, 6)

    local divider = newInstance("Frame", {
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.fromOffset(10, 34),
        BackgroundColor3 = Color3.fromRGB(90, 130, 175),
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
    }, panel)

    fpsLabel = addLabel(
        panel, "FPS", "-- FPS", UDim2.fromOffset(105, 31),
        UDim2.fromOffset(12, 39), Enum.Font.GothamBlack, 23,
        Color3.fromRGB(90, 255, 177)
    )

    frameLabel = addLabel(
        panel, "FrameTime", "--.- ms", UDim2.fromOffset(105, 18),
        UDim2.fromOffset(13, 68), Enum.Font.GothamMedium, 10,
        Color3.fromRGB(151, 177, 207)
    )

    doorLabel = addLabel(
        panel, "DoorCount", "DOOR 000", UDim2.fromOffset(112, 20),
        UDim2.new(1, -123, 0, 42), Enum.Font.GothamBold, 12,
        Color3.fromRGB(235, 243, 255), Enum.TextXAlignment.Right
    )

    tierLabel = addLabel(
        panel, "Tier", "LV 00  /  BASE REALITY", UDim2.new(1, -24, 0, 19),
        UDim2.fromOffset(12, 91), Enum.Font.GothamBold, 10,
        Color3.fromRGB(77, 225, 255)
    )

    local barBack = newInstance("Frame", {
        Name = "ProgressBack",
        Position = UDim2.fromOffset(12, 115),
        Size = UDim2.new(1, -24, 0, 7),
        BackgroundColor3 = Color3.fromRGB(40, 53, 76),
        BorderSizePixel = 0,
    }, panel)
    addCorner(barBack, 8)

    barFill = newInstance("Frame", {
        Name = "ProgressFill",
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(69, 224, 255),
        BorderSizePixel = 0,
    }, barBack)
    addCorner(barFill, 8)
    newInstance("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 225, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(193, 103, 255)),
        }),
    }, barFill)

    nextLabel = addLabel(
        panel, "NextTier", "NEXT UPGRADE IN 10 DOORS",
        UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 126),
        Enum.Font.GothamMedium, 8, Color3.fromRGB(164, 185, 216)
    )

    -- Mobile-friendly drag handle: drag from the header area.
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    trackConnection(panel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            local localY = input.Position.Y - panel.AbsolutePosition.Y
            if localY <= 35 then
                dragging = true
                dragStart = input.Position
                startPosition = panel.Position
                dragInput = input
            end
        end
    end))

    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end))

    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input == dragInput
            or input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragInput = nil
        end
    end))

    local minimized = false
    trackConnection(minimize.Activated:Connect(function()
        minimized = not minimized
        if minimized then
            panel.Size = UDim2.fromOffset(252, 37)
            minimize.Text = "+"
        else
            panel.Size = UDim2.fromOffset(252, 145)
            minimize.Text = "—"
        end
    end))

    return panel
end

--// MILESTONE TOAST
local function showMilestone(tier)
    if not hud or not hud.Parent then return end
    notificationToken += 1
    local thisToken = notificationToken
    local color = tierColors[tier] or tierColors[10]

    local toast = newInstance("Frame", {
        Name = "MilestoneToast",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 52),
        Size = UDim2.fromOffset(270, 66),
        BackgroundColor3 = Color3.fromRGB(9, 14, 29),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, hud)
    addCorner(toast, 12)
    addStroke(toast, color, 1.5, 0.1)

    addLabel(
        toast, "SmallTitle", "GRAPHICS EVOLVED",
        UDim2.new(1, -18, 0, 21), UDim2.fromOffset(10, 7),
        Enum.Font.GothamBold, 10, color
    )
    addLabel(
        toast, "TierTitle", string.format("LEVEL %02d  •  %s", tier, tierNames[tier]),
        UDim2.new(1, -18, 0, 23), UDim2.fromOffset(10, 29),
        Enum.Font.GothamBlack, 11, Color3.fromRGB(245, 248, 255)
    )

    TweenService:Create(toast, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.07,
        Position = UDim2.new(0.5, 0, 0, 62),
    }):Play()

    task.delay(2.5, function()
        if not alive or not toast.Parent or thisToken > notificationToken then
            if toast and toast.Parent then toast:Destroy() end
            return
        end
        local tween = TweenService:Create(toast, TweenInfo.new(0.3), {
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, 0, 0, 44),
        })
        tween:Play()
        tween.Completed:Connect(function()
            if toast then pcall(function() toast:Destroy() end) end
        end)
    end)
end

--// HUD REFRESH
local function updateHUD()
    if not hud or not hud.Parent then return end

    local tier = getTier()
    local color = tierColors[tier] or tierColors[10]
    local progress = getProgressToNextTier()

    if fpsLabel then
        fpsLabel.Text = string.format("%d FPS", currentFPS)
        if currentFPS >= 55 then
            fpsLabel.TextColor3 = Color3.fromRGB(88, 255, 174)
        elseif currentFPS >= 35 then
            fpsLabel.TextColor3 = Color3.fromRGB(255, 211, 102)
        else
            fpsLabel.TextColor3 = Color3.fromRGB(255, 104, 119)
        end
    end

    if frameLabel then
        frameLabel.Text = string.format("FRAME TIME  %.1f ms", frameTimeMs)
    end

    if doorLabel then
        doorLabel.Text = string.format("DOOR %03d", doorsOpened)
    end

    if tierLabel then
        tierLabel.Text = string.format("LV %02d  /  %s", tier, tierNames[tier])
        tierLabel.TextColor3 = color
    end

    if nextLabel then
        if doorsOpened >= 100 then
            nextLabel.Text = "MAX LEVEL REACHED  •  REALITY OVERDRIVE"
        else
            local remaining = 10 - (doorsOpened % 10)
            nextLabel.Text = string.format("NEXT UPGRADE IN %d DOOR%s", remaining, remaining == 1 and "" or "S")
        end
    end

    if barFill then
        TweenService:Create(barFill, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
            Size = UDim2.new(progress, 0, 1, 0),
            BackgroundColor3 = color,
        }):Play()
    end
end

--// DOOR / ROOM TRACKING
local function setDoorCount(value)
    local number = tonumber(value)
    if not number then return end
    number = math.max(0, math.floor(number))

    -- A return to room 0/1 indicates a new run; reset progression.
    if number <= 1 and doorsOpened > 1 and number < doorsOpened then
        doorsOpened = number
        lastRoomSeen = number
        applyGraphics(true)
        updateHUD()
        return
    end

    if number <= doorsOpened then return end

    local previousTier = getTier()
    doorsOpened = number
    lastRoomSeen = number
    local newTier = getTier()

    applyGraphics(true)
    updateHUD()

    if newTier > previousTier then
        showMilestone(newTier)
    end
end

--// CREATE HUD BEFORE STARTING TRACKERS
createHUD()
applyGraphics(true)
updateHUD()

--// PREFERRED TRACKER: DOORS GAME DATA
local hasLatestRoom = false

task.spawn(function()
    local gameData = ReplicatedStorage:WaitForChild("GameData", 18)
    if not alive or not gameData then return end

    local latestRoom = gameData:WaitForChild("LatestRoom", 12)
    if not alive or not latestRoom then return end

    hasLatestRoom = true
    setDoorCount(latestRoom.Value)

    trackConnection(latestRoom:GetPropertyChangedSignal("Value"):Connect(function()
        if alive then
            setDoorCount(latestRoom.Value)
        end
    end))
end)

--// FALLBACK TRACKER: CURRENTROOMS FOLDER
-- Used only if GameData.LatestRoom is not available.
task.spawn(function()
    local currentRooms = workspace:WaitForChild("CurrentRooms", 20)
    if not alive or not currentRooms then return end

    task.wait(4)
    if not alive or hasLatestRoom then return end

    local function readRoomName(instance)
        local n = tonumber(instance.Name)
        if n then setDoorCount(n) end
    end

    local highestRoom = nil
    for _, room in ipairs(currentRooms:GetChildren()) do
        local roomNumber = tonumber(room.Name)
        if roomNumber and (highestRoom == nil or roomNumber > highestRoom) then
            highestRoom = roomNumber
        end
    end
    if highestRoom ~= nil then
        setDoorCount(highestRoom)
    end

    trackConnection(currentRooms.ChildAdded:Connect(function(room)
        readRoomName(room)
    end))
end)

--// LIVE FPS METER + ADAPTIVE QUALITY
trackConnection(RunService.RenderStepped:Connect(function(deltaTime)
    if not alive then return end

    fpsFrames += 1
    fpsAccumulator += deltaTime

    if fpsAccumulator >= 0.6 then
        currentFPS = math.floor((fpsFrames / fpsAccumulator) + 0.5)
        frameTimeMs = currentFPS > 0 and (1000 / currentFPS) or 0

        fpsFrames = 0
        fpsAccumulator = 0

        local newQuality
        if currentFPS < 25 then
            newQuality = 0.50
        elseif currentFPS < 32 then
            newQuality = 0.62
        elseif currentFPS < 42 then
            newQuality = 0.76
        elseif currentFPS < 52 then
            newQuality = 0.88
        else
            newQuality = 1
        end

        if math.abs(newQuality - qualityScale) >= 0.05 then
            qualityScale = newQuality
            applyGraphics(true)
        end

        updateHUD()
    end
end))

--// CLEANUP: call getgenv().ROD_Cleanup() to stop and restore Lighting.
local function cleanup()
    if not alive then return end
    alive = false

    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end

    for instance, properties in pairs(originalProperties) do
        if instance and instance.Parent then
            for property, value in pairs(properties) do
                safeSet(instance, property, value)
            end
        end
    end

    for _, instance in ipairs(ownedInstances) do
        pcall(function() instance:Destroy() end)
    end

    if hud then
        pcall(function() hud:Destroy() end)
    end

    if createdAtmosphere and borrowedAtmosphere then
        pcall(function() borrowedAtmosphere:Destroy() end)
    end

    if ENV.ROD_Cleanup == cleanup then
        ENV.ROD_Cleanup = nil
    end

    print("[REALITY OVERDRIVE] Stopped. Original lighting restored where possible.")
end

ENV.ROD_Cleanup = cleanup

print("[REALITY OVERDRIVE] v2.0 loaded")
print("[REALITY OVERDRIVE] FPS HUD active | Door progression active")
print("[REALITY OVERDRIVE] Cleanup: getgenv().ROD_Cleanup()")

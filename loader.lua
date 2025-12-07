-- =============================================
-- КОДОВОЕ НАЗВАНИЕ: "CHRONOS-DELTA v2.0"
-- БИБЛИОТЕКА: Delta Executor
-- ТИП: Локальный Script в LocalScript
-- =============================================

-- Проверка наличия Delta функций
if not Delta or not Delta.GetPlayers then
    warn("[CHRONOS] Delta API не обнаружена. Завершение работы.")
    return
end

-- Конфигурация
local Config = {
    -- Aimbot настройки
    Aimbot = {
        Enabled = false, -- По умолчанию выключен, активируется через GUI
        TargetBone = "Head", -- Head, UpperTorso, HumanoidRootPart
        Smoothing = 0.7, -- 0 = мгновенно, 1 = максимально плавно
        FOV = 75, -- Градусы
        Prediction = 0.12, -- Прогнозирование движения (секунды)
        AutoFire = false, -- Автоматическая стрельба
        IgnoreWalls = true, -- Игнорировать стены и препятствия
        TeamCheck = true, -- Игнорировать свою команду
        MaxDistance = 2000, -- Максимальная дистанция
    },
    
    -- ESP настройки
    ESP = {
        Enabled = true,
        BoxType = "2D", -- 2D, 3D, Corner
        BoxColor = Color3.fromRGB(255, 50, 50),
        TeamBoxColor = Color3.fromRGB(50, 255, 50),
        ShowNames = true,
        ShowDistance = true,
        ShowHealth = true,
        ShowTracers = true, -- Линии к игрокам
        TracerOrigin = "Bottom", -- Bottom, Middle, Top, Mouse
        ShowSkeleton = false,
        ShowHeadDot = true,
        ThroughWalls = true, -- Отображать через стены
        MaxRenderDistance = 5000,
    },
    
    -- Визуальные эффекты
    Visuals = {
        FOVCircle = true,
        CircleColor = Color3.fromRGB(255, 50, 50),
        CircleThickness = 1.5,
        Watermark = true,
        ShowFPS = true,
    },
    
    -- Клавиши управления
    Keys = {
        ToggleMenu = Enum.KeyCode.Insert, -- Insert для открытия/закрытия меню
        ToggleAimbot = Enum.KeyCode.X, -- X для быстрого включения/выключения Aimbot
        PanicKey = Enum.KeyCode.End, -- End для экстренного выключения
    }
}

-- Глобальные переменные
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")

-- Кэш игровых объектов
local Target = nil
local ESPObjects = {}
local Connections = {}
local CurrentFOV = Config.Aimbot.FOV
local IsMenuOpen = true

-- Математические функции
local Math = {}
function Math.GetClosestPlayerToCursor()
    local ClosestPlayer = nil
    local ShortestDistance = Config.Aimbot.FOV
    
    for _, Player in pairs(Players:GetPlayers()) do
        if Player == LocalPlayer then continue end
        if Config.Aimbot.TeamCheck and Player.Team == LocalPlayer.Team then continue end
        
        local Character = Player.Character
        if not Character then continue end
        
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if not Humanoid or Humanoid.Health <= 0 then continue end
        
        local TargetPart = Character:FindFirstChild(Config.Aimbot.TargetBone)
        if not TargetPart then continue end
        
        -- Расчет расстояния от курсора до цели на экране
        local ScreenPosition, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
        if not OnScreen then continue end
        
        local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
        local TargetPosition = Vector2.new(ScreenPosition.X, ScreenPosition.Y)
        
        local Distance = (MousePosition - TargetPosition).Magnitude
        local AngleDistance = (Distance / Camera.ViewportSize.X) * 180
        
        -- Проверка на дистанцию в игре
        local RealDistance = (TargetPart.Position - Camera.CFrame.Position).Magnitude
        if RealDistance > Config.Aimbot.MaxDistance then continue end
        
        if AngleDistance < ShortestDistance then
            ShortestDistance = AngleDistance
            ClosestPlayer = {
                Player = Player,
                Character = Character,
                Part = TargetPart,
                Distance = RealDistance
            }
        end
    end
    
    return ClosestPlayer
end

function Math.CalculatePrediction(TargetPart, TravelTime)
    if not TargetPart or not TargetPart:IsA("BasePart") then 
        return TargetPart and TargetPart.Position or Vector3.zero
    end
    
    -- Простое линейное предсказание
    local Velocity = TargetPart.Velocity
    return TargetPart.Position + (Velocity * TravelTime)
end

function Math.SmoothAngle(Current, Target, Smoothing)
    return Current + (Target - Current) * (1 - Smoothing)
end

-- Aimbot система
local Aimbot = {}
Aimbot.LastTarget = nil
Aimbot.IsAiming = false

function Aimbot:GetTargetPosition(TargetData)
    if not TargetData then return nil end
    
    local TargetPart = TargetData.Part
    local TravelTime = Config.Aimbot.Prediction
    
    -- Если включено предсказание
    if Config.Aimbot.Prediction > 0 then
        return Math.CalculatePrediction(TargetPart, TravelTime)
    end
    
    return TargetPart.Position
end

function Aimbot:AimAtPosition(Position)
    if not Position then return end
    
    local CameraPosition = Camera.CFrame.Position
    local Direction = (Position - CameraPosition).Unit
    
    -- Вычисление углов
    local LookVector = Camera.CFrame.LookVector
    local CurrentAngle = math.atan2(LookVector.X, LookVector.Z)
    local TargetAngle = math.atan2(Direction.X, Direction.Z)
    
    -- Сглаживание
    local SmoothAngle = Math.SmoothAngle(CurrentAngle, TargetAngle, Config.Aimbot.Smoothing)
    
    -- Применение нового угла
    local NewCFrame = CFrame.new(Camera.CFrame.Position) * 
                      CFrame.Angles(0, SmoothAngle, 0) * 
                      CFrame.new(0, 0, -10)
    
    -- Манипуляция камерой через Delta
    if Delta and Delta.SetCameraCFrame then
        Delta.SetCameraCFrame(NewCFrame)
    else
        -- Фолбэк метод (менее точный)
        Camera.CFrame = NewCFrame
    end
end

function Aimbot:Update()
    if not Config.Aimbot.Enabled then 
        Target = nil
        return 
    end
    
    -- Поиск цели
    Target = Math.GetClosestPlayerToCursor()
    
    -- Прицеливание
    if Target then
        local TargetPosition = self:GetTargetPosition(Target)
        if TargetPosition then
            self:AimAtPosition(TargetPosition)
            self.IsAiming = true
            
            -- Авто-огонь
            if Config.Aimbot.AutoFire then
                Delta.Mouse1Click() -- Гипотетическая функция Delta
            end
        end
    else
        self.IsAiming = false
    end
    
    self.LastTarget = Target
end

-- ESP система с отображением через стены
local ESP = {}
ESP.DrawingObjects = {}

function ESP:CreateESPObject(Player)
    if not Player or not Player.Character then return end
    
    local Drawing = {}
    
    -- Создание Drawing объектов
    Drawing.Box = Drawing.new("Square")
    Drawing.Box.Thickness = 1.5
    Drawing.Box.Filled = false
    Drawing.Box.ZIndex = 10
    Drawing.Box.Visible = false
    
    Drawing.Tracer = Drawing.new("Line")
    Drawing.Tracer.Thickness = 1
    Drawing.Tracer.ZIndex = 5
    Drawing.Tracer.Visible = false
    
    Drawing.Name = Drawing.new("Text")
    Drawing.Name.Size = 14
    Drawing.Name.Center = true
    Drawing.Name.Outline = true
    Drawing.Name.ZIndex = 11
    Drawing.Name.Visible = false
    
    Drawing.Distance = Drawing.new("Text")
    Drawing.Distance.Size = 12
    Drawing.Distance.Center = true
    Drawing.Distance.Outline = true
    Drawing.Distance.ZIndex = 11
    Drawing.Distance.Visible = false
    
    Drawing.HealthBar = Drawing.new("Square")
    Drawing.HealthBar.Thickness = 1
    Drawing.HealthBar.Filled = true
    Drawing.HealthBar.ZIndex = 9
    Drawing.HealthBar.Visible = false
    
    Drawing.HealthBarBackground = Drawing.new("Square")
    Drawing.HealthBarBackground.Thickness = 1
    Drawing.HealthBarBackground.Filled = true
    Drawing.HealthBarBackground.ZIndex = 8
    Drawing.HealthBarBackground.Visible = false
    
    Drawing.HeadDot = Drawing.new("Circle")
    Drawing.HeadDot.Thickness = 1.5
    Drawing.HeadDot.Filled = true
    Drawing.HeadDot.ZIndex = 12
    Drawing.HeadDot.Visible = false
    
    ESP.DrawingObjects[Player] = Drawing
    return Drawing
end

function ESP:GetTeamColor(Player)
    if not Config.ESP then return Config.ESP.BoxColor end
    
    if Config.Aimbot.TeamCheck and Player.Team == LocalPlayer.Team then
        return Config.ESP.TeamBoxColor
    end
    
    return Config.ESP.BoxColor
end

function ESP:UpdatePlayerESP(Player, Drawing)
    if not Player or not Player.Character or not Drawing then return false end
    
    local Character = Player.Character
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid or Humanoid.Health <= 0 then return false end
    
    -- Получение позиций частей тела
    local Head = Character:FindFirstChild("Head")
    local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
    if not Head or not HumanoidRootPart then return false end
    
    -- Преобразование в координаты экрана
    local HeadPosition, HeadOnScreen = Camera:WorldToViewportPoint(Head.Position)
    local RootPosition, RootOnScreen = Camera:WorldToViewportPoint(HumanoidRootPart.Position)
    
    -- Если не на экране и не включено отображение через стены
    if not HeadOnScreen and not Config.ESP.ThroughWalls then
        return false
    end
    
    -- Расчет размеров бокса
    local BoxSize = Vector2.new(2000 / RootPosition.Z, 3000 / RootPosition.Z)
    local BoxPosition = Vector2.new(
        RootPosition.X - BoxSize.X / 2,
        RootPosition.Y - BoxSize.Y / 2
    )
    
    -- Цвет в зависимости от команды
    local TeamColor = self:GetTeamColor(Player)
    
    -- Обновление бокса
    Drawing.Box.Size = BoxSize
    Drawing.Box.Position = BoxPosition
    Drawing.Box.Color = TeamColor
    Drawing.Box.Visible = Config.ESP.Enabled and Config.ESP.BoxType ~= "None"
    
    -- Трейсеры
    if Config.ESP.ShowTracers then
        local TracerStart = Vector2.new()
        
        if Config.ESP.TracerOrigin == "Bottom" then
            TracerStart = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        elseif Config.ESP.TracerOrigin == "Middle" then
            TracerStart = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        elseif Config.ESP.TracerOrigin == "Top" then
            TracerStart = Vector2.new(Camera.ViewportSize.X / 2, 0)
        else -- Mouse
            TracerStart = Vector2.new(Mouse.X, Mouse.Y)
        end
        
        Drawing.Tracer.From = TracerStart
        Drawing.Tracer.To = Vector2.new(RootPosition.X, RootPosition.Y)
        Drawing.Tracer.Color = TeamColor
        Drawing.Tracer.Visible = Config.ESP.Enabled and Config.ESP.ShowTracers
    end
    
    -- Имя игрока
    if Config.ESP.ShowNames then
        Drawing.Name.Position = Vector2.new(
            RootPosition.X,
            BoxPosition.Y - 20
        )
        Drawing.Name.Text = Player.Name
        Drawing.Name.Color = TeamColor
        Drawing.Name.Visible = Config.ESP.Enabled and Config.ESP.ShowNames
    end
    
    -- Дистанция
    if Config.ESP.ShowDistance then
        local Distance = (HumanoidRootPart.Position - Camera.CFrame.Position).Magnitude
        
        Drawing.Distance.Position = Vector2.new(
            RootPosition.X,
            BoxPosition.Y + BoxSize.Y + 5
        )
        Drawing.Distance.Text = string.format("[%d studs]", math.floor(Distance))
        Drawing.Distance.Color = TeamColor
        Drawing.Distance.Visible = Config.ESP.Enabled and Config.ESP.ShowDistance
    end
    
    -- Полоска здоровья
    if Config.ESP.ShowHealth then
        local HealthPercent = Humanoid.Health / Humanoid.MaxHealth
        
        local HealthBarSize = Vector2.new(3, BoxSize.Y * HealthPercent)
        local HealthBarPosition = Vector2.new(
            BoxPosition.X - 8,
            BoxPosition.Y + BoxSize.Y - HealthBarSize.Y
        )
        
        Drawing.HealthBarBackground.Size = Vector2.new(3, BoxSize.Y)
        Drawing.HealthBarBackground.Position = Vector2.new(BoxPosition.X - 8, BoxPosition.Y)
        Drawing.HealthBarBackground.Color = Color3.fromRGB(50, 50, 50)
        Drawing.HealthBarBackground.Visible = Config.ESP.Enabled and Config.ESP.ShowHealth
        
        Drawing.HealthBar.Size = HealthBarSize
        Drawing.HealthBar.Position = HealthBarPosition
        Drawing.HealthBar.Color = Color3.fromRGB(
            255 - (255 * HealthPercent),
            255 * HealthPercent,
            50
        )
        Drawing.HealthBar.Visible = Config.ESP.Enabled and Config.ESP.ShowHealth
    end
    
    -- Точка на голове
    if Config.ESP.ShowHeadDot then
        Drawing.HeadDot.Position = Vector2.new(HeadPosition.X, HeadPosition.Y)
        Drawing.HeadDot.Radius = 4
        Drawing.HeadDot.Color = TeamColor
        Drawing.HeadDot.Visible = Config.ESP.Enabled and Config.ESP.ShowHeadDot
    end
    
    return true
end

function ESP:Update()
    if not Config.ESP.Enabled then
        for Player, Drawing in pairs(ESP.DrawingObjects) do
            for _, Obj in pairs(Drawing) do
                if Obj then
                    Obj.Visible = false
                end
            end
        end
        return
    end
    
    for _, Player in pairs(Players:GetPlayers()) do
        if Player == LocalPlayer then continue end
        
        local Drawing = ESP.DrawingObjects[Player]
        if not Drawing then
            Drawing = self:CreateESPObject(Player)
        end
        
        if Drawing then
            local IsValid = self:UpdatePlayerESP(Player, Drawing)
            if not IsValid then
                for _, Obj in pairs(Drawing) do
                    if Obj then
                        Obj.Visible = false
                    end
                end
            end
        end
    end
end

function ESP:Cleanup()
    for Player, Drawing in pairs(ESP.DrawingObjects) do
        for _, Obj in pairs(Drawing) do
            if Obj then
                Obj:Remove()
            end
        end
    end
    ESP.DrawingObjects = {}
end

-- Графический интерфейс (использует Roblox GUI)
local GUI = {}
GUI.ScreenGui = nil
GUI.MainFrame = nil

function GUI:Create()
    -- Создание ScreenGui
    GUI.ScreenGui = Instance.new("ScreenGui")
    GUI.ScreenGui.Name = "ChronosDeltaGUI"
    GUI.ScreenGui.ResetOnSpawn = false
    GUI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    GUI.ScreenGui.Parent = game:GetService("CoreGui")
    
    -- Основной фрейм
    GUI.MainFrame = Instance.new("Frame")
    GUI.MainFrame.Name = "MainFrame"
    GUI.MainFrame.Size = UDim2.new(0, 400, 0, 500)
    GUI.MainFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
    GUI.MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    GUI.MainFrame.BackgroundTransparency = 0.2
    GUI.MainFrame.BorderSizePixel = 0
    GUI.MainFrame.Active = true
    GUI.MainFrame.Draggable = true
    GUI.MainFrame.Visible = IsMenuOpen
    GUI.MainFrame.Parent = GUI.ScreenGui
    
    -- Тень
    local Shadow = Instance.new("Frame")
    Shadow.Size = UDim2.new(1, 6, 1, 6)
    Shadow.Position = UDim2.new(0, -3, 0, -3)
    Shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Shadow.BackgroundTransparency = 0.8
    Shadow.BorderSizePixel = 0
    Shadow.ZIndex = -1
    Shadow.Parent = GUI.MainFrame
    
    -- Заголовок
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 40)
    Title.Position = UDim2.new(0, 0, 0, 0)
    Title.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    Title.BorderSizePixel = 0
    Title.Text = "CHRONOS DELTA v2.0"
    Title.TextColor3 = Color3.fromRGB(255, 100, 100)
    Title.TextSize = 20
    Title.Font = Enum.Font.GothamBold
    Title.Parent = GUI.MainFrame
    
    -- Кнопка закрытия
    local CloseButton = Instance.new("TextButton")
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Position = UDim2.new(1, -35, 0, 5)
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    CloseButton.BorderSizePixel = 0
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.white
    CloseButton.TextSize = 18
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.Parent = GUI.MainFrame
    
    CloseButton.MouseButton1Click:Connect(function()
        IsMenuOpen = not IsMenuOpen
        GUI.MainFrame.Visible = IsMenuOpen
    end)
    
    -- Создание вкладок
    local TabButtons = {}
    local TabFrames = {}
    local Tabs = {"Aimbot", "ESP", "Visuals", "Settings"}
    
    local TabContainer = Instance.new("Frame")
    TabContainer.Size = UDim2.new(1, -20, 0, 30)
    TabContainer.Position = UDim2.new(0, 10, 0, 45)
    TabContainer.BackgroundTransparency = 1
    TabContainer.Parent = GUI.MainFrame
    
    local ContentFrame = Instance.new("Frame")
    ContentFrame.Size = UDim2.new(1, -20, 1, -100)
    ContentFrame.Position = UDim2.new(0, 10, 0, 80)
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.Parent = GUI.MainFrame
    
    for i, TabName in ipairs(Tabs) do
        -- Кнопка вкладки
        local TabButton = Instance.new("TextButton")
        TabButton.Size = UDim2.new(0.25, 0, 1, 0)
        TabButton.Position = UDim2.new(0.25 * (i-1), 0, 0, 0)
        TabButton.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
        TabButton.BorderSizePixel = 0
        TabButton.Text = TabName
        TabButton.TextColor3 = Color3.fromRGB(200, 200, 200)
        TabButton.TextSize = 14
        TabButton.Font = Enum.Font.Gotham
        TabButton.Parent = TabContainer
        
        -- Фрейм вкладки
        local TabFrame = Instance.new("Frame")
        TabFrame.Size = UDim2.new(1, 0, 1, 0)
        TabFrame.Position = UDim2.new(0, 0, 0, 0)
        TabFrame.BackgroundTransparency = 1
        TabFrame.Visible = i == 1
        TabFrame.Parent = ContentFrame
        
        TabButtons[TabName] = TabButton
        TabFrames[TabName] = TabFrame
        
        TabButton.MouseButton1Click:Connect(function()
            for _, Frame in pairs(TabFrames) do
                Frame.Visible = false
            end
            for _, Button in pairs(TabButtons) do
                Button.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            end
            
            TabFrame.Visible = true
            TabButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
        end)
        
        if i == 1 then
            TabButton.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
        end
    end
    
    -- Функция создания переключателя
    local function CreateToggle(Parent, Name, ConfigTable, ConfigKey, PositionY)
        local ToggleFrame = Instance.new("Frame")
        ToggleFrame.Size = UDim2.new(1, 0, 0, 30)
        ToggleFrame.Position = UDim2.new(0, 0, 0, PositionY)
        ToggleFrame.BackgroundTransparency = 1
        ToggleFrame.Parent = Parent
        
        local ToggleLabel = Instance.new("TextLabel")
        ToggleLabel.Size = UDim2.new(0.7, 0, 1, 0)
        ToggleLabel.Position = UDim2.new(0, 0, 0, 0)
        ToggleLabel.BackgroundTransparency = 1
        ToggleLabel.Text = Name
        ToggleLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        ToggleLabel.TextSize = 14
        ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
        ToggleLabel.Font = Enum.Font.Gotham
        ToggleLabel.Parent = ToggleFrame
        
        local ToggleButton = Instance.new("TextButton")
        ToggleButton.Size = UDim2.new(0, 50, 0, 25)
        ToggleButton.Position = UDim2.new(1, -55, 0.5, -12.5)
        ToggleButton.BackgroundColor3 = ConfigTable[ConfigKey] and 
                                       Color3.fromRGB(100, 255, 100) or 
                                       Color3.fromRGB(255, 100, 100)
        ToggleButton.BorderSizePixel = 0
        ToggleButton.Text = ConfigTable[ConfigKey] and "ON" or "OFF"
        ToggleButton.TextColor3 = Color3.white
        ToggleButton.TextSize = 12
        ToggleButton.Font = Enum.Font.GothamBold
        ToggleButton.Parent = ToggleFrame
        
        ToggleButton.MouseButton1Click:Connect(function()
            ConfigTable[ConfigKey] = not ConfigTable[ConfigKey]
            ToggleButton.BackgroundColor3 = ConfigTable[ConfigKey] and 
                                           Color3.fromRGB(100, 255, 100) or 
                                           Color3.fromRGB(255, 100, 100)
            ToggleButton.Text = ConfigTable[ConfigKey] and "ON" or "OFF"
        end)
        
        return ToggleFrame
    end
    
    -- Функция создания слайдера
    local function CreateSlider(Parent, Name, ConfigTable, ConfigKey, Min, Max, PositionY)
        local SliderFrame = Instance.new("Frame")
        SliderFrame.Size = UDim2.new(1, 0, 0, 40)
        SliderFrame.Position = UDim2.new(0, 0, 0, PositionY)
        SliderFrame.BackgroundTransparency = 1
        SliderFrame.Parent = Parent
        
        local SliderLabel = Instance.new("TextLabel")
        SliderLabel.Size = UDim2.new(1, 0, 0, 20)
        SliderLabel.Position = UDim2.new(0, 0, 0, 0)
        SliderLabel.BackgroundTransparency = 1
        SliderLabel.Text = Name .. ": " .. tostring(ConfigTable[ConfigKey])
        SliderLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        SliderLabel.TextSize = 14
        SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
        SliderLabel.Font = Enum.Font.Gotham
        SliderLabel.Parent = SliderFrame
        
        local SliderTrack = Instance.new("Frame")
        SliderTrack.Size = UDim2.new(1, -10, 0, 4)
        SliderTrack.Position = UDim2.new(0, 5, 1, -10)
        SliderTrack.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        SliderTrack.BorderSizePixel = 0
        SliderTrack.Parent = SliderFrame
        
        local SliderFill = Instance.new("Frame")
        local Percent = (ConfigTable[ConfigKey] - Min) / (Max - Min)
        SliderFill.Size = UDim2.new(Percent, 0, 1, 0)
        SliderFill.Position = UDim2.new(0, 0, 0, 0)
        SliderFill.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        SliderFill.BorderSizePixel = 0
        SliderFill.Parent = SliderTrack
        
        local SliderButton = Instance.new("TextButton")
        SliderButton.Size = UDim2.new(0, 20, 0, 20)
        SliderButton.Position = UDim2.new(Percent, -10, 0.5, -10)
        SliderButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        SliderButton.BorderSizePixel = 0
        SliderButton.Text = ""
        SliderButton.Parent = SliderTrack
        
        local Dragging = false
        
        local function UpdateSlider(X)
            local RelativeX = math.clamp((X - SliderTrack.AbsolutePosition.X) / 
                                        SliderTrack.AbsoluteSize.X, 0, 1)
            local Value = math.floor(Min + (Max - Min) * RelativeX)
            
            ConfigTable[ConfigKey] = Value
            SliderLabel.Text = Name .. ": " .. tostring(Value)
            SliderFill.Size = UDim2.new(RelativeX, 0, 1, 0)
            SliderButton.Position = UDim2.new(RelativeX, -10, 0.5, -10)
        end
        
        SliderButton.MouseButton1Down:Connect(function()
            Dragging = true
        end)
        
        game:GetService("UserInputService").InputEnded:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                Dragging = false
            end
        end)
        
        game:GetService("UserInputService").InputChanged:Connect(function(Input)
            if Dragging and Input.UserInputType == Enum.UserInputType.MouseMovement then
                UpdateSlider(Input.Position.X)
            end
        end)
        
        return SliderFrame
    end
    
    -- Заполнение вкладок
    -- Вкладка Aimbot
    local CurrentY = 10
    CreateToggle(TabFrames["Aimbot"], "Enable Aimbot", Config.Aimbot, "Enabled", CurrentY)
    CurrentY = CurrentY + 35
    
    local BoneDropdown = Instance.new("TextButton")
    BoneDropdown.Size = UDim2.new(1, 0, 0, 30)
    BoneDropdown.Position = UDim2.new(0, 0, 0, CurrentY)
    BoneDropdown.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    BoneDropdown.BorderSizePixel = 0
    BoneDropdown.Text = "Target Bone: " .. Config.Aimbot.TargetBone
    BoneDropdown.TextColor3 = Color3.fromRGB(220, 220, 220)
    BoneDropdown.TextSize = 14
    BoneDropdown.Font = Enum.Font.Gotham
    BoneDropdown.Parent = TabFrames["Aimbot"]
    
    BoneDropdown.MouseButton1Click:Connect(function()
        local Bones = {"Head", "UpperTorso", "HumanoidRootPart"}
        local CurrentIndex = table.find(Bones, Config.Aimbot.TargetBone) or 1
        local NextIndex = CurrentIndex % #Bones + 1
        Config.Aimbot.TargetBone = Bones[NextIndex]
        BoneDropdown.Text = "Target Bone: " .. Config.Aimbot.TargetBone
    end)
    
    CurrentY = CurrentY + 40
    CreateToggle(TabFrames["Aimbot"], "Ignore Walls", Config.Aimbot, "IgnoreWalls", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["Aimbot"], "Team Check", Config.Aimbot, "TeamCheck", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["Aimbot"], "Auto Fire", Config.Aimbot, "AutoFire", CurrentY)
    CurrentY = CurrentY + 35
    CreateSlider(TabFrames["Aimbot"], "FOV", Config.Aimbot, "FOV", 1, 360, CurrentY)
    CurrentY = CurrentY + 50
    CreateSlider(TabFrames["Aimbot"], "Smoothing", Config.Aimbot, "Smoothing", 0, 100, CurrentY)
    CurrentY = CurrentY + 50
    
    -- Вкладка ESP
    CurrentY = 10
    CreateToggle(TabFrames["ESP"], "Enable ESP", Config.ESP, "Enabled", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Through Walls", Config.ESP, "ThroughWalls", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Box", Config.ESP, "Box", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Names", Config.ESP, "ShowNames", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Distance", Config.ESP, "ShowDistance", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Health", Config.ESP, "ShowHealth", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Tracers", Config.ESP, "ShowTracers", CurrentY)
    CurrentY = CurrentY + 35
    CreateToggle(TabFrames["ESP"], "Show Head Dot", Config.ESP, "ShowHeadDot", CurrentY)
    CurrentY = CurrentY + 35
    
    -- Вкладка Settings
    CurrentY = 10
    local KeybindButton = Instance.new("TextButton")
    KeybindButton.Size = UDim2.new(1, 0, 0, 30)
    KeybindButton.Position = UDim2.new(0, 0, 0, CurrentY)
    KeybindButton.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    KeybindButton.BorderSizePixel = 0
    KeybindButton.Text = "Aimbot Key: " .. tostring(Config.Keys.ToggleAimbot)
    KeybindButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    KeybindButton.TextSize = 14
    KeybindButton.Font = Enum.Font.Gotham
    KeybindButton.Parent = TabFrames["Settings"]
    
    KeybindButton.MouseButton1Click:Connect(function()
        KeybindButton.Text = "Press any key..."
        local Input = game:GetService("UserInputService").InputBegan:Wait()
        Config.Keys.ToggleAimbot = Input.KeyCode
        KeybindButton.Text = "Aimbot Key: " .. tostring(Input.KeyCode)
    end)
    
    CurrentY = CurrentY + 40
    
    local UnloadButton = Instance.new("TextButton")
    UnloadButton.Size = UDim2.new(1, 0, 0, 40)
    UnloadButton.Position = UDim2.new(0, 0, 0, CurrentY)
    UnloadButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    UnloadButton.BorderSizePixel = 0
    UnloadButton.Text = "UNLOAD SCRIPT"
    UnloadButton.TextColor3 = Color3.white
    UnloadButton.TextSize = 16
    UnloadButton.Font = Enum.Font.GothamBold
    UnloadButton.Parent = TabFrames["Settings"]
    
    UnloadButton.MouseButton1Click:Connect(function()
        GUI:Destroy()
        ESP:Cleanup()
        for _, Connection in pairs(Connections) do
            Connection:Disconnect()
        end
        warn("[CHRONOS] Script unloaded.")
    end)
    
    return GUI.ScreenGui
end

function GUI:Destroy()
    if self.ScreenGui then
        self.ScreenGui:Destroy()
        self.ScreenGui = nil
    end
end

-- Визуальные элементы (FOV круг)
local Visuals = {}
Visuals.FOVCircle = nil

function Visuals:CreateFOVCircle()
    if not Config.Visuals.FOVCircle then
        if self.FOVCircle then
            self.FOVCircle:Remove()
            self.FOVCircle = nil
        end
        return
    end
    
    if not self.FOVCircle then
        self.FOVCircle = Drawing.new("Circle")
        self.FOVCircle.Thickness = Config.Visuals.CircleThickness
        self.FOVCircle.NumSides = 64
        self.FOVCircle.Filled = false
        self.FOVCircle.ZIndex = 999
    end
    
    self.FOVCircle.Color = Config.Visuals.CircleColor
    self.FOVCircle.Position = Vector2.new(
        Camera.ViewportSize.X / 2,
        Camera.ViewportSize.Y / 2
    )
    self.FOVCircle.Radius = (Config.Aimbot.FOV / 180) * (Camera.ViewportSize.Y / 2)
    self.FOVCircle.Visible = Config.Aimbot.Enabled and Config.Visuals.FOVCircle
end

function Visuals:Update()
    self:CreateFOVCircle()
    
    -- Водяной знак
    if Config.Visuals.Watermark then
        Drawing.Fonts = {}
        local WatermarkText = string.format(
            "CHRONOS DELTA | FPS: %d | Aimbot: %s | Target: %s",
            math.floor(1/RunService.RenderStepped:Wait()),
            Config.Aimbot.Enabled and "ON" or "OFF",
            Target and Target.Player.Name or "None"
        )
        
        -- Это псевдокод для Drawing API
        if Drawing and Drawing.new then
            if not self.Watermark then
                self.Watermark = Drawing.new("Text")
                self.Watermark.Size = 16
                self.Watermark.Outline = true
                self.Watermark.ZIndex = 1000
            end
            
            self.Watermark.Text = WatermarkText
            self.Watermark.Position = Vector2.new(10, 10)
            self.Watermark.Color = Color3.fromRGB(255, 100, 100)
            self.Watermark.Visible = true
        end
    elseif self.Watermark then
        self.Watermark.Visible = false
    end
end

-- Обработка ввода
local InputHandler = {}
function InputHandler:BindKeys()
    -- Переключение меню (Insert)
    table.insert(Connections, game:GetService("UserInputService").InputBegan:Connect(function(Input)
        if Input.KeyCode == Config.Keys.ToggleMenu then
            IsMenuOpen = not IsMenuOpen
            if GUI.MainFrame then
                GUI.MainFrame.Visible = IsMenuOpen
            end
        end
        
        -- Быстрое переключение Aimbot (X)
        if Input.KeyCode == Config.Keys.ToggleAimbot then
            Config.Aimbot.Enabled = not Config.Aimbot.Enabled
            if GUI and GUI.MainFrame then
                -- Обновить UI если открыт
            end
        end
        
        -- Паника (End)
        if Input.KeyCode == Config.Keys.PanicKey then
            Config.Aimbot.Enabled = false
            Config.ESP.Enabled = false
            if GUI and GUI.MainFrame then
                GUI.MainFrame.Visible = false
            end
            warn("[CHRONOS] Panic mode activated.")
        end
    end))
end

-- Основной цикл
function Main()
    print("[CHRONOS] Initializing...")
    
    -- Инициализация GUI
    GUI:Create()
    
    -- Привязка клавиш
    InputHandler:BindKeys()
    
    print("[CHRONOS] Loaded successfully. Press INSERT to open menu.")
    print("[CHRONOS] Aimbot Key:", Config.Keys.ToggleAimbot)
    
    -- Основной цикл обновления
    local RenderStepped = RunService.RenderStepped
    
    table.insert(Connections, RenderStepped:Connect(function(deltaTime)
        -- Обновление Aimbot
        Aimbot:Update()
        
        -- Обновление ESP
        ESP:Update()
        
        -- Обновление визуалов
        Visuals:Update()
        
        -- Обновление FOV из конфига
        CurrentFOV = Config.Aimbot.FOV
    end))
end

-- Запуск с обработкой ошибок
local success, err = pcall(Main)
if not success then
    warn("[CHRONOS] Initialization failed:", err)
    
    -- Попытка очистки
    pcall(function()
        if GUI then GUI:Destroy() end
        if ESP then ESP:Cleanup() end
    end)
end

-- Возвращаем объект для ручного управления
return {
    Config = Config,
    ToggleAimbot = function()
        Config.Aimbot.Enabled = not Config.Aimbot.Enabled
        return Config.Aimbot.Enabled
    end,
    ToggleESP = function()
        Config.ESP.Enabled = not Config.ESP.Enabled
        return Config.ESP.Enabled
    end,
    Unload = function()
        if GUI then GUI:Destroy() end
        if ESP then ESP:Cleanup() end
        for _, Connection in pairs(Connections) do
            pcall(function() Connection:Disconnect() end)
        end
    end
}

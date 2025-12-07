-- ============================================
-- CHRONOS AIMBOT - Загрузчик
-- GitHub: https://github.com/markkir2013-web/CHRONOS-AIMBOT
-- ============================================

local VERSION = "1.0.0"
local REPO_URL = "https://github.com/markkir2013-web/CHRONOS-AIMBOT"
local AUTHOR = "markkir2013-web"

print("╔══════════════════════════════════════╗")
print("║     CHRONOS AIMBOT Loader v" .. VERSION .. "     ║")
print("║      GitHub: " .. AUTHOR .. "       ║")
print("╚══════════════════════════════════════╝")

-- Конфигурация
local Config = {
    DebugMode = false,
    AutoUpdate = true,
    LoadModules = true
}

-- Основная функция загрузки
local function LoadScript()
    local mainScriptUrl = "https://raw.githubusercontent.com/markkir2013-web/CHRONOS-AIMBOT/main/code"
    
    print("[LOADER] Загрузка основного скрипта...")
    
    -- Пытаемся загрузить
    local success, response = pcall(function()
        return game:HttpGet(mainScriptUrl, true)
    end)
    
    if not success then
        warn("[ERROR] Не удалось загрузить скрипт:")
        warn(response)
        return false
    end
    
    -- Проверяем, что код не пустой
    if #response < 10 then
        warn("[ERROR] Скрипт слишком короткий или пустой")
        return false
    end
    
    -- Компилируем и выполняем
    local func, err = loadstring(response)
    
    if not func then
        warn("[ERROR] Ошибка компиляции Lua:")
        warn(err)
        return false
    end
    
    -- Запускаем скрипт
    print("[LOADER] Скрипт загружен, запуск...")
    local execSuccess, execErr = pcall(func)
    
    if not execSuccess then
        warn("[ERROR] Ошибка выполнения:")
        warn(execErr)
        return false
    end
    
    print("[LOADER] ✅ Скрипт успешно запущен!")
    return true
end

-- Функция проверки обновлений
local function CheckForUpdates()
    if not Config.AutoUpdate then return end
    
    print("[UPDATER] Проверка обновлений...")
    
    -- Здесь можно добавить логику проверки версий
    -- Например, сравнение с версией из другого файла
end

-- Функция загрузки модулей
local function LoadModules()
    if not Config.LoadModules then return end
    
    local modules = {
        "utils",
        "config",
        "gui"
    }
    
    for _, module in ipairs(modules) do
        local moduleUrl = string.format(
            "https://raw.githubusercontent.com/markkir2013-web/CHRONOS-AIMBOT/main/modules/%s.lua",
            module
        )
        
        -- Пытаемся загрузить каждый модуль
        pcall(function()
            local code = game:HttpGet(moduleUrl)
            loadstring(code)()
            print("[MODULES] Загружен модуль: " .. module)
        end)
    end
end

-- Главная функция
local function Main()
    print("[INIT] Инициализация загрузчика...")
    
    -- Проверяем окружение (если нужно)
    if not game or not game:GetService then
        warn("[ERROR] Неподдерживаемая среда выполнения")
        return
    end
    
    -- Проверка обновлений
    CheckForUpdates()
    
    -- Загрузка модулей (если есть)
    LoadModules()
    
    -- Загрузка основного скрипта
    local loaded = LoadScript()
    
    if loaded then
        print("\n══════════════════════════════════════")
        print(" CHRONOS AIMBOT успешно активирован! ")
        print("══════════════════════════════════════\n")
    else
        warn("\n❌ Не удалось загрузить CHRONOS AIMBOT")
        warn("Проверьте подключение к интернету")
        warn("Или сообщите о проблеме: " .. REPO_URL)
    end
end

-- Запускаем
Main()

return {
    Version = VERSION,
    Reload = LoadScript,
    Config = Config
}

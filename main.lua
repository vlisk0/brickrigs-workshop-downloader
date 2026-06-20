local resourceDir = system.pathForFile("", system.ResourceDirectory):gsub("\\", "/")
local steamcmdPath = resourceDir .. "/steamcmd/steamcmd.exe"
local f = io.open(steamcmdPath, "r")
if not f then
    steamcmdPath = resourceDir .. "/steamcmd.exe"
    f = io.open(steamcmdPath, "r")
end
local hasSteamcmd = (f ~= nil)
if f then f:close() end

local cacheDir = resourceDir .. "/workshop_cache"
local workshopContentDir = cacheDir .. "/steamapps/workshop/content/552100"
local brickRigsVehiclesDir = os.getenv("USERPROFILE") .. "\\AppData\\Local\\BrickRigs\\SavedRemastered\\Vehicles"

local widget = require("widget")

local textField, logText, downloadButton, isDownloading = nil, nil, nil, false

local metadataHex = [[
1011 0076 6568 6963 6c65 5f39 3336 3834
3039 3030 0000 110e 0040 4945 00c0 a344
0020 1445 5097 4b47 e0ed 3049 1d09 0765
6119 9544 9057 6800 0000 0080 2bad faea
cade 0840 8dcb 5eec cade 0802 044e 6f6e
6504 4e6f 6e65 044e 6f6e 65
]]

local function hexStringToBytes(hex)
    local cleaned = hex:gsub("%s+", "")
    local bytes = {}
    for i = 1, #cleaned, 2 do
        local byte = cleaned:sub(i, i+1)
        if #byte == 2 then
            table.insert(bytes, tonumber(byte, 16))
        end
    end
    return bytes
end

local metadataBytes = hexStringToBytes(metadataHex)

local function addLog(msg)
    if logText then
        logText.text = (logText.text or "") .. msg .. "\n"
        if logText.setSelection then
            logText:setSelection(#logText.text, #logText.text)
        end
    end
    print(msg)
end

local function ensureDirectories()
    os.execute('if not exist "' .. cacheDir .. '" mkdir "' .. cacheDir .. '"')
    os.execute('if not exist "' .. brickRigsVehiclesDir .. '" mkdir "' .. brickRigsVehiclesDir .. '"')
    os.execute('if not exist "' .. cacheDir .. '\\steamapps" mkdir "' .. cacheDir .. '\\steamapps"')
    addLog("Папки подготовлены")
end

local function runCommandAndLog(cmd)
    local tmpOut = cacheDir .. "/tmp_out.txt"
    local fullCmd = 'cmd.exe /c "' .. cmd .. '" > "' .. tmpOut .. '" 2>&1'
    os.execute(fullCmd)
    local file = io.open(tmpOut, "r")
    local content = file and file:read("*a") or ""
    if file then file:close() end
    if content and #content > 0 then
        addLog("--- ВЫВОД STEAMCMD ---")
        addLog(content)
        addLog("--- КОНЕЦ ВЫВОДА ---")
    end
    os.execute('del "' .. tmpOut .. '" 2>nul')
    return content
end

local function getFilesByExt(folder, ext)
    local tmpList = cacheDir .. "/tmp_list_ext.txt"
    local folderEscaped = folder:gsub("/", "\\")
    os.execute('dir /b "' .. folderEscaped .. '\\*' .. ext .. '" 2>nul > "' .. tmpList .. '"')
    local file = io.open(tmpList, "r")
    local files = {}
    if file then
        for line in file:lines() do
            table.insert(files, line)
        end
        file:close()
    end
    os.execute('del "' .. tmpList .. '" 2>nul')
    return files
end

local function createSteamScript(vehicleIds)
    local scriptPath = cacheDir .. "/download_script.txt"
    local file = io.open(scriptPath, "w")
    if not file then
        addLog("ОШИБКА: не удалось создать файл скрипта " .. scriptPath)
        return nil
    end
    file:write('force_install_dir "' .. cacheDir .. '"\n')
    file:write("login anonymous\n")
    for _, id in ipairs(vehicleIds) do
        file:write("workshop_download_item 552100 " .. id .. "\n")
    end
    file:write("quit\n")
    file:close()
    addLog("Скрипт создан: " .. scriptPath)
    return scriptPath
end

local function moveBrvFiles(vehicleIds)
    local movedCount = 0
    for _, id in ipairs(vehicleIds) do
        local srcFolder = workshopContentDir .. "/" .. id
        local srcFolderRaw = srcFolder:gsub("/", "\\")
        addLog("Проверяем папку: " .. srcFolderRaw)
        
        local brvFiles = getFilesByExt(srcFolderRaw, ".brv")
        if #brvFiles == 0 then
            addLog("Предупреждение: не найден .brv файл для ID " .. id)
        else
            local brvFile = brvFiles[1]
            local srcFile = srcFolderRaw .. "\\" .. brvFile
            
            local folderName = "vehicle_" .. id
            local targetFolder = brickRigsVehiclesDir .. "\\" .. folderName
            local targetBrv = targetFolder .. "\\vehicle.brv"
            local targetMeta = targetFolder .. "\\MetaData.brm"
            
            os.execute('mkdir "' .. targetFolder .. '" 2>nul')
            os.execute('copy /Y "' .. srcFile .. '" "' .. targetBrv .. '"')
            addLog("Скопировано: " .. srcFile .. " -> " .. targetBrv)
            
            local metaFile = io.open(targetMeta, "wb")
            if metaFile then
                local bytesToWrite = {}
                for _, b in ipairs(metadataBytes) do
                    table.insert(bytesToWrite, string.char(b))
                end
                metaFile:write(table.concat(bytesToWrite))
                metaFile:close()
                addLog("Создан MetaData.brm: " .. targetMeta)
            else
                addLog("ОШИБКА: не удалось создать MetaData.brm")
            end
            
            local imageFiles = {}
            local exts = { ".jpg", ".jpeg", ".png", ".bmp", ".tga" }
            for _, ext in ipairs(exts) do
                local files = getFilesByExt(srcFolderRaw, ext)
                for _, fname in ipairs(files) do
                    table.insert(imageFiles, fname)
                end
            end
            if #imageFiles > 0 then
                local srcImg = srcFolderRaw .. "\\" .. imageFiles[1]
                local targetImg = targetFolder .. "\\Preview.png"
                os.execute('copy /Y "' .. srcImg .. '" "' .. targetImg .. '"')
                addLog("Скопировано превью: " .. srcImg .. " -> " .. targetImg)
            else
                addLog("Превью не найдено в папке мастерской")
            end
            
            movedCount = movedCount + 1
        end
    end
    addLog("Готово. Обработано построек: " .. movedCount)
end

local function extractIds(input)
    local ids = {}
    if not input or input == "" then return ids end
    for token in string.gmatch(input, "[^%s,]+") do
        token = token:match("^%s*(.-)%s*$") or token
        local id = token:match("[?&]id=(%d+)")
        if id then
            table.insert(ids, id)
        else
            for num in string.gmatch(token, "%d+") do
                table.insert(ids, num)
            end
        end
    end
    return ids
end

local function startDownload(vehicleIds)
    if #vehicleIds == 0 then
        addLog("Нет ID для скачивания. Введите хотя бы один ID или ссылку.")
        return
    end
    
    isDownloading = true
    downloadButton:setEnabled(false)
    downloadButton.alpha = 0.5
    
    addLog("=== НАЧАЛО ЗАГРУЗКИ ===")
    addLog("ID: " .. table.concat(vehicleIds, ", "))
    
    if not hasSteamcmd then
        addLog("ОШИБКА: SteamCMD не найден по пути " .. steamcmdPath)
        addLog("Убедитесь, что steamcmd.exe лежит в папке проекта или в подпапке steamcmd")
        isDownloading = false
        downloadButton:setEnabled(true)
        downloadButton.alpha = 1
        return
    end
    
    local scriptPath = createSteamScript(vehicleIds)
    if not scriptPath then
        isDownloading = false
        downloadButton:setEnabled(true)
        downloadButton.alpha = 1
        return
    end
    
    addLog("Запуск SteamCMD...")
    local cmd = '"' .. steamcmdPath .. '" +runscript "' .. scriptPath .. '"'
    runCommandAndLog(cmd)
    addLog("SteamCMD завершил работу.")
    
    local function sleep(sec)
        local t = os.clock() + sec
        while os.clock() < t do end
    end
    sleep(2)
    
    addLog("Поиск и копирование .brv файлов...")
    moveBrvFiles(vehicleIds)
    
    addLog("=== ЗАГРУЗКА ЗАВЕРШЕНА ===")
    isDownloading = false
    downloadButton:setEnabled(true)
    downloadButton.alpha = 1
end

local function onDownloadTap(event)
    if event.phase == "began" then
        if isDownloading then
            addLog("Загрузка уже выполняется, подождите...")
            return
        end
        local ids = extractIds(textField.text)
        if #ids == 0 then
            addLog("Ошибка: не удалось извлечь ID из введённой строки.")
            return
        end
        startDownload(ids)
    end
    return true
end

local function initUI()
    local bg = display.newRect(display.contentCenterX, display.contentCenterY, display.contentWidth, display.contentHeight)
    bg:setFillColor(0.9, 0.9, 0.9)
    
    local title = display.newText({
        text = "Brick Rigs - Загрузчик построек (SteamCMD)",
        x = display.contentCenterX,
        y = 40,
        fontSize = 20,
        font = native.systemFontBold
    })
    title:setFillColor(0, 0, 0)
    
    local label = display.newText({
        text = "ID или ссылка",
        x = display.contentCenterX,
        y = 90,
        fontSize = 14,
        font = native.systemFont
    })
    label:setFillColor(0, 0, 0)
    local textFieldBg = display.newRoundedRect(display.contentCenterX, 130, 405, 45, 5)
    textFieldBg:setFillColor(1, 1, 1)
    textField = native.newTextField(display.contentCenterX, 130, 400, 40)
    textField.placeholder = ""
    textField.inputType = "default"

    downloadButton = widget.newButton({
        label = "СКАЧАТЬ",
        x = display.contentCenterX,
        y = 190,
        width = 200,
        height = 50,
        fontSize = 18,
        labelColor = { default = { 0, 0, 0 }, over = { 0.3, 0.3, 0.3 } },
        fillColor = { default = { 0.9, 0.9, 0.9 }, over = { 0.6, 0.6, 0.6 } },
        onEvent = onDownloadTap
    })
    
    local logBg = display.newRoundedRect(display.contentCenterX, display.contentHeight - 180, display.contentWidth - 40, 240, 5)
    logBg:setFillColor(1, 1, 1)
    
    logText = native.newTextBox(display.contentCenterX, display.contentHeight - 180, display.contentWidth - 50, 230)
    logText.text = "Готов к работе.\n"
    logText.isEditable = false
    logText:setTextColor(0, 0, 0)
    logText.size = 12
    
    local pathLabel = display.newText({
        text = "Путь к постройкам: " .. brickRigsVehiclesDir,
        x = display.contentCenterX,
        y = display.contentHeight - 20,
        fontSize = 11,
        font = native.systemFont
    })
    pathLabel:setFillColor(0, 0, 0)
    pathLabel.alpha = 0.5
    
    ensureDirectories()
    
    if hasSteamcmd then
        addLog("SteamCMD найден: " .. steamcmdPath)
    else
        addLog("ВНИМАНИЕ: SteamCMD не найден по пути " .. steamcmdPath)
        addLog("Поместите steamcmd.exe в папку с проектом (или в подпапку steamcmd).")
    end
    
    addLog("Папка с постройками: " .. brickRigsVehiclesDir)
    addLog("Кэш SteamCMD: " .. cacheDir)
end

initUI()
---@type Modules
local Modules = VFS.Include("LuaUI/TurboBarCam/modules.lua")
---@type LogBuilder
local LogBuilder = VFS.Include("LuaUI/TurboBarCommons/logger_prototype.lua")

---@class ModuleManager : ModuleAliases
local ModuleManager = WG.TurboBarCam.ModuleManager or {
    --- Stores the actual loaded Lua modules/classes.
    registry        = {},
    --- Stores metadata for registered files.
    -- Keyed by filePath, stores { filePath, currentHash, hooks = {} }
    registeredFiles = {},
    modulesRoot     = "LuaUI/TurboBarCam/",
    --- Used to detect circular dependencies during a load sequence.
    -- Stores fullModulePath strings.
    loadingStack    = {}
}

local Log = LogBuilder.createInstance("TurboBarCam", function()
    ---@type WidgetConfig
    local CONFIG = WG.TurboBarCam.CONFIG
    return CONFIG and CONFIG.DEBUG.LOG_LEVEL or "INFO"
end):appendPrefix("ModuleManager")

-- Helper function to get file content and calculate its hash
-- Returns fileContent, hash; or nil, nil if errors.
local function getFileContentAndHash(filePath)
    local fileContent = VFS.LoadFile(filePath)
    if not fileContent then
        Log:warn(string.format("getFileContentAndHash: Could not load content for file: %s", tostring(filePath)))
        return nil, nil -- Ensure nil is returned for hash too if content is nil
    end

    local hash = VFS.CalculateHash(fileContent, 0) -- 0 for MD5
    if not hash then
        Log:warn(string.format("getFileContentAndHash: Could not calculate hash for file: %s (content was read successfully, but hashing failed)", tostring(filePath)))
    end
    return fileContent, hash
end

--- Includes a module, stores it, and registers it for hot reloading.
-- Throws an error if a circular dependency is detected.
local function registerModule(modulePath, postLoadOrUpdateHook)
    if type(modulePath) ~= "string" or modulePath == "" then
        Log:error("registerModule: filePath must be a non-empty string.")
        return nil
    end
    local fullModulePath = ModuleManager.modulesRoot .. modulePath

    if type(postLoadOrUpdateHook) ~= "function" then
        Log:error(string.format("registerModule: postLoadOrUpdateHook for '%s' must be a function. Got type: %s", tostring(modulePath), type(postLoadOrUpdateHook)))
        return nil
    end

    -- Check for circular dependency
    for i, loadingPathInStack in ipairs(ModuleManager.loadingStack) do
        if loadingPathInStack == fullModulePath then
            local cycleTrace = table.concat(ModuleManager.loadingStack, "\n-> ") .. "\n-> " .. fullModulePath
            -- Throw an error, halting execution.
            -- The loadingStack will be cleared on the next widget re-initialization if this error is caught high up.
            Log:error(string.format("\n\nCircular dependency detected in %s\n\n", cycleTrace))
        end
    end

    local registrationData = ModuleManager.registeredFiles[fullModulePath]
    if registrationData then
        -- Module already fully loaded and registered in a previous, completed load sequence.
        -- This is NOT a circular dependency being detected at this point; it's a legitimate re-request.
        local moduleInstance = ModuleManager.registry[fullModulePath]
        table.insert(registrationData.hooks, postLoadOrUpdateHook)
        local configuredModule = postLoadOrUpdateHook(moduleInstance)
        return configuredModule or moduleInstance
    else
        -- New module registration attempt.
        table.insert(ModuleManager.loadingStack, fullModulePath)

        -- If VFS.Include errors, execution stops here. The error propagates.
        -- ModuleManager.loadingStack will still contain fullModulePath.
        -- This is acceptable if widget re-initialization clears the ModuleManager state.
        local loadedModule = VFS.Include(fullModulePath)

        -- This part is reached ONLY if VFS.Include did NOT error and halt execution.
        local removedPath = table.remove(ModuleManager.loadingStack)
        -- Basic sanity check for stack operations.
        if removedPath ~= fullModulePath then
            Log:error(string.format("ModuleManager: Internal consistency warning in loadingStack during removal. Expected '%s', got '%s'. Stack after removal: {%s}",
                    tostring(fullModulePath), tostring(removedPath), table.concat(ModuleManager.loadingStack, ", ")))
        end

        ModuleManager.registry[fullModulePath] = loadedModule
        local initialFileContent, initialHash = getFileContentAndHash(fullModulePath)
        if not initialFileContent then
            Log:warn(string.format("registerModule: Failed to get content/hash for '%s' after VFS.Include. Registration hash will be nil.", modulePath))
        end

        registrationData = {
            filePath    = fullModulePath,
            currentHash = initialHash, -- Will be nil if getFileContentAndHash failed
            hooks       = { postLoadOrUpdateHook }
        }
        ModuleManager.registeredFiles[fullModulePath] = registrationData

        if loadedModule == nil then
            Log:warn(string.format("registerModule: Module '%s' VFS.Include returned nil. Registration Hash: %s", modulePath, tostring(initialHash or "N/A")))
        end

        local configuredModule = postLoadOrUpdateHook(loadedModule)
        return configuredModule or loadedModule
    end
end

--- Checks all registered files for content changes and reloads them.
function ModuleManager.reloadChanged()
    Log:info("reloadChanged: Starting check for registered files...")
    local filesReloadedCount = 0
    local totalRegisteredFiles = 0
    for _ in pairs(ModuleManager.registeredFiles) do totalRegisteredFiles = totalRegisteredFiles + 1 end

    for path, data in pairs(ModuleManager.registeredFiles) do
        local processFile = true
        local currentFileContent, currentHash = getFileContentAndHash(path)

        if not currentFileContent then
            Log:warn(string.format("reloadChanged: Could not load content for '%s' to check for changes. Skipping this file for reload check.", path))
            processFile = false
        end

        if processFile and not currentHash and data.currentHash then
            Log:warn(string.format("reloadChanged: Could not compute current hash for '%s', but previous hash exists. Forcing reload.", path))
            currentHash = "__force_reload_due_to_hash_error__" .. Spring.GetTimer()
        elseif processFile and not currentHash and not data.currentHash then
            Log:error(string.format("reloadChanged: Hash computations failed for '%s' (current and initial). Cannot determine change, skipping.", path))
            processFile = false
        end

        if processFile then
            if data.currentHash ~= currentHash then
                Log:info(string.format("reloadChanged: File content hash changed for '%s'. OldHash: %s, NewHash: %s. Reloading...", path, tostring(data.currentHash or "N/A"), currentHash))

                -- If VFS.Include errors here, this reloadChanged function (or its caller) will halt.
                local reloadedModule = VFS.Include(data.filePath)
                local finalReloadedModule

                if reloadedModule ~= nil then
                    finalReloadedModule = reloadedModule
                    ModuleManager.registry[path] = finalReloadedModule
                    ModuleManager.registeredFiles[path].currentHash = currentHash
                    filesReloadedCount = filesReloadedCount + 1
                    Log:info(string.format("reloadChanged: Successfully reloaded '%s'.", path))
                else
                    Log:error(string.format("reloadChanged: Module '%s' VFS.Include returned nil during reload. Registry may hold old instance.", path))
                    finalReloadedModule = ModuleManager.registry[path] -- Fallback to whatever is in registry
                end

                if data.hooks then
                    Log:info(string.format("reloadChanged: Calling %d hooks for '%s' after attempting reload.", #data.hooks, path))
                    for i, hook in ipairs(data.hooks) do
                        -- If a hook errors here, this reloadChanged function (or its caller) will halt.
                        hook(finalReloadedModule)
                    end
                end
            end
        end
    end

    if filesReloadedCount > 0 then
        Log:info(string.format("reloadChanged: Finished. Reloaded %d changed file(s) out of %d registered files.", filesReloadedCount, totalRegisteredFiles))
    else
        Log:info(string.format("reloadChanged: Finished. No files changed (based on content hash) among %d registered files.", totalRegisteredFiles))
    end
end

--- Resets the ModuleManager's state, including the loading stack.
function ModuleManager.reset()
    Log:info("reset: Clearing all registered files, modules, and loading stack.")
    ModuleManager.registry = {}
    ModuleManager.registeredFiles = {}
    ModuleManager.loadingStack = {} -- Ensure loading stack is cleared on reset
end

-- Dynamically create alias functions for simple modules
for aliasName, relativePathInModulesFile in pairs(Modules.SimpleModules) do
    if type(aliasName) == "string" and type(relativePathInModulesFile) == "string" then
        if ModuleManager[aliasName] then
            Log:error(string.format("ModuleManager: Alias '%s' already exists on ModuleManager. ", aliasName))
        else
            ModuleManager[aliasName] = function(postLoadOrUpdateHook, data)
                if data then
                    Log:error(string.format("ModuleManager: Alias '%s' was called with additional data, but it is a simple module and does not support it.", aliasName))
                    return nil
                end
                if type(postLoadOrUpdateHook) ~= "function" then
                    Log:error(string.format("%s (alias): A valid function hook must be provided for path '%s'. Got hook type: %s.", aliasName, relativePathInModulesFile, type(postLoadOrUpdateHook)))
                    return nil
                end
                return registerModule(relativePathInModulesFile, postLoadOrUpdateHook)
            end
        end
    else
        Log:error(string.format("ModuleManager: Invalid entry in Modules table during alias creation. Alias: %s (type: %s), Path: %s (type: %s).",
                tostring(aliasName), type(aliasName), tostring(relativePathInModulesFile), type(relativePathInModulesFile)))
    end
end

-- Generic alias creation for Parametrised Modules
for aliasName, c in pairs(Modules.ParametrisedModules) do
    ---@type ParametrisedModuleConfig
    local config = c
    if ModuleManager[aliasName] then
        Log:error(string.format("ModuleManager: Alias '%s' from ParametrisedModules conflicts with an existing alias.", aliasName))
    else
        ModuleManager[aliasName] = function(postLoadOrUpdateHook, data)
            if type(postLoadOrUpdateHook) ~= "function" then
                Log:error(string.format("%s (alias): A valid function hook must be provided. Got type: %s.", aliasName, type(postLoadOrUpdateHook)))
                return nil
            end

            local wrapperHook = function(baseModule)
                local configuredModule = baseModule

                -- If a 'configure' function is defined, use it to process the data.
                if config.configure and type(config.configure) == 'function' then
                    configuredModule = config.configure(baseModule, data)
                elseif data then
                    Log:warn(string.format("ModuleManager: Alias '%s' was called with data, but no 'configure' function is defined for it in modules.lua.", aliasName))
                    return nil
                end
                postLoadOrUpdateHook(configuredModule)
                return configuredModule
            end
            return registerModule(config.path, wrapperHook)
        end
    end
end


return ModuleManager
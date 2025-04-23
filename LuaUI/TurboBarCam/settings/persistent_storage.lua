---@type Log
local Log = VFS.Include("LuaUI/TurboBarCam/common/log.lua").Log

---@class PersistentStorage
local PersistentStorage = {}
PersistentStorage.__index = PersistentStorage

--- Creates a new persistent storage instance
---@param name string Storage name
---@param isPersistent boolean Whether the storage should save to disk
---@param saveInterval number How often to save changes to disk (in seconds)
---@return PersistentStorage
function PersistentStorage.new(name, isPersistent, saveInterval)
    local obj = {
        name = name,
        filepath = isPersistent and "LuaUI/TurboBarCam/settings/storage/" .. name .. ".lua" or nil,
        data = {},
        isDirty = false,
        lastSaveTime = os.clock(),
        saveInterval = saveInterval or 5, -- Default to 5 seconds
        isInitialized = false,
        isPersistent = isPersistent or false
    }
    setmetatable(obj, PersistentStorage)
    obj:initialize()
    return obj
end

--- Initialize the persistent storage by loading from file
function PersistentStorage:initialize()
    if self.isInitialized then return end
    
    if self.isPersistent then
        self:load()
    end
    
    self.isInitialized = true
    self.isDirty = false
    
    if self.isPersistent then
        Log.debug("Initialized persistent storage: " .. self.filepath)
    else
        Log.debug("Initialized non-persistent storage: " .. self.name)
    end
end

--- Load data from file
function PersistentStorage:load()
    if not self.isPersistent then
        self.data = {}
        return self.data
    end
    
    local success, result
    success, result = pcall(function()
        return VFS.Include(self.filepath)
    end)

    if success and type(result) == "table" then
        self.data = result
        Log.debug("Loaded persistent storage from " .. self.filepath)
    else
        self.data = {}
        Log.debug("Created new persistent storage file: " .. self.filepath)
    end

    self.isDirty = false
    return self.data
end

--- Save data to file if needed
---@param force boolean Force save regardless of dirty status
function PersistentStorage:save(force)
    -- Skip saving for non-persistent storage
    if not self.isPersistent then
        self.isDirty = false
        self.lastSaveTime = os.clock()
        return
    end
    
    local currentTime = os.clock()
    
    -- Only save if dirty and enough time has passed, or forced
    if (not self.isDirty and not force) or 
       (not force and (currentTime - self.lastSaveTime) < self.saveInterval) then
        return
    end
    
    -- Convert data table to string with return statement
    local content = "return {\n"
    for key, value in pairs(self.data) do
        if type(value) == "table" then
            content = content .. string.format('  ["%s"] = {\n', key)
            for k, v in pairs(value) do
                if type(v) == "string" then
                    content = content .. string.format('    %s = "%s",\n', k, tostring(v))
                else
                    content = content .. string.format('    %s = %s,\n', k, tostring(v))
                end
            end
            content = content .. "  },\n"
        else
            if type(value) == "string" then
                content = content .. string.format('  ["%s"] = "%s",\n', key, tostring(value))
            else
                content = content .. string.format('  ["%s"] = %s,\n', key, tostring(value))
            end
        end
    end
    content = content .. "}"

    -- Save to file
    local file = io.open(self.filepath, "w")
    if file then
        file:write(content)
        file:close()
        self.isDirty = false
        self.lastSaveTime = currentTime
        Log.trace("Persistent storage saved to " .. self.filepath)
    else
        Log.error("Failed to save persistent storage to " .. self.filepath)
    end
end

--- Get a value from storage
---@param key string Key to retrieve
---@return any value
function PersistentStorage:get(key)
    return self.data[key]
end

--- Set a value in storage
---@param key string Key to set
---@param value any Value to store
function PersistentStorage:set(key, value)
    self.data[key] = value
    self.isDirty = true
end

--- Update data periodically
---@param dt number Delta time
function PersistentStorage:update(dt)
    if self.isPersistent and self.isDirty and (os.clock() - self.lastSaveTime) >= self.saveInterval then
        self:save()
    end
end

--- Close storage and save any pending changes
function PersistentStorage:close()
    if self.isPersistent and self.isDirty then
        self:save(true)
    end
end

--- Clear all data
function PersistentStorage:clear()
    self.data = {}
    self.isDirty = true
    if self.isPersistent then
        self:save(true)
    end
end

return PersistentStorage
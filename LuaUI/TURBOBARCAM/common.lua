---@type {Util: Util}
local UtilsModule = VFS.Include("LuaUI/TURBOBARCAM/common/utils.lua")
---@type {TrackingManager: TrackingManager}
local TrackingModule = VFS.Include("LuaUI/TURBOBARCAM/common/tracking.lua")
---@type {ClusterMathUtils: ClusterMathUtils}
local ClusterMathUtils = VFS.Include("LuaUI/TURBOBARCAM/common/cluster_math_utils.lua")
---@type {DBSCAN: DBSCAN}
local DBSCAN = VFS.Include("LuaUI/TURBOBARCAM/common/dbscan.lua")

---@return CommonModules
return {
    Util = UtilsModule.Util,
    Tracking = TrackingModule.TrackingManager,
    ClusterMathUtils = ClusterMathUtils.ClusterMathUtils,
    DBSCAN = DBSCAN.DBSCAN,
}
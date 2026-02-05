function widget:GetInfo()
    return {
        name      = "Replay filename",
        desc      = "Keeps the replay filename",
        author    = "SuperKitowiec",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = -9999,
        enabled   = true
    }
end


function widget:Initialize()
    WG.ReplayMetadata = {}
end

function widget:AddConsoleLine(msg)
    if Spring.IsReplay() and string.find(msg, "Opening demofile") then
        replayFilename = msg:match("([^\\/]+)%.sdfz$")
        WG.ReplayMetadata.filename = replayFilename
        Spring.Echo("Replay filename saved", replayFilename)
    end
end

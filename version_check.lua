-- =====================================================================
--  Distortionz Version Checker
--  Reads from Config.VersionCheck (see config.lua)
-- =====================================================================

local function TrimVersion(version)
    if not version then return '0.0.0' end
    return (tostring(version):gsub('^[vV]', ''))
end

local function SplitVersion(version)
    local parts = {}
    for part in TrimVersion(version):gmatch('[^.]+') do
        parts[#parts + 1] = tonumber(part) or 0
    end
    return parts
end

local function IsVersionNewer(remote, current)
    local r, c = SplitVersion(remote), SplitVersion(current)
    for i = 1, math.max(#r, #c) do
        local rp, cp = r[i] or 0, c[i] or 0
        if rp ~= cp then return rp > cp end
    end
    return false
end

local RESOURCE_NAME = GetCurrentResourceName()
local PREFIX = ('^5[%s]^7'):format(RESOURCE_NAME)

local function Log(color, msg, ...)
    print(('%s %s%s^7'):format(PREFIX, color, msg:format(...)))
end

local function LogBanner(currentVersion, latestVersion, changelog, download)
    print(('%s ^1============================================================^7'):format(PREFIX))
    Log('^1', 'Outdated version detected!  Current: ^1v%s^7 → Latest: ^2v%s',
        TrimVersion(currentVersion), TrimVersion(latestVersion))
    Log('^3', 'Changelog:^7 %s', changelog)
    Log('^5', 'Download:^7  %s', download)
    print(('%s ^1============================================================^7'):format(PREFIX))
end

local function VersionCheck()
    if not Config or not Config.VersionCheck or not Config.VersionCheck.enabled then
        return
    end

    local versionUrl = Config.VersionCheck.url
    if not versionUrl or versionUrl == '' then
        Log('^1', 'Version check failed: missing version URL in config.')
        return
    end

    local currentVersion = Config.CurrentVersion
        or GetResourceMetadata(RESOURCE_NAME, 'version', 0)
        or '0.0.0'

    PerformHttpRequest(versionUrl, function(statusCode, response, _)
        if statusCode ~= 200 then
            Log('^1', 'Version check failed. HTTP %s — URL: %s',
                tostring(statusCode or 'unknown'), versionUrl)
            return
        end

        if not response or response == '' then
            Log('^1', 'Version check failed: empty response body.')
            return
        end

        if response:sub(1, 1) == '<' then
            Log('^1', 'Version check failed: got HTML, not JSON.')
            Log('^3', 'Tip: use a raw.githubusercontent.com URL, not github.com/blob.')
            return
        end

        local success, data = pcall(json.decode, response)
        if not success or type(data) ~= 'table' then
            Log('^1', 'Version check failed: invalid JSON response.')
            return
        end

        local latestVersion = data.version or data.latest or '0.0.0'
        local changelog     = data.changelog or 'No changelog provided.'
        local download      = data.download  or 'No download URL provided.'

        if IsVersionNewer(latestVersion, currentVersion) then
            LogBanner(currentVersion, latestVersion, changelog, download)
        else
            Log('^2', 'You are running the latest version. v%s', TrimVersion(currentVersion))
        end
    end, 'GET', '', {
        ['User-Agent'] = ('Distortionz/%s'):format(RESOURCE_NAME),
        ['Accept']     = 'application/json',
    })
end

CreateThread(function()
    Wait(2500)
    if Config and Config.VersionCheck and Config.VersionCheck.checkOnStart then
        VersionCheck()
    end
end)

exports('CheckVersion', VersionCheck)

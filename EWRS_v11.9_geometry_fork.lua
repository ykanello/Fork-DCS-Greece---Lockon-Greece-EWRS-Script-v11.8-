--=====================================================
-- DCS Greece - Lockon Greece EWRS Script v11.9-geometry-fork 
--=====================================================

env.info("EWRS: Starting Early Warning Radar System")

if not mist then
    trigger.action.outText("ERROR: MIST NOT LOADED! EWRS requires MIST.", 30)
    return
end

Config = Config or {}
Config.EWRS = {
    enable = true,
    
    -- ===== MESSAGE TIMING CONFIGURATION =====
    refresh_time = 45,                    -- How often reports appear (in seconds)
    message_display_duration = 20,        -- How long messages stay on screen (in seconds)
    radar_cache_refresh_time = 180,       -- How often to refresh radar cache (in seconds)
    -- ========================================
    
    default_max_contacts = 6,
    
    default_radius_nm = 100,
    auto_enable_on_spawn = true,
    
    friendly_picture_enable = true,
    default_friendly_max_contacts = 4,
    friendly_default_radius_nm = 30,
    
    enable_training_mode = true,
    
    -- SPEED REPORTING CONFIGURATION
    enable_speed_reporting = false,
    speed_report_units_blue = "KNOTS",    -- "KNOTS" or "KMH"
    speed_report_units_red  = "KMH",
    
    -- UNITS - REFERENCE REPORTING CONFIGURATION
    default_units_blue = "IMPERIAL",   -- "IMPERIAL" or "METRIC"
    default_units_red  = "METRIC",
    default_reference_blue = "BULLSEYE",    -- "OWN" or "BULLSEYE"
    default_reference_red  = "OWN",

    enemy_range_options = {30, 60, 80, 120, 180},
    friendly_range_options = {30, 60, 80, 120, 160},
    
    enemy_contact_options = {2, 4, 6, 8},
    friendly_contact_options = {2, 4, 6, 8},
    
    friendly_use_player_names = true,
    
    radar_types = {
        SAM_SR = true,
        SAM_TR = true,
        EWR = true,
        AWACS = true,
        AEW = true,
        Ships = true,
        Fighter = false,
        Bomber = false,
    },
    
    only_armed_ships = true,

    -- ===== RADAR GEOMETRY / ELEVATION FILTER =====
    -- This layer makes EWRS radar-type aware.
    -- Unprofiled radars keep the original EWRS behavior by default.
    -- To make the filter stricter, set default_policy = "BLOCK" and define default_profile.
    radar_geometry = {
        enable = true,
        log_rejections = false,
        log_accepts = false,

        -- "ALLOW" = radars without a profile behave normally.
        -- "BLOCK" = radars without a profile are ignored unless default_profile is defined.
        default_policy = "ALLOW",

        -- Approximation notes:
        -- 1. DCS altitude is MSL, not AGL.
        -- 2. This does not model terrain masking between radar and target.
        -- 3. The curvature model uses the common radar-horizon approximation.
        -- 4. Values are gameplay-tunable profiles, not a certified technical manual.
        profiles_by_type = {
            -- 55G6 Tall Rack / Nebo-style 3D EWR profile.
            -- Good strategic picture, poor low-altitude far picture.
            ["55G6 EWR"] = {
                name = "55G6 Tall Rack / Nebo EWR",
                maxRangeNm = 150,
                minElevationDeg = 2,
                maxElevationDeg = 16,
                antennaHeightM = 10,
                useRadarHorizon = true,
            },
        },

        -- Fallback substring matching helps if DCS / map / mod type names vary slightly.
        profiles_by_substring = {
            {
                match = "55G6",
                profile = {
                    name = "55G6 Tall Rack / Nebo EWR",
                    maxRangeNm = 150,
                    minElevationDeg = 2,
                    maxElevationDeg = 16,
                    antennaHeightM = 10,
                    useRadarHorizon = true,
                }
            },
        },

        -- Example for later expansion:
        -- profiles_by_type["p-19 s-125 sr"] = {
        --     name = "P-19 Flat Face",
        --     maxRangeNm = 50,
        --     minElevationDeg = 0.5,
        --     maxElevationDeg = 30,
        --     antennaHeightM = 8,
        --     useRadarHorizon = true,
        -- }
    },
}

-----------------------------------------------------
-- HELPER FUNCTION: Pad string with spaces for alignment
-----------------------------------------------------
local function padToWidth(str, width)
    local len = string.len(str)
    if len >= width then
        return str
    end
    return str .. string.rep(" ", width - len)
end

-----------------------------------------------------
-- HELPER FUNCTION: Format bearing (NO O'CLOCK)
-----------------------------------------------------
local function formatBearing(user_point, target_point)
    local dx = target_point.x - user_point.x
    local dz = target_point.z - user_point.z
    local bearing = (math.deg(math.atan2(dx, dz)) + 360) % 360
    return string.format("%03d", math.floor(bearing))
end

-----------------------------------------------------
-- HELPER FUNCTION: Check if unit is airborne radar (AWACS/AEW)
-----------------------------------------------------
local function isAirborneRadar(unit)
    local desc = unit:getDesc()
    local isAirborne = (desc.category == Unit.Category.AIRPLANE) or (desc.category == Unit.Category.HELICOPTER)
    
    if not isAirborne then
        return false
    end
    
    if unit:hasAttribute("AWACS") or unit:hasAttribute("AEW") then
        return true
    end
    
    return false
end

-----------------------------------------------------
-- HELPER FUNCTION: Format speed based on configuration
-----------------------------------------------------
local function formatSpeed(velocity, units_type, speed_report_units)
    if not Config.EWRS.enable_speed_reporting then
        return "", ""
    end
    
    local speed_mps = mist.vec.mag(velocity)
    local speed_display
    
    if units_type == "METRIC" then
        if speed_report_units == "KMH" or speed_report_units == "METRIC" then
            speed_display = math.floor(mist.utils.mpsToKnots(speed_mps) * 1.852)
            return speed_display, "km/h"
        else
            speed_display = math.floor(mist.utils.mpsToKnots(speed_mps))
            return speed_display, "kts"
        end
    else
        speed_display = math.floor(mist.utils.mpsToKnots(speed_mps))
        return speed_display, "kts"
    end
end

-----------------------------------------------------
-- RADAR GEOMETRY / ELEVATION FILTER HELPERS
-----------------------------------------------------
local EWRS_GEOM = {
    NM_TO_M = 1852,
    M_TO_FT = 3.28084,
    NM_TO_FT = 6076.12,
}

local function geomDegToRad(deg)
    return deg * math.pi / 180
end

local function geomHorizontalRangeM(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- Common radar-horizon approximation:
-- range_nm = 1.23 * (sqrt(radar_alt_ft) + sqrt(target_alt_ft))
-- This returns the minimum target altitude MSL required by curvature alone.
local function geomRadarHorizonMinTargetFt(rangeNm, radarAltFt)
    local term = (rangeNm / 1.23) - math.sqrt(math.max(radarAltFt, 0))

    if term <= 0 then
        return 0
    end

    return term * term
end

local function geomGetUnitType(unit)
    local ok, unitType = pcall(function() return unit:getTypeName() end)
    if ok and unitType then
        return unitType
    end
    return "UNKNOWN"
end

local function geomGetRadarProfile(radar)
    local cfg = Config.EWRS.radar_geometry

    if not cfg or not cfg.enable then
        return nil, "GEOMETRY_DISABLED"
    end

    local unitType = geomGetUnitType(radar)

    if cfg.profiles_by_type and cfg.profiles_by_type[unitType] then
        return cfg.profiles_by_type[unitType], unitType
    end

    if cfg.profiles_by_substring then
        for _, rule in ipairs(cfg.profiles_by_substring) do
            if rule.match and rule.profile and string.find(unitType, rule.match, 1, true) then
                return rule.profile, rule.match
            end
        end
    end

    if cfg.default_policy == "BLOCK" and cfg.default_profile then
        return cfg.default_profile, "DEFAULT"
    end

    return nil, "UNPROFILED_ALLOWED"
end

local function geomLogReject(radar, targetObj, reason)
    local cfg = Config.EWRS.radar_geometry
    if cfg and cfg.log_rejections then
        env.info("EWRS GEOM: reject radar=" .. geomGetUnitType(radar) ..
                 " target=" .. (targetObj and targetObj:getName() or "UNKNOWN") ..
                 " reason=" .. tostring(reason))
    end
end

local function geomLogAccept(radar, targetObj, profileName)
    local cfg = Config.EWRS.radar_geometry
    if cfg and cfg.log_accepts then
        env.info("EWRS GEOM: accept radar=" .. geomGetUnitType(radar) ..
                 " target=" .. (targetObj and targetObj:getName() or "UNKNOWN") ..
                 " profile=" .. tostring(profileName))
    end
end

-----------------------------------------------------
-- EWRS CLASS
-----------------------------------------------------
EWRS = {}
EWRS.__index = EWRS

function EWRS:new(side)
    local o = setmetatable({}, self)
    o.side = side
    o.enemy = (side == coalition.side.BLUE) and coalition.side.RED or coalition.side.BLUE
    o.refresh_time = Config.EWRS.refresh_time
    o.users = {}
    o.radars = {}
    o.picture = {}
    o.bullseye = nil
    o.menuAdded = {}
    env.info("EWRS: Created for side " .. tostring(side))
    o:cacheRadars()
    o:startSearch()
    return o
end

-----------------------------------------------------
-- Radar Geometry Filter
-----------------------------------------------------
function EWRS:radarCanSeeTarget(radar, targetObj)
    local cfg = Config.EWRS.radar_geometry

    if not cfg or not cfg.enable then
        return true
    end

    if not radar or not radar:isExist() or not targetObj or not targetObj:isExist() then
        return false
    end

    local profile, profileKey = geomGetRadarProfile(radar)

    -- Original EWRS behavior for radars without a profile.
    if not profile then
        if cfg.default_policy == "BLOCK" then
            geomLogReject(radar, targetObj, "unprofiled radar blocked")
            return false
        end
        return true
    end

    local okRadar, radarPoint = pcall(function() return radar:getPoint() end)
    local okTarget, targetPoint = pcall(function() return targetObj:getPoint() end)

    if not okRadar or not radarPoint or not okTarget or not targetPoint then
        geomLogReject(radar, targetObj, "missing point")
        return false
    end

    local rangeM = geomHorizontalRangeM(radarPoint, targetPoint)
    local rangeNm = rangeM / EWRS_GEOM.NM_TO_M

    if profile.maxRangeNm and rangeNm > profile.maxRangeNm then
        geomLogReject(radar, targetObj, string.format("range %.1f nm > %.1f nm", rangeNm, profile.maxRangeNm))
        return false
    end

    local antennaHeightM = profile.antennaHeightM or 0
    local radarAltFt = (radarPoint.y + antennaHeightM) * EWRS_GEOM.M_TO_FT
    local targetAltFt = targetPoint.y * EWRS_GEOM.M_TO_FT
    local rangeFt = rangeNm * EWRS_GEOM.NM_TO_FT

    local horizonMinFt = 0
    if profile.useRadarHorizon ~= false then
        horizonMinFt = geomRadarHorizonMinTargetFt(rangeNm, radarAltFt)
    end

    local minAltitudeFt = horizonMinFt
    if profile.minElevationDeg then
        minAltitudeFt = minAltitudeFt + math.tan(geomDegToRad(profile.minElevationDeg)) * rangeFt
    end

    local maxAltitudeFt = math.huge
    if profile.maxElevationDeg then
        maxAltitudeFt = horizonMinFt + math.tan(geomDegToRad(profile.maxElevationDeg)) * rangeFt
    end

    if targetAltFt < minAltitudeFt then
        geomLogReject(radar, targetObj,
            string.format("alt %.0f ft < min %.0f ft at %.1f nm", targetAltFt, minAltitudeFt, rangeNm))
        return false
    end

    if targetAltFt > maxAltitudeFt then
        geomLogReject(radar, targetObj,
            string.format("alt %.0f ft > max %.0f ft at %.1f nm", targetAltFt, maxAltitudeFt, rangeNm))
        return false
    end

    geomLogAccept(radar, targetObj, profile.name or profileKey)
    return true
end

-----------------------------------------------------
-- Radar Cache
-----------------------------------------------------
function EWRS:cacheRadars()
    self.radars = {}
    env.info("EWRS: Starting radar cache for side " .. tostring(self.side))
    
    for _, coalition_id in ipairs({coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL}) do
        local groups = coalition.getGroups(coalition_id)
        
        for _, group in ipairs(groups) do
            local units = group:getUnits()
            
            for _, unit in ipairs(units) do
                if unit and unit:isExist() then
                    local unitName = unit:getName()
                    local unitType = unit:getTypeName()
                    local isRadar = false
                    
                    if Config.EWRS.radar_types.SAM_SR and unit:hasAttribute("SAM SR") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.SAM_TR and unit:hasAttribute("SAM TR") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.EWR and unit:hasAttribute("EWR") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.AWACS and unit:hasAttribute("AWACS") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.AEW and unit:hasAttribute("AEW") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.Fighter and unit:hasAttribute("Fighters") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.Bomber and unit:hasAttribute("Bombers") then
                        isRadar = true
                    elseif Config.EWRS.radar_types.Ships and unit:hasAttribute("Ships") then
                        if Config.EWRS.only_armed_ships then
                            if unit:hasAttribute("Armed ships") 
                            or unit:hasAttribute("Heavy armed ships")
                            or unit:hasAttribute("Aircraft Carriers") then
                                isRadar = true
                            end
                        else
                            isRadar = true
                        end
                    end
                    
                    if isRadar then
                        table.insert(self.radars, unit)
                        env.info("EWRS: Added radar: " .. unitName .. " (" .. unitType .. ")")
                    end
                end
            end
        end
    end
    
    env.info("EWRS: Total radars: " .. #self.radars)
end

-----------------------------------------------------
-- Radar Detection
-----------------------------------------------------
function EWRS:detectRadarContacts()
    local contacts = {}
    local detected_units = {}
    local cached_radars = {}
    local active_count = 0
    
    env.info("EWRS: Starting detection with " .. #self.radars .. " cached radars")
    
    for _, radar in ipairs(self.radars) do
        if radar and radar:isExist() then
            -- Keep inactive radars cached. This matters when external scripts cycle
            -- radar emission ON/OFF; otherwise EWRS would forget them until cache refresh.
            cached_radars[#cached_radars + 1] = radar
            
            if radar:isActive() then
                active_count = active_count + 1
                
                local controller = radar:getController()
                if controller then
                    local detected = controller:getDetectedTargets()
                    
                    if detected then
                        for _, target in ipairs(detected) do
                            if target and target.object and target.object:isExist() then
                                local targetObj = target.object
                                
                                if self:radarCanSeeTarget(radar, targetObj) then
                                    local targetName = targetObj:getName()
                                    
                                    if not detected_units[targetName] then
                                        detected_units[targetName] = true
                                        table.insert(contacts, targetObj)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    self.radars = cached_radars
    
    env.info("EWRS: Active radars: " .. active_count .. " / cached radars after cleanup: " .. #self.radars)
    env.info("EWRS: Detected " .. #contacts .. " contacts")
    return contacts
end

-----------------------------------------------------
-- Detect Which Radars Are Detecting Player
-----------------------------------------------------
function EWRS:detectRadarsTrackingPlayer(player_unit)
    if not player_unit or not player_unit:isExist() then
        return {}
    end
    
    local player_name = player_unit:getName()
    local tracking_radars = {}
    
    for _, radar in ipairs(self.radars) do
        if radar and radar:isExist() and radar:isActive() then
            if radar:getCoalition() == self.enemy then
                local controller = radar:getController()
                if controller then
                    local detected = controller:getDetectedTargets()
                    
                    if detected then
                        for _, target in ipairs(detected) do
                            if target and target.object and target.object:isExist() then
                                local targetObj = target.object
                                if targetObj:getName() == player_name and self:radarCanSeeTarget(radar, targetObj) then
                                    table.insert(tracking_radars, radar)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return tracking_radars
end
-----------------------------------------------------
-- Search Theatre
-----------------------------------------------------
function EWRS:searchTheatre()
    self.picture = {}
    local contacts = self:detectRadarContacts()
    local enemyCount = 0
    
    for _, target in ipairs(contacts) do
        if target:getCoalition() == self.enemy then
            local targetName = target:getName()
            self.picture[targetName] = target
            enemyCount = enemyCount + 1
        end
    end
    
    env.info("EWRS: Added " .. enemyCount .. " enemies to picture")
end

-----------------------------------------------------
-- Target Aspect Calculation
-----------------------------------------------------
function EWRS:aspect(user_point, target_point, velocity)
    if not velocity then return "UNKNOWN" end
    
    local dx = user_point.x - target_point.x
    local dz = user_point.z - target_point.z
    local bearing_target_to_user = math.deg(math.atan2(dx, dz)) % 360
    
    local target_heading = math.deg(math.atan2(velocity.x, velocity.z)) % 360
    local target_tail = (target_heading + 180) % 360
    local angle_diff = math.abs(bearing_target_to_user - target_tail)
    local aspect_angle = math.min(angle_diff, 360 - angle_diff)
    
    if aspect_angle <= 45 then
        return "LOW ASPECT"
    elseif aspect_angle <= 90 then
        return "MEDIUM ASPECT"
    else
        return "HIGH ASPECT"
    end
end

-----------------------------------------------------
-- Display For Users
-----------------------------------------------------
function EWRS:displayForUsers()
    local userCount = 0
    for _ in pairs(self.users) do
        userCount = userCount + 1
    end
    env.info("EWRS: Displaying for " .. tostring(userCount) .. " users")
    
    -- Clean up dead users first (pcall-guarded)
    local dead_users = {}
    for name, data in pairs(self.users) do
        local ok, exists = pcall(function() return data.unit and data.unit:isExist() end)
        if not ok or not exists then
            table.insert(dead_users, name)
        end
    end
    
    for _, name in ipairs(dead_users) do
        env.info("EWRS: Removing dead user: " .. name)
        self.users[name] = nil
    end
    
    for name, data in pairs(self.users) do
        if data.unit and data.unit:isExist() then
            if data.training_mode then
                self:displayTrainingModeForUser(name, data)
            else
                self:displayNormalModeForUser(name, data)
            end
        end
    end
end

-----------------------------------------------------
-- Display Normal Mode
-----------------------------------------------------
function EWRS:displayNormalModeForUser(name, data)
    local nearby_units = {}
    local user_point = data.unit:getPoint()

    for target_name, target in pairs(self.picture) do
        if target and target:isExist() then
            local desc = target:getDesc()
            local isHelo = desc.category == Unit.Category.HELICOPTER
            local isAircraft = desc.category == Unit.Category.AIRPLANE
            
            local isExcludedRadarUnit = false
            
            if target:hasAttribute("SAM SR") or 
               target:hasAttribute("SAM TR") or 
               target:hasAttribute("EWR") or
               target:hasAttribute("Ships") then
                isExcludedRadarUnit = true
            end
            
            if isAirborneRadar(target) then
                isExcludedRadarUnit = false
            end
            
            if (isHelo or isAircraft) and not isExcludedRadarUnit then
                if (not isHelo) or data.include_helos then
                    local target_point = target:getPoint()
                    local range = mist.utils.get2DDist(user_point, target_point)

                    if range <= data.enemy_view_radius then
                        local ownBearing = (math.deg(math.atan2(target_point.z - user_point.z, target_point.x - user_point.x)) + 360) % 360
                        local bullBearing = nil
                        
                        if self.bullseye then
                            local dx = target_point.x - self.bullseye.x
                            local dz = target_point.z - self.bullseye.z
                            bullBearing = (math.deg(math.atan2(dz, dx)) + 360) % 360
                        end
                        
                        local aspect = self:aspect(user_point, target_point, target:getVelocity())
                        
                        table.insert(nearby_units, {
                            type = desc.typeName,
                            alt = target_point.y,
                            range = range,
                            velocity = target:getVelocity(),
                            aspect = aspect,
                            ownBearing = ownBearing,
                            bullBearing = bullBearing,
                            bullRange = self.bullseye and mist.utils.get2DDist(self.bullseye, target_point) or nil
                        })
                    end
                end
            end
        end
    end

    if #nearby_units > 0 then
        table.sort(nearby_units, function(a, b) return a.range < b.range end)
        
        local units_type = data.units or "IMPERIAL"
        
        local display_radius
        if units_type == "METRIC" then
            display_radius = math.floor(data.enemy_view_radius / 1000)
        else
            display_radius = math.floor(mist.utils.metersToNM(data.enemy_view_radius))
        end
        
        local helo_status = data.include_helos and "WITH HELO" or "W/O HELO"
        local ref_type = (data.reference == "BULLSEYE") and "BE" or "BRAA"
        local user_max_contacts = data.max_contacts or Config.EWRS.default_max_contacts
        
        local player_name = data.unit:getPlayerName()
        local player_header = player_name and (" - " .. player_name) or ""
        
        local report = string.format("ENEMY PICTURE%s: %d%s - %d contacts - %s - %s - %s\n\n", 
            player_header,
            display_radius,
            units_type == "METRIC" and "km" or "nm",
            user_max_contacts,
            ref_type,
            helo_status,
            units_type
        )

        local maxTypeLen = 0
        local maxBearingLen = 0
        for i = 1, math.min(#nearby_units, user_max_contacts) do
            if string.len(nearby_units[i].type) > maxTypeLen then
                maxTypeLen = string.len(nearby_units[i].type)
            end
            
            local t = nearby_units[i]
            local target_point = {
                x = user_point.x + math.sin(math.rad(t.ownBearing)) * t.range,
                z = user_point.z + math.cos(math.rad(t.ownBearing)) * t.range
            }
            local formattedBearing = formatBearing(user_point, target_point)
            
            if string.len(formattedBearing) > maxBearingLen then
                maxBearingLen = string.len(formattedBearing)
            end
        end
        maxTypeLen = maxTypeLen + 3
        maxBearingLen = maxBearingLen + 1

        for i = 1, math.min(#nearby_units, user_max_contacts) do
            local t = nearby_units[i]
            
            local alt_str
            if units_type == "METRIC" then
                if t.alt >= 1000 then
                    local alt_thousands = math.floor(t.alt / 1000)
                    alt_str = string.format("%dK m", alt_thousands)
                else
                    alt_str = string.format("%d m", math.floor(t.alt))
                end
            else
                if t.alt >= 304.8 then
                    local alt_thousands = math.floor(mist.utils.metersToFeet(t.alt) / 1000)
                    alt_str = string.format("%dK", alt_thousands)
                else
                    alt_str = string.format("%dft", math.floor(mist.utils.metersToFeet(t.alt)))
                end
            end
            
            local range_display
            if units_type == "METRIC" then
                if data.reference == "BULLSEYE" and t.bullRange then
                    range_display = math.floor(t.bullRange / 1000)
                else
                    range_display = math.floor(t.range / 1000)
                end
            else
                if data.reference == "BULLSEYE" and t.bullRange then
                    range_display = math.floor(mist.utils.metersToNM(t.bullRange))
                else
                    range_display = math.floor(mist.utils.metersToNM(t.range))
                end
            end
            
            local bearingStr
            local target_point = {
                x = user_point.x + math.sin(math.rad(t.ownBearing)) * t.range,
                z = user_point.z + math.cos(math.rad(t.ownBearing)) * t.range
            }
            
            if data.reference == "BULLSEYE" and t.bullBearing then
                bearingStr = string.format("%03d", math.floor(t.bullBearing))
            else
                bearingStr = formatBearing(user_point, target_point)
            end
            
            bearingStr = string.format("%-" .. maxBearingLen .. "s", bearingStr)
            
            local speed_display, speed_unit = formatSpeed(t.velocity, units_type, 
            (self.side == coalition.side.BLUE) and Config.EWRS.speed_report_units_blue or Config.EWRS.speed_report_units_red)
            local paddedType = padToWidth(t.type, maxTypeLen)
            
            if Config.EWRS.enable_speed_reporting then
                if units_type == "METRIC" then
                    report = report .. string.format("%s%s / %3d km / %5s / %3d %s / %s\n", 
                        paddedType, bearingStr, range_display, alt_str, speed_display, speed_unit, t.aspect)
                else
                    report = report .. string.format("%s%s / %3d nm / %5s / %3d %s / %s\n", 
                        paddedType, bearingStr, range_display, alt_str, speed_display, speed_unit, t.aspect)
                end
            else
                if units_type == "METRIC" then
                    report = report .. string.format("%s%s / %3d km / %5s / %s\n", 
                        paddedType, bearingStr, range_display, alt_str, t.aspect)
                else
                    report = report .. string.format("%s%s / %3d nm / %5s / %s\n", 
                        paddedType, bearingStr, range_display, alt_str, t.aspect)
                end
            end
        end

        trigger.action.outTextForUnit(data.unit:getID(), report, Config.EWRS.message_display_duration)
    end
end

-----------------------------------------------------
-- Display Training Mode
-----------------------------------------------------
function EWRS:displayTrainingModeForUser(name, data)
    env.info("EWRS: Displaying training mode for user " .. name)
    
    local threats = {}
    local user_point = data.unit:getPoint()
    local user_unit = data.unit
    
    local tracking_radars = self:detectRadarsTrackingPlayer(user_unit)
    
    for _, radar in ipairs(tracking_radars) do
        if radar and radar:isExist() then
            local radar_point = radar:getPoint()
            local range = mist.utils.get2DDist(user_point, radar_point)
            
            local radar_to_player_bearing = (math.deg(math.atan2(user_point.z - radar_point.z, user_point.x - radar_point.x)) + 360) % 360
            local player_bearing_to_radar = (radar_to_player_bearing + 180) % 360
            local exact_type = radar:getTypeName()
            
            table.insert(threats, {
                type = exact_type,
                range = range,
                bearing = player_bearing_to_radar
            })
        end
    end
    
    if #threats > 0 then
        table.sort(threats, function(a, b) return a.range < b.range end)
        
        local player_name = user_unit:getPlayerName()
        local player_header = player_name and (" - " .. player_name) or ""
        local units_type = data.units or "IMPERIAL"
        local max_contacts = data.max_contacts or Config.EWRS.default_max_contacts
        
        local report = "TRAINING MODE" .. player_header .. " - " .. units_type .. ":\n\n"
        
        local displayThreats = {}
        for i = 1, math.min(#threats, max_contacts) do
            table.insert(displayThreats, threats[i])
        end
        
        local maxTypeLen = 0
        for _, t in ipairs(displayThreats) do
            if string.len(t.type) > maxTypeLen then
                maxTypeLen = string.len(t.type)
            end
        end
        maxTypeLen = maxTypeLen + 3
        
        for _, t in ipairs(displayThreats) do
            local range_display
            if units_type == "METRIC" then
                range_display = math.floor(t.range / 1000)
            else
                range_display = math.floor(mist.utils.metersToNM(t.range))
            end
            
            local bearing_deg = math.floor(t.bearing)
            local paddedType = padToWidth(t.type, maxTypeLen)
            
            if units_type == "METRIC" then
                report = report .. string.format("%s%03d / %3d km\n", paddedType, bearing_deg, range_display)
            else
                report = report .. string.format("%s%03d / %3d nm\n", paddedType, bearing_deg, range_display)
            end
        end
        
        trigger.action.outTextForUnit(user_unit:getID(), report, Config.EWRS.message_display_duration)
    else
        local player_name = user_unit:getPlayerName()
        local player_header = player_name and (" - " .. player_name) or ""
        local units_type = data.units or "IMPERIAL"
        
        trigger.action.outTextForUnit(user_unit:getID(), 
            "TRAINING MODE" .. player_header .. " - " .. units_type .. ":\n\nNo enemy radars detecting you", 
            Config.EWRS.message_display_duration)
    end
end

-----------------------------------------------------
-- Start Search
-----------------------------------------------------
function EWRS:startSearch()
    env.info("EWRS: Starting search loop")
    
    timer.scheduleFunction(function(arg, time)
        local this = arg[1]
        this:searchTheatre()
        this:displayForUsers()
        return time + this.refresh_time
    end, {self}, timer.getTime() + 2)
    
    timer.scheduleFunction(function(arg, time)
        local this = arg[1]
        env.info("EWRS: Refreshing radar cache for dynamic spawns")
        this:cacheRadars()
        return time + Config.EWRS.radar_cache_refresh_time
    end, {self}, timer.getTime() + 5)
end

function EWRS:setBullseye(x, z)
    if x and z then
        self.bullseye = {x = x, z = z}
        env.info("EWRS: Bullseye set to " .. x .. ", " .. z)
    end
end

-----------------------------------------------------
-- User Management
-----------------------------------------------------
function EWRS:addUser(unit, view_radius)
    if not unit or not unit:isExist() then return end
    
    local name = unit:getName()
    local enemy_radius = view_radius or mist.utils.NMToMeters(Config.EWRS.default_radius_nm)
    local friendly_radius = mist.utils.NMToMeters(Config.EWRS.friendly_default_radius_nm)
    
    self.users[name] = {
        unit = unit,
        enemy_view_radius = enemy_radius,
        friendly_view_radius = friendly_radius,
        units = (self.side == coalition.side.BLUE) and Config.EWRS.default_units_blue or Config.EWRS.default_units_red,
        include_helos = true,
        reference = (self.side == coalition.side.BLUE) and Config.EWRS.default_reference_blue or Config.EWRS.default_reference_red,
        max_contacts = Config.EWRS.default_max_contacts,
        friendly_max_contacts = Config.EWRS.default_friendly_max_contacts,
        training_mode = false
    }
    
    env.info("EWRS: User added: " .. name .. 
             " with enemy radius " .. mist.utils.metersToNM(enemy_radius) .. "nm" ..
             " and friendly radius " .. mist.utils.metersToNM(friendly_radius) .. "nm" ..
             " - Training mode: false")
    trigger.action.outTextForUnit(unit:getID(), 
        "EWRS enabled. Enemy radius: " .. mist.utils.metersToNM(enemy_radius) .. 
        " NM, Friendly radius: " .. mist.utils.metersToNM(friendly_radius) .. " NM", 5)
end

function EWRS:removeUser(name, unit)
    self.users[name] = nil
    if unit and unit:isExist() then
        trigger.action.outTextForUnit(unit:getID(), "EWRS reports hidden.", 5)
    end
    env.info("EWRS: User removed: " .. name)
end

function EWRS:setUnits(name, val)
    if self.users[name] then
        self.users[name].units = val
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Units set to " .. val, 5)
    end
end

function EWRS:toggleHelos(name)
    if self.users[name] then
        local current = self.users[name].include_helos
        self.users[name].include_helos = not current
        local status = not current and "INCLUDED" or "EXCLUDED"
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Helicopters " .. status, 5)
    end
end

function EWRS:setRef(name, val)
    if self.users[name] then
        self.users[name].reference = val
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Reference set to " .. val, 5)
    end
end

function EWRS:toggleTrainingMode(name)
    if self.users[name] then
        local current = self.users[name].training_mode
        self.users[name].training_mode = not current
        local status = not current and "ENABLED" or "DISABLED"
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Training mode " .. status, 5)
        env.info("EWRS: Training mode " .. status .. " for user " .. name)
    end
end

function EWRS:toggleSpeedReporting(name)
    if self.users[name] then
        local current = Config.EWRS.enable_speed_reporting
        Config.EWRS.enable_speed_reporting = not current
        local status = not current and "ENABLED" or "DISABLED"
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Speed reporting " .. status, 5)
        env.info("EWRS: Speed reporting " .. status .. " for user " .. name)
    end
end

function EWRS:setSpeedReportingUnits(name, units)
    if self.users[name] then
        if units == "KNOTS" or units == "KMH" then
            if self.side == coalition.side.BLUE then
    Config.EWRS.speed_report_units_blue = units
else
    Config.EWRS.speed_report_units_red = units
end
            trigger.action.outTextForUnit(self.users[name].unit:getID(), 
                "EWRS: Speed reporting units set to " .. units, 5)
        end
    end
end

function EWRS:setEnemyRange(name, radius_nm)
    if self.users[name] then
        self.users[name].enemy_view_radius = mist.utils.NMToMeters(radius_nm)
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Enemy range filter set to " .. radius_nm .. " NM", 5)
    end
end

function EWRS:setFriendlyRange(name, radius_nm)
    if self.users[name] then
        self.users[name].friendly_view_radius = mist.utils.NMToMeters(radius_nm)
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Friendly range filter set to " .. radius_nm .. " NM", 5)
    end
end

function EWRS:setEnemyMaxContacts(name, count)
    if self.users[name] then
        self.users[name].max_contacts = count
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Enemy max contacts set to " .. count, 5)
    end
end

function EWRS:setFriendlyMaxContacts(name, count)
    if self.users[name] then
        self.users[name].friendly_max_contacts = count
        trigger.action.outTextForUnit(self.users[name].unit:getID(), 
            "EWRS: Friendly max contacts set to " .. count, 5)
    end
end

-----------------------------------------------------
-- Enemy Picture Display On-Demand
-----------------------------------------------------
function EWRS:displayEnemyPictureOnDemand(unit)
    env.info("EWRS: Enemy picture requested on-demand")
    
    if not unit or not unit:isExist() then
        env.info("EWRS EP: Invalid unit")
        return
    end

    local group = unit:getGroup()
    if not group then
        env.info("EWRS EP: No group")
        return
    end
    
    local unitName = unit:getName()
    local user_data = self.users[unitName]
    
    if user_data and user_data.training_mode then
        self:displayTrainingPictureOnDemand(unit)
        return
    end
    
    local view_radius = user_data and user_data.enemy_view_radius or mist.utils.NMToMeters(Config.EWRS.default_radius_nm)
    local units_type = user_data and user_data.units or "IMPERIAL"
    
    local display_radius
    if units_type == "METRIC" then
        display_radius = math.floor(view_radius / 1000)
    else
        display_radius = math.floor(mist.utils.metersToNM(view_radius))
    end
    
    local player_name = unit:getPlayerName()
    local player_header = player_name and (" - " .. player_name) or ""
    
    trigger.action.outTextForUnit(unit:getID(), 
        string.format("ENEMY PICTURE%s: %d%s - Check auto-refresh in %d seconds", 
            player_header, 
            display_radius,
            units_type == "METRIC" and "km" or "nm",
            Config.EWRS.refresh_time), 5)
end

-----------------------------------------------------
-- Display Training Picture On-Demand
-----------------------------------------------------
function EWRS:displayTrainingPictureOnDemand(unit)
    env.info("EWRS: Training picture requested on-demand")
    
    if not unit or not unit:isExist() then
        env.info("EWRS TP: Invalid unit")
        return
    end

    local group = unit:getGroup()
    if not group then
        env.info("EWRS TP: No group")
        return
    end
    
    local unitName = unit:getName()
    local user_data = self.users[unitName]
    
    if user_data then
        self:displayTrainingModeForUser(unitName, user_data)
    end
end

-----------------------------------------------------
-- Friendly Picture Display
-----------------------------------------------------
function EWRS:displayFriendlyPicture(unit)
    env.info("EWRS: Friendly picture requested")
    
    if not unit or not unit:isExist() then return end

    local unitName = unit:getName()
    local user_data = self.users[unitName]
    local user_point = unit:getPoint()
    local units_type = user_data and user_data.units or "IMPERIAL"
    local view_radius = user_data and user_data.friendly_view_radius 
                        or mist.utils.NMToMeters(Config.EWRS.friendly_default_radius_nm)
    local max_contacts = user_data and user_data.friendly_max_contacts 
                         or Config.EWRS.default_friendly_max_contacts

    local nearby = {}

    -- Scan all friendly groups
    local groups = coalition.getGroups(self.side)
    for _, group in ipairs(groups) do
        if group and group:isExist() then
            for _, target in ipairs(group:getUnits()) do
                if target and target:isExist() then
                    local desc = target:getDesc()
                    local isAir = desc.category == Unit.Category.AIRPLANE 
                               or desc.category == Unit.Category.HELICOPTER
                    
                    if isAir and target:getName() ~= unitName then
                        local target_point = target:getPoint()
                        local range = mist.utils.get2DDist(user_point, target_point)
                        
                        if range <= view_radius then
                            local bearing_deg = math.floor(
                                (math.deg(math.atan2(
                                    target_point.x - user_point.x,
                                    target_point.z - user_point.z
                                )) + 360) % 360
                            )
                            
                            local alt = target_point.y
                            local player_name = target:getPlayerName()
                            local label = (Config.EWRS.friendly_use_player_names and player_name) 
                                          or target:getTypeName()

                            table.insert(nearby, {
                                label = label,
                                range = range,
                                bearing = bearing_deg,
                                alt = alt,
                                is_player = player_name ~= nil
                            })
                        end
                    end
                end
            end
        end
    end

    local player_name = unit:getPlayerName()
    local player_header = player_name and (" - " .. player_name) or ""

    if #nearby == 0 then
        trigger.action.outTextForUnit(unit:getID(),
            "FRIENDLY PICTURE" .. player_header .. ":\n\nNo friendly air contacts within range", 8)
        return
    end

    -- Sort by range
    table.sort(nearby, function(a, b) return a.range < b.range end)

    local display_radius
    if units_type == "METRIC" then
        display_radius = math.floor(view_radius / 1000)
    else
        display_radius = math.floor(mist.utils.metersToNM(view_radius))
    end

    local report = string.format("FRIENDLY PICTURE%s: %d%s - %d contacts\n\n",
        player_header,
        display_radius,
        units_type == "METRIC" and "km" or "nm",
        math.min(#nearby, max_contacts)
    )

    -- Find max label length for alignment
    local maxLen = 0
    for i = 1, math.min(#nearby, max_contacts) do
        if #nearby[i].label > maxLen then maxLen = #nearby[i].label end
    end
    maxLen = maxLen + 3

    for i = 1, math.min(#nearby, max_contacts) do
        local t = nearby[i]

        local alt_str
        if units_type == "METRIC" then
            if t.alt >= 1000 then
                alt_str = string.format("%dK m", math.floor(t.alt / 1000))
            else
                alt_str = string.format("%d m", math.floor(t.alt))
            end
        else
            if t.alt >= 304.8 then
                alt_str = string.format("%dK", math.floor(mist.utils.metersToFeet(t.alt) / 1000))
            else
                alt_str = string.format("%dft", math.floor(mist.utils.metersToFeet(t.alt)))
            end
        end

        local range_display
        if units_type == "METRIC" then
            range_display = math.floor(t.range / 1000)
        else
            range_display = math.floor(mist.utils.metersToNM(t.range))
        end

        local paddedLabel = padToWidth(t.label, maxLen)

        if units_type == "METRIC" then
            report = report .. string.format("%s%03d / %3d km / %s\n",
                paddedLabel, t.bearing, range_display, alt_str)
        else
            report = report .. string.format("%s%03d / %3d nm / %s\n",
                paddedLabel, t.bearing, range_display, alt_str)
        end
    end

    trigger.action.outTextForUnit(unit:getID(), report, Config.EWRS.message_display_duration)
end

-----------------------------------------------------
-- F10 Menu Creation
-----------------------------------------------------
function EWRS:addRadioMenuForUser(unit)
    if not unit or not unit:isExist() then return end

    local group = unit:getGroup()
    if not group then return end
    
    local unitName = unit:getName()
    local unitID = unit:getID()
    local gr_id = group:getID()

    self.menuAdded = self.menuAdded or {}
    if self.menuAdded[unitID] then return end

    local function makeUnitCommand(funcName)
        local capturedUnitName = unitName
        return function()
            local u = Unit.getByName(capturedUnitName)
            if u and u:isExist() then
                self[funcName](self, capturedUnitName)
            end
        end
    end
    
    local function makeUnitCommandWithParam(funcName, param)
        local capturedUnitName = unitName
        local capturedParam = param
        return function()
            local u = Unit.getByName(capturedUnitName)
            if u and u:isExist() then
                self[funcName](self, capturedUnitName, capturedParam)
            end
        end
    end
    
    local function makeBogeyDope()
        local capturedUnitName = unitName
        return function()
            local u = Unit.getByName(capturedUnitName)
            if u and u:isExist() then
                EWRS_coalition[u:getCoalition()]:displayEnemyPictureOnDemand(u)
            else
                trigger.action.outTextForGroup(gr_id, "ENEMY PICTURE\n\nNO DATA", 5)
            end
        end
    end
    
    local function makeFriendlyPicture()
        local capturedUnitName = unitName
        return function()
            local u = Unit.getByName(capturedUnitName)
            if u and u:isExist() then
                EWRS_coalition[u:getCoalition()]:displayFriendlyPicture(u)
            else
                trigger.action.outTextForGroup(gr_id, "FRIENDLY PICTURE\n\nNO DATA", 5)
            end
        end
    end

    local rootPath = missionCommands.addSubMenuForGroup(gr_id, "EWRS - " .. (unit:getPlayerName() or "Unknown"))
    
    self.menuPaths = self.menuPaths or {}
    self.menuPaths[unitID] = {path = rootPath, groupID = gr_id}

    missionCommands.addCommandForGroup(gr_id, "Toggle HELO", rootPath, makeUnitCommand("toggleHelos"))
    missionCommands.addCommandForGroup(gr_id, "Bogey Dope", rootPath, makeBogeyDope())

    if Config.EWRS.friendly_picture_enable then
        missionCommands.addCommandForGroup(gr_id, "Request Friendly Picture", rootPath, makeFriendlyPicture())
    end

    if Config.EWRS.enable_training_mode then
        missionCommands.addCommandForGroup(gr_id, "Toggle Training Mode", rootPath, makeUnitCommand("toggleTrainingMode"))
    end

    local settingsMenu = missionCommands.addSubMenuForGroup(gr_id, "Settings", rootPath)

    local enemyRangeMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Enemy Range Filter", settingsMenu)
    for _, nm in ipairs(Config.EWRS.enemy_range_options) do
        missionCommands.addCommandForGroup(gr_id, nm .. " NM", enemyRangeMenu, makeUnitCommandWithParam("setEnemyRange", nm))
    end

    local friendlyRangeMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Friendly Range Filter", settingsMenu)
    for _, nm in ipairs(Config.EWRS.friendly_range_options) do
        missionCommands.addCommandForGroup(gr_id, nm .. " NM", friendlyRangeMenu, makeUnitCommandWithParam("setFriendlyRange", nm))
    end

    local refMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Reference", settingsMenu)
    missionCommands.addCommandForGroup(gr_id, "Ownship", refMenu, makeUnitCommandWithParam("setRef", "OWN"))
    missionCommands.addCommandForGroup(gr_id, "Bullseye", refMenu, makeUnitCommandWithParam("setRef", "BULLSEYE"))

    local unitsMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Units", settingsMenu)
    missionCommands.addCommandForGroup(gr_id, "Imperial (NM / ft)", unitsMenu, makeUnitCommandWithParam("setUnits", "IMPERIAL"))
    missionCommands.addCommandForGroup(gr_id, "Metric (km / m)", unitsMenu, makeUnitCommandWithParam("setUnits", "METRIC"))

    local enemyContactsMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Enemy Max Contacts", settingsMenu)
    for _, count in ipairs(Config.EWRS.enemy_contact_options) do
        missionCommands.addCommandForGroup(gr_id, tostring(count) .. " Contacts", enemyContactsMenu, makeUnitCommandWithParam("setEnemyMaxContacts", count))
    end

    local friendlyContactsMenu = missionCommands.addSubMenuForGroup(gr_id, "Set Friendly Max Contacts", settingsMenu)
    for _, count in ipairs(Config.EWRS.friendly_contact_options) do
        missionCommands.addCommandForGroup(gr_id, tostring(count) .. " Contacts", friendlyContactsMenu, makeUnitCommandWithParam("setFriendlyMaxContacts", count))
    end

    local speedMenu = missionCommands.addSubMenuForGroup(gr_id, "Speed Reporting", settingsMenu)
    missionCommands.addCommandForGroup(gr_id, "Toggle Speed Report", speedMenu, makeUnitCommand("toggleSpeedReporting"))
    missionCommands.addCommandForGroup(gr_id, "Set to Knots", speedMenu, makeUnitCommandWithParam("setSpeedReportingUnits", "KNOTS"))
    missionCommands.addCommandForGroup(gr_id, "Set to km/h", speedMenu, makeUnitCommandWithParam("setSpeedReportingUnits", "KMH"))

    missionCommands.addCommandForGroup(gr_id, "Enable Reports", settingsMenu, function()
        local capturedUnitName = unitName
        local u = Unit.getByName(capturedUnitName)
        if u and u:isExist() then
            EWRS_coalition[u:getCoalition()]:addUser(u, mist.utils.NMToMeters(Config.EWRS.default_radius_nm))
        end
    end)

    missionCommands.addCommandForGroup(gr_id, "Hide Reports", settingsMenu, function()
        local capturedUnitName = unitName
        local u = Unit.getByName(capturedUnitName)
        if u and u:isExist() then
            EWRS_coalition[u:getCoalition()]:removeUser(capturedUnitName, u)
        end
    end)

    self.menuAdded[unitID] = true
    
    env.info("EWRS: Menu added for unit " .. unitName .. " (player: " .. (unit:getPlayerName() or "AI") .. ")")
end

-----------------------------------------------------
-- HARDENED INITIALIZATION
-----------------------------------------------------

if Config.EWRS.enable then

    env.info("EWRS: Initializing HARDENED v11.9 geometry fork")

    EWRS_coalition = {
        [coalition.side.BLUE] = EWRS:new(coalition.side.BLUE),
        [coalition.side.RED]  = EWRS:new(coalition.side.RED),
    }

    -------------------------------------------------
    -- SAFE BULLSEYE SET
    -------------------------------------------------
    for side, ewrs in pairs(EWRS_coalition) do
        local bullseyePoint = coalition.getMainRefPoint(side)
        if bullseyePoint and bullseyePoint.x and bullseyePoint.z then
            ewrs:setBullseye(bullseyePoint.x, bullseyePoint.z)
        else
            env.info("EWRS: No bullseye found for side " .. tostring(side))
        end
    end

    -------------------------------------------------
    -- SAFE UNIT VALIDATION
    -------------------------------------------------
    local function isValidUnit(obj)
        if not obj then return false end
        if not obj.isExist then return false end
        if not obj:isExist() then return false end
        
        local success, category = pcall(function() return obj:getCategory() end)
        if not success then return false end
        
        return category == Object.Category.UNIT
    end

    -------------------------------------------------
    -- SAFE MENU ADD
    -------------------------------------------------
    local function addMenuToUnit(unit)

        if not isValidUnit(unit) then return end
        if not unit:getPlayerName() then return end

        local side = unit:getCoalition()
        local ewrs = EWRS_coalition[side]
        if not ewrs then return end

        timer.scheduleFunction(function()

            if not isValidUnit(unit) then return end

            ewrs:addRadioMenuForUser(unit)

            if Config.EWRS.auto_enable_on_spawn then
                ewrs:addUser(unit, mist.utils.NMToMeters(Config.EWRS.default_radius_nm))
            end

        end, {}, timer.getTime() + 1)
    end

    -------------------------------------------------
    -- HARDENED EVENT HANDLER
    -------------------------------------------------
    local ewrsEventHandler = {}

    function ewrsEventHandler:onEvent(event)

        if not event then return end
        if not event.initiator then return end
        if not isValidUnit(event.initiator) then return end

        local unit = event.initiator
        local unitName = unit:getName()
        local unitID = unit:getID()

        -------------------------------------------------
        -- PLAYER SPAWN
        -------------------------------------------------
        if event.id == world.event.S_EVENT_BIRTH then

            if unit:getPlayerName() then
                addMenuToUnit(unit)
            end

        -------------------------------------------------
        -- HARD CLEANUP: Eject / Crash / Death 
        -------------------------------------------------
        elseif event.id == world.event.S_EVENT_EJECTION
            or event.id == world.event.S_EVENT_PILOT_DEAD
            or event.id == world.event.S_EVENT_CRASH
            or event.id == world.event.S_EVENT_DEAD then
            
            for side, ewrs in pairs(EWRS_coalition) do

                if ewrs.menuPaths and ewrs.menuPaths[unitID] then
                    local menuInfo = ewrs.menuPaths[unitID]
                    if menuInfo.path and menuInfo.groupID then
                        missionCommands.removeItemForGroup(menuInfo.groupID, menuInfo.path)
                        env.info("EWRS: Removed menu for unit " .. unitName)
                    end
                    ewrs.menuPaths[unitID] = nil
                end

                if ewrs.users[unitName] then
                    ewrs.users[unitName] = nil
                end

                if ewrs.menuAdded and unitID then
                    ewrs.menuAdded[unitID] = nil
                end
            end

            env.info("EWRS: Cleaned up user " .. unitName)

        -------------------------------------------------
        -- SOFT CLEANUP: Player leaves slot (landing, slot change)
        -- Only reset menu so it rebuilds on next BIRTH.
        -- User data is also cleared so addUser fires fresh on respawn.
        -------------------------------------------------
        elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then

            for side, ewrs in pairs(EWRS_coalition) do
                if ewrs.menuPaths and ewrs.menuPaths[unitID] then
                    local menuInfo = ewrs.menuPaths[unitID]
                    if menuInfo.path and menuInfo.groupID then
                        pcall(function()
                            missionCommands.removeItemForGroup(menuInfo.groupID, menuInfo.path)
                        end)
                    end
                    ewrs.menuPaths[unitID] = nil
                end
                if ewrs.menuAdded then
                    ewrs.menuAdded[unitID] = nil
                end
                if ewrs.users[unitName] then
                    ewrs.users[unitName] = nil
                end
            end

            env.info("EWRS: Player left slot: " .. unitName .. " (menu reset, will re-add on BIRTH)")

        end  -- closes the if/elseif chain
    end      -- closes onEvent

    world.addEventHandler(ewrsEventHandler)

    -------------------------------------------------
    -- ADD MENUS FOR EXISTING PLAYERS (SAFE)
    -------------------------------------------------
    timer.scheduleFunction(function()

        for side, ewrs in pairs(EWRS_coalition) do

            local groups = coalition.getGroups(side)

            if groups then
                for _, group in ipairs(groups) do

                    if group and group:isExist() then
                        local units = group:getUnits()

                        for _, unit in ipairs(units) do
                            if isValidUnit(unit) and unit:getPlayerName() then
                                addMenuToUnit(unit)
                            end
                        end
                    end
                end
            end
        end

    end, {}, timer.getTime() + 3)

    trigger.action.outText("Lock-On Greece / DCS World Greece - EWRS v11.9 geometry fork", 20)

else
    env.info("EWRS: Disabled")
end
local TowDrivers = {}
local TowCalls = {}
local CallQueue = {}
local callIdCounter = 0

local CompanyRotation = {}
local RotationIndex = 1

local TowStats = {}
local statsFileName = "tow_stats.json"

local tryAssignQueuedCalls

-------------------------------------------------
-- Utility / helpers
-------------------------------------------------

local function notify(src, text, nType)
    TriggerClientEvent('twopoint_tow:notify', src, {
        title = Config.Notify.title,
        description = text,
        type = nType or 'info',
        position = Config.Notify.position,
        duration = Config.Notify.duration
    })
end

local function debugPrint(...)
    if not Config.Debug then return end
    print("[TwoPoint_TowDuty]", ...)
end

local function getLBPhoneResource()
    return (Config.LBPhone and Config.LBPhone.resource) or "lb-phone"
end

local function getLBPhoneAppIdentifier()
    return (Config.LBPhone and Config.LBPhone.appIdentifier) or "twopoint_tow"
end

local function forcePhoneOnlyMode()
    return Config.LBPhone and Config.LBPhone.forcePhoneOnlyMode == true
end

local function defaultPhoneOnlyMode()
    if not Config.LBPhone then return false end
    if forcePhoneOnlyMode() then return true end
    return Config.LBPhone.phoneOnlyModeDefault ~= false
end

local function lbPhoneEnabled()
    return Config.LBPhone
        and Config.LBPhone.enabled
        and GetResourceState(getLBPhoneResource()) == "started"
end

local function sendPhoneAppUpdate(src)
    if not Config.LBPhone or not Config.LBPhone.enabled then return end
    TriggerClientEvent('twopoint_tow:phoneAppUpdate', src)
end

local function broadcastPhoneAppUpdate()
    if not Config.LBPhone or not Config.LBPhone.enabled then return end
    for src, info in pairs(TowDrivers) do
        if info.onDuty then
            sendPhoneAppUpdate(src)
        end
    end
end

local function trimString(value)
    value = value and tostring(value) or ""
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeCompanyName(value)
    return trimString(value):lower()
end

local function getDefaultDutyPasswords()
    if Config.TowDutyAuth and Config.TowDutyAuth.DefaultPasswords then
        return Config.TowDutyAuth.DefaultPasswords
    end
    return Config.TowDutyPasswords or {}
end

local function defaultPasswordAllowed(password)
    password = tostring(password or "")
    if password == "" then return false end

    for _, pw in ipairs(getDefaultDutyPasswords()) do
        if tostring(pw) == password then
            return true
        end
    end

    return false
end

local function getConfiguredCompanyAuth(company)
    local wanted = normalizeCompanyName(company)
    if wanted == "" then return nil end

    local configured = Config.TowDutyAuth and Config.TowDutyAuth.Companies or nil
    if type(configured) ~= "table" then return nil end

    for name, password in pairs(configured) do
        if normalizeCompanyName(name) == wanted then
            return tostring(name), tostring(password or "")
        end
    end

    return nil
end

local function validateDutyLogin(company, password)
    password = tostring(password or "")
    company = trimString(company)
    if company == "" then company = "Tow" end

    if password == "" then
        return false, Config.Messages.wrongPassword or "Invalid tow duty password."
    end

    local configuredCompany, configuredPassword = getConfiguredCompanyAuth(company)
    if configuredCompany then
        if configuredPassword ~= "" and password == configuredPassword then
            return true, nil, configuredCompany
        end
        return false, Config.Messages.wrongPassword or "Invalid tow duty password."
    end

    local authCfg = Config.TowDutyAuth or {}
    if authCfg.AllowRandomCompanyNames == false then
        return false, Config.Messages.unknownCompany or "Unknown tow company."
    end

    if defaultPasswordAllowed(password) then
        return true, nil, company
    end

    return false, Config.Messages.wrongPassword or "Invalid tow duty password."
end

local function isValidDutyPassword(password)
    local ok = validateDutyLogin("Tow", password)
    return ok == true
end

local function getTowCounts()
    local onDuty, idle = 0, 0
    for _, info in pairs(TowDrivers) do
        if info.onDuty then
            onDuty = onDuty + 1
            if not info.busy then
                idle = idle + 1
            end
        end
    end
    return onDuty, idle
end

local function broadcastAvailability()
    local onDuty = getTowCounts()
    TriggerClientEvent('twopoint_tow:updateAvailability', -1, onDuty > 0)
end

local function getCurrentRotationCompany()
    if #CompanyRotation == 0 then return nil end
    return CompanyRotation[RotationIndex]
end

local function broadcastRotation()
    TriggerClientEvent('twopoint_tow:updateRotationCompany', -1, getCurrentRotationCompany())
end

local function refreshCompanies()
    local seen = {}
    local newList = {}

    for _, info in pairs(TowDrivers) do
        if info.onDuty and info.companyName and info.companyName ~= "" then
            if not seen[info.companyName] then
                seen[info.companyName] = true
                table.insert(newList, info.companyName)
            end
        end
    end

    CompanyRotation = newList
    if RotationIndex > #CompanyRotation then
        RotationIndex = 1
    end

    broadcastRotation()
end

local function getNextCompany(exclude)
    if #CompanyRotation == 0 then return nil end
    local checked = 0

    while checked < #CompanyRotation do
        local company = CompanyRotation[RotationIndex]
        RotationIndex = RotationIndex + 1
        if RotationIndex > #CompanyRotation then
            RotationIndex = 1
        end
        checked = checked + 1

        if not exclude or not exclude[company] then
            broadcastRotation()
            return company
        end
    end

    return nil
end

local function companyHasDrivers(company)
    for _, info in pairs(TowDrivers) do
        if info.onDuty and info.companyName == company then
            return true
        end
    end
    return false
end

local function getCallByRequester(src)
    for _, call in pairs(TowCalls) do
        if call.requester == src and call.status ~= 'completed' and call.status ~= 'cancelled' then
            return call
        end
    end
end

local function getDriverInfo(src)
    if not TowDrivers[src] then
        TowDrivers[src] = {
            onDuty = false,
            busy = false,
            currentCallId = nil,
            companyName = nil,
            dutyStartedAt = nil,
            identifier = nil,
            onDutyViaPhone = false,
            phoneOnlyMode = defaultPhoneOnlyMode()
        }
    end
    return TowDrivers[src]
end

local function getIdentifier(src)
    local identifier
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and id:sub(1, 8) == "license:" then
            identifier = id
            break
        end
    end
    if not identifier then
        identifier = GetPlayerIdentifier(src, 0)
    end
    return identifier or tostring(src)
end

local function loadStats()
    local resName = GetCurrentResourceName()
    local raw = LoadResourceFile(resName, statsFileName)
    if raw then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == "table" then
            TowStats = data
            debugPrint("Loaded tow stats")
        else
            debugPrint("Failed to decode tow stats file")
        end
    end
end

local function saveStats()
    local resName = GetCurrentResourceName()
    SaveResourceFile(resName, statsFileName, json.encode(TowStats or {}), -1)
end

local function formatDuration(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format("%02dh %02dm %02ds", h, m, s)
end

local function sendWebhook(url, embed)
    if not url or url == "" then return end
    PerformHttpRequest(url, function() end, "POST", json.encode({ embeds = { embed } }), {
        ["Content-Type"] = "application/json"
    })
end

local function addDutyTime(src)
    local info = TowDrivers[src]
    if not info or not info.onDuty or not info.dutyStartedAt then
        return 0
    end

    local now = os.time()
    local session = now - (info.dutyStartedAt or now)
    if session < 0 then session = 0 end

    local identifier = info.identifier or getIdentifier(src)
    info.identifier = identifier

    TowStats[identifier] = TowStats[identifier] or { totalSeconds = 0 }
    TowStats[identifier].totalSeconds = (TowStats[identifier].totalSeconds or 0) + session
    saveStats()

    info.dutyStartedAt = nil

    return session
end

local function sendDutyWebhook(src, action, companyName, sessionSeconds)
    local url = Config.Webhooks and Config.Webhooks.Duty or nil
    if not url or url == "" then return end

    local name = GetPlayerName(src) or "Unknown"
    local identifier = getIdentifier(src)
    local stats = TowStats[identifier] or {}
    local totalSeconds = stats.totalSeconds or 0

    local embed = {
        title = ("Tow Duty %s"):format(action),
        color = action == "On" and 65280 or 16711680,
        fields = {
            { name = "Player",   value = string.format("%s (%s)", name, identifier), inline = false },
            { name = "Company",  value = companyName or "N/A", inline = true }
        },
        footer = { text = "TwoPoint Tow Duty" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }

    if action == "Off" then
        table.insert(embed.fields, { name = "Session Time",    value = formatDuration(sessionSeconds or 0), inline = true })
        table.insert(embed.fields, { name = "Total Tow Time",  value = formatDuration(totalSeconds), inline = true })
    end

    sendWebhook(url, embed)
end

local function setTowDutyOn(src, company, viaPhone)
    local info = getDriverInfo(src)
    company = company and tostring(company) or ""
    company = company:gsub("^%s+", ""):gsub("%s+$", "")
    if company == "" then company = "Tow" end

    info.onDuty = true
    info.busy = false
    info.currentCallId = nil
    info.companyName = company
    info.dutyStartedAt = os.time()
    info.identifier = getIdentifier(src)
    info.onDutyViaPhone = viaPhone == true
    if viaPhone and Config.LBPhone then
        info.phoneOnlyMode = defaultPhoneOnlyMode()
    end

    notify(src, string.format(Config.Messages.dutyOnCompany or "You are now on Tow Duty with %s.", company), "success")
    sendDutyWebhook(src, "On", company, 0)

    refreshCompanies()
    broadcastAvailability()
    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()

    tryAssignQueuedCalls()
end

local function setTowDutyOff(src)
    local info = getDriverInfo(src)
    if not info.onDuty then return false end

    local session = addDutyTime(src)
    local companyName = info.companyName
    info.onDuty = false
    info.busy = false
    info.currentCallId = nil
    info.companyName = nil
    info.onDutyViaPhone = false
    info.phoneOnlyMode = defaultPhoneOnlyMode()

    notify(src, Config.Messages.dutyOff or "You are now off Tow Duty.", "inform")
    sendDutyWebhook(src, "Off", companyName, session)

    refreshCompanies()
    broadcastAvailability()
    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()
    return true
end

local function sendLBPhoneTowNotification(src, call, distance)
    if not lbPhoneEnabled() then return false end

    local info = getDriverInfo(src)
    if Config.LBPhone.notificationsRequirePhoneDuty ~= false and not info.onDutyViaPhone then
        return false
    end

    local caller = call.callerName or (call.requester and GetPlayerName(call.requester)) or "Unknown"
    local content = ("Caller: %s"):format(caller)
    if distance then
        content = content .. (" • %.1fm away"):format(distance)
    end

    local ok, err = pcall(function()
        exports[getLBPhoneResource()]:SendNotification(src, {
            app = getLBPhoneAppIdentifier(),
            title = "New Tow Call",
            content = content,
            customData = {
                buttons = {
                    { title = "Accept", event = "twopoint_tow:phoneNotificationAccept", server = true, data = { callId = call.id } },
                    { title = "Reject", event = "twopoint_tow:phoneNotificationReject", server = true, data = { callId = call.id } }
                }
            }
        })
    end)

    if not ok then
        debugPrint("LB Phone notification failed:", err)
        return false
    end

    return true
end

-------------------------------------------------
-- Queue helpers
-------------------------------------------------

local function isCallQueued(callId)
    for i, id in ipairs(CallQueue) do
        if id == callId then
            return true, i
        end
    end
    return false, nil
end

local function queueCall(callId)
    local exists = isCallQueued(callId)
    if not exists then
        table.insert(CallQueue, callId)
    end
    local call = TowCalls[callId]
    if call then
        call.status = 'queued'
    end
    debugPrint("Queued call", callId)
end

local function dequeueCall(callId)
    local exists, idx = isCallQueued(callId)
    if exists and idx then
        table.remove(CallQueue, idx)
    end
end

tryAssignQueuedCalls = function()
    if #CallQueue == 0 then return end

    local snapshot = {}
    for _, id in ipairs(CallQueue) do
        table.insert(snapshot, id)
    end

    for _, callId in ipairs(snapshot) do
        local call = TowCalls[callId]
        if call and call.status == 'queued' then
            TriggerEvent('twopoint_tow:internalDispatchCall', callId)
        end
    end
end

-------------------------------------------------
-- Dispatch logic
-------------------------------------------------

AddEventHandler('twopoint_tow:internalDispatchCall', function(callId)
    local call = TowCalls[callId]
    if not call then return end

    call.declinedCompanies = call.declinedCompanies or {}
    local chosenCompany = call.companyName

    -- If this company has already declined this call, do not immediately
    -- re-offer it to the same company/driver. This fixes rejected popups
    -- sticking at the top because the same call was dispatched again.
    if chosenCompany and call.declinedCompanies[chosenCompany] then
        chosenCompany = nil
        call.companyName = nil
    end

    if not chosenCompany or not companyHasDrivers(chosenCompany) then
        chosenCompany = getNextCompany(call.declinedCompanies)
        call.companyName = chosenCompany
    end

    if not chosenCompany then
        queueCall(callId)
        return
    end

    local candidates = {}
    for src, info in pairs(TowDrivers) do
        if info.onDuty and not info.busy and info.companyName == chosenCompany then
            table.insert(candidates, src)
        end
    end

    if #candidates == 0 then
        queueCall(callId)
        return
    end

    local targetCoords = vector3(call.coords.x, call.coords.y, call.coords.z)
    local bestSrc, bestDist = nil, nil

    for _, src in ipairs(candidates) do
        local ped = GetPlayerPed(src)
        if ped ~= 0 then
            local coords = GetEntityCoords(ped)
            local dist = #(coords - targetCoords)
            if not bestDist or dist < bestDist then
                bestSrc = src
                bestDist = dist
            end
        end
    end

    if not bestSrc then
        queueCall(callId)
        return
    end

    local info = getDriverInfo(bestSrc)
    info.busy = true
    info.currentCallId = callId

    call.status = 'offered'
    call.assignedDriver = nil
    call.offeredTo = bestSrc
    call.offerExpires = os.time() + math.floor((Config.AcceptTime or 15000) / 1000)
    call.lastCompanyChange = os.time()

    dequeueCall(callId)

    local name = call.callerName or (call.requester and GetPlayerName(call.requester)) or "Unknown"
    local usePhoneOnly = info.onDutyViaPhone and (forcePhoneOnlyMode() or info.phoneOnlyMode)
    local sentPhoneNotification = false

    if usePhoneOnly then
        sentPhoneNotification = sendLBPhoneTowNotification(bestSrc, call, bestDist or 0.0)
    end

    -- If forcePhoneOnlyMode is enabled, never fall back to the on-screen prompt
    -- for phone-duty drivers. The call still appears in the Tow Duty phone app.
    if not sentPhoneNotification and not (usePhoneOnly and forcePhoneOnlyMode()) then
        TriggerClientEvent('twopoint_tow:promptCall', bestSrc, callId, call.coords, name, Config.AcceptTime, bestDist or 0.0)
    end

    local offeredCompany = call.companyName
    local offerExpires = call.offerExpires
    SetTimeout((Config.AcceptTime or 15000) + 1000, function()
        local timeoutCall = TowCalls[callId]
        if not timeoutCall or timeoutCall.status ~= 'offered' or timeoutCall.offeredTo ~= bestSrc or timeoutCall.offerExpires ~= offerExpires then
            return
        end

        local timeoutInfo = TowDrivers[bestSrc]
        if timeoutInfo and timeoutInfo.currentCallId == callId then
            timeoutInfo.busy = false
            timeoutInfo.currentCallId = nil
        end

        timeoutCall.declinedCompanies = timeoutCall.declinedCompanies or {}
        if offeredCompany then
            timeoutCall.declinedCompanies[offeredCompany] = true
        end
        timeoutCall.offeredTo = nil
        timeoutCall.status = 'queued'

        TriggerClientEvent('twopoint_tow:clearPrompt', bestSrc, callId)
        notify(bestSrc, Config.Messages.callTimedOut or "You did not respond to the tow call in time.", "info")
        sendPhoneAppUpdate(bestSrc)
        broadcastPhoneAppUpdate()
        TriggerEvent('twopoint_tow:internalDispatchCall', callId)
    end)

    sendPhoneAppUpdate(bestSrc)
    broadcastPhoneAppUpdate()
end)

-------------------------------------------------
-- ox_lib callbacks (for tablet)
-------------------------------------------------

local function buildTowQueueState(src)
    local info = getDriverInfo(src)
    if not info.onDuty then
        return { error = Config.Messages.notOnDuty or "You are not on tow duty." }
    end

    local ped = GetPlayerPed(src)
    local myCoords = ped ~= 0 and GetEntityCoords(ped) or nil

    local calls = {}
    local now = os.time()
    local activeOffer = nil

    for id, call in pairs(TowCalls) do
        if call.status ~= 'completed' and call.status ~= 'cancelled' then
            local requesterName = call.requester and GetPlayerName(call.requester) or "Unknown"
            local age = now - (call.createdAt or now)
            if age < 0 then age = 0 end

            local dist = nil
            if myCoords and call.coords then
                local v = vector3(call.coords.x, call.coords.y, call.coords.z)
                dist = #(myCoords - v)
            end

            local isOfferForMe = call.status == 'offered' and call.offeredTo == src
            local canAccept = false
            local canReject = false

            if isOfferForMe then
                canAccept = true
                canReject = true
            elseif not info.busy then
                canAccept = call.status == 'queued' or call.status == 'new'
                if call.companyName and call.companyName ~= info.companyName and companyHasDrivers(call.companyName) then
                    canAccept = false
                end
            end

            local callData = {
                id = call.id,
                requesterName = requesterName,
                companyName = call.companyName,
                status = call.status,
                assignedDriver = call.assignedDriver and GetPlayerName(call.assignedDriver) or nil,
                distance = dist,
                ageSeconds = age,
                canAccept = canAccept,
                canReject = canReject,
                offeredToMe = isOfferForMe
            }

            if isOfferForMe then
                activeOffer = callData
            end

            table.insert(calls, callData)
        end
    end

    table.sort(calls, function(a, b)
        return (a.id or 0) < (b.id or 0)
    end)

    return {
        calls = calls,
        busy = info.busy or false,
        companyName = info.companyName,
        onDuty = info.onDuty or false,
        onDutyViaPhone = info.onDutyViaPhone or false,
        phoneOnlyMode = forcePhoneOnlyMode() or info.phoneOnlyMode or false,
        forcePhoneOnlyMode = forcePhoneOnlyMode(),
        currentCallId = info.currentCallId,
        activeOffer = activeOffer,
        lbPhoneEnabled = lbPhoneEnabled()
    }
end

lib.callback.register('twopoint_tow:getQueue', function(source)
    return buildTowQueueState(source)
end)

local function acceptCallFromQueueForDriver(src, callId)
    local info = getDriverInfo(src)

    if not info.onDuty then
        return { ok = false, error = Config.Messages.notOnDuty or "You are not on tow duty." }
    end

    callId = tonumber(callId)
    local call = callId and TowCalls[callId] or nil
    if not call or call.status == 'completed' or call.status == 'cancelled' then
        return { ok = false, error = Config.Messages.callTaken or "This tow call has already been handled." }
    end

    local offeredToMe = call.status == 'offered' and call.offeredTo == src

    if info.busy and not offeredToMe then
        return { ok = false, error = "You already have an active tow call." }
    end

    if call.status == 'assigned' then
        return { ok = false, error = Config.Messages.callTaken or "This tow call has already been handled." }
    end

    if call.status == 'offered' and call.offeredTo and call.offeredTo ~= src then
        return { ok = false, error = "This tow call is currently being offered to another driver." }
    end

    if call.companyName and call.companyName ~= info.companyName and companyHasDrivers(call.companyName) then
        return { ok = false, error = "This tow call is assigned to another tow company." }
    end

    if call.offeredTo then
        TriggerClientEvent('twopoint_tow:clearPrompt', call.offeredTo, callId)
        local oldInfo = TowDrivers[call.offeredTo]
        if oldInfo and oldInfo.currentCallId == callId and call.offeredTo ~= src then
            oldInfo.busy = false
            oldInfo.currentCallId = nil
        end
    end

    dequeueCall(callId)

    call.status = 'assigned'
    call.assignedDriver = src
    call.offeredTo = nil
    call.companyName = info.companyName or call.companyName

    info.busy = true
    info.currentCallId = callId

    if call.requester then
        notify(call.requester, Config.Messages.callAcceptedCivilian or "A tow truck is en-route.", "success")
    end

    TriggerClientEvent('twopoint_tow:callAssigned', src, {
        id = call.id,
        coords = call.coords
    })

    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()
    return { ok = true }
end

lib.callback.register('twopoint_tow:acceptCallFromQueue', function(source, callId)
    return acceptCallFromQueueForDriver(source, callId)
end)

lib.callback.register('twopoint_tow:phoneGetState', function(source)
    local info = getDriverInfo(source)
    if not info.onDuty then
        return {
            onDuty = false,
            onDutyViaPhone = false,
            phoneOnlyMode = defaultPhoneOnlyMode(),
            forcePhoneOnlyMode = forcePhoneOnlyMode(),
            calls = {},
            busy = false,
            lbPhoneEnabled = lbPhoneEnabled()
        }
    end

    return buildTowQueueState(source)
end)

lib.callback.register('twopoint_tow:phoneLogin', function(source, data)
    data = data or {}
    local requestedCompany = data.companyName or data.company or "Tow"
    local password = data.password or ""

    if not lbPhoneEnabled() then
        return { ok = false, error = "LB Phone is not running." }
    end

    local valid, errorMessage, company = validateDutyLogin(requestedCompany, password)
    if not valid then
        return { ok = false, error = errorMessage or Config.Messages.wrongPassword or "Invalid tow duty password." }
    end

    local info = getDriverInfo(source)
    if info.onDuty then
        if company == "" then company = info.companyName or "Tow" end
        info.companyName = company
        info.onDutyViaPhone = true
        info.phoneOnlyMode = defaultPhoneOnlyMode()
        refreshCompanies()
        sendPhoneAppUpdate(source)
        broadcastPhoneAppUpdate()
        return { ok = true, state = buildTowQueueState(source) }
    end

    setTowDutyOn(source, company, true)
    return { ok = true, state = buildTowQueueState(source) }
end)

lib.callback.register('twopoint_tow:phoneLogout', function(source)
    setTowDutyOff(source)
    return { ok = true, state = { onDuty = false, calls = {}, phoneOnlyMode = defaultPhoneOnlyMode(), forcePhoneOnlyMode = forcePhoneOnlyMode(), lbPhoneEnabled = lbPhoneEnabled() } }
end)

lib.callback.register('twopoint_tow:phoneSetPhoneOnlyMode', function(source, data)
    local info = getDriverInfo(source)

    if forcePhoneOnlyMode() then
        info.phoneOnlyMode = true
    else
        info.phoneOnlyMode = data and data.enabled == true
    end

    sendPhoneAppUpdate(source)
    return {
        ok = true,
        forced = forcePhoneOnlyMode(),
        state = info.onDuty and buildTowQueueState(source) or {
            onDuty = false,
            phoneOnlyMode = defaultPhoneOnlyMode(),
            forcePhoneOnlyMode = forcePhoneOnlyMode()
        }
    }
end)

lib.callback.register('twopoint_tow:phoneAcceptCall', function(source, data)
    data = data or {}
    local result = acceptCallFromQueueForDriver(source, data.callId)
    result.state = buildTowQueueState(source)
    return result
end)

-------------------------------------------------
-- Commands
-------------------------------------------------

RegisterCommand('towduty', function(source, args)
    local src = source
    local info = getDriverInfo(src)

    if info.onDuty then
        setTowDutyOff(src)
        return
    end

    if #args < 1 then
        notify(src, "Usage: /towduty [company] <password>", "error")
        return
    end

    local password = args[#args]
    local requestedCompany = "Tow"
    if #args > 1 then
        requestedCompany = table.concat(args, " ", 1, #args - 1)
    end

    local valid, errorMessage, company = validateDutyLogin(requestedCompany, password)
    if not valid then
        notify(src, errorMessage or Config.Messages.wrongPassword or "Invalid tow duty password.", "error")
        return
    end

    setTowDutyOn(src, company or "Tow", false)
end, false)

-------------------------------------------------
-- Events - civilian call / cancel
-------------------------------------------------

RegisterNetEvent('twopoint_tow:requestTow', function(data)
    local src = source

    local onDuty, idle = getTowCounts()
    if onDuty == 0 then
        notify(src, Config.Messages.noTowUnitsWorking or "No tow trucks working currently.", "error")
        return
    end

    local existing = getCallByRequester(src)
    if existing then
        notify(src, Config.Messages.alreadyHasCall or "You already have an active tow request.", "error")
        return
    end

    callIdCounter = callIdCounter + 1
    local id = callIdCounter

    local coords = data.coords or {}
    local x, y, z = coords.x or 0.0, coords.y or 0.0, coords.z or 0.0

    TowCalls[id] = {
        id = id,
        requester = src,
        callerName = GetPlayerName(src) or "Unknown",
        coords = { x = x, y = y, z = z },
        status = 'new',
        assignedDriver = nil,
        companyName = nil,
        declinedCompanies = {},
        createdAt = os.time(),
        lastCompanyChange = os.time()
    }

    notify(src, Config.Messages.towRequestCreated or "Tow request created. A tow truck is being dispatched.", "success")

    TriggerEvent('twopoint_tow:internalDispatchCall', id)
    broadcastPhoneAppUpdate()
end)

RegisterNetEvent('twopoint_tow:civilianCancelCall', function()
    local src = source
    local call = getCallByRequester(src)
    if not call then
        notify(src, Config.Messages.noActiveCall or "You do not have an active tow request.", "error")
        return
    end

    call.status = 'cancelled'
    dequeueCall(call.id)

    if call.assignedDriver then
        local driverInfo = getDriverInfo(call.assignedDriver)
        if driverInfo then
            driverInfo.busy = false
            if driverInfo.currentCallId == call.id then
                driverInfo.currentCallId = nil
            end
        end

        TriggerClientEvent('twopoint_tow:clearActiveCall', call.assignedDriver)
        notify(call.assignedDriver, Config.Messages.callCancelledByCivilian or "The civilian cancelled their tow request.", "info")
    end

    notify(src, Config.Messages.callCancelledCivilian or "You cancelled your tow request.", "info")

    tryAssignQueuedCalls()
end)

-------------------------------------------------
-- Events - driver responses
-------------------------------------------------

local function handleDriverCallResponse(src, callId, accepted)
    callId = tonumber(callId)
    local info = getDriverInfo(src)
    local call = callId and TowCalls[callId] or nil

    if not call or (call.status ~= 'offered' and call.status ~= 'new') then
        notify(src, Config.Messages.callTaken or "This tow call has already been handled.", "error")
        TriggerClientEvent('twopoint_tow:clearPrompt', src, callId)
        return { ok = false, error = Config.Messages.callTaken or "This tow call has already been handled." }
    end

    if call.offeredTo ~= src then
        notify(src, Config.Messages.callTaken or "This tow call has already been handled.", "error")
        TriggerClientEvent('twopoint_tow:clearPrompt', src, callId)
        return { ok = false, error = Config.Messages.callTaken or "This tow call has already been handled." }
    end

    TriggerClientEvent('twopoint_tow:clearPrompt', src, callId)

    if not accepted then
        info.busy = false
        if info.currentCallId == callId then
            info.currentCallId = nil
        end

        notify(src, Config.Messages.callRejectedDriver or "You rejected the tow call.", "info")

        call.declinedCompanies = call.declinedCompanies or {}
        if call.companyName then
            call.declinedCompanies[call.companyName] = true
        end
        call.offeredTo = nil
        call.status = 'queued'

        sendPhoneAppUpdate(src)
        broadcastPhoneAppUpdate()
        TriggerEvent('twopoint_tow:internalDispatchCall', callId)
        return { ok = true }
    end

    call.status = 'assigned'
    call.assignedDriver = src
    call.offeredTo = nil
    info.busy = true
    info.currentCallId = callId

    local requester = call.requester
    if requester then
        notify(requester, Config.Messages.callAcceptedCivilian or "A tow truck is en-route.", "success")
    end

    TriggerClientEvent('twopoint_tow:callAssigned', src, {
        id = call.id,
        coords = call.coords
    })

    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()
    return { ok = true }
end

RegisterNetEvent('twopoint_tow:respondToCall', function(callId, accepted)
    handleDriverCallResponse(source, callId, accepted)
end)

RegisterNetEvent('twopoint_tow:phoneNotificationAccept', function(data)
    handleDriverCallResponse(source, data and data.callId, true)
end)

RegisterNetEvent('twopoint_tow:phoneNotificationReject', function(data)
    handleDriverCallResponse(source, data and data.callId, false)
end)

lib.callback.register('twopoint_tow:phoneRespondToOffer', function(source, data)
    data = data or {}
    local result = handleDriverCallResponse(source, data.callId, data.accept == true)
    result.state = getDriverInfo(source).onDuty and buildTowQueueState(source) or { onDuty = false }
    return result
end)

RegisterNetEvent('twopoint_tow:driverCancelCall', function()
    local src = source
    local info = getDriverInfo(src)
    local callId = info.currentCallId
    if not callId then
        notify(src, Config.Messages.driverNoActiveCall or "You do not have an active tow call.", "error")
        return
    end

    local call = TowCalls[callId]
    if not call then
        info.busy = false
        info.currentCallId = nil
        return
    end

    call.status = 'queued'
    call.assignedDriver = nil
    call.offeredTo = nil

    info.busy = false
    info.currentCallId = nil

    notify(src, Config.Messages.callCancelledDriver or "You cancelled the tow assignment.", "info")
    TriggerClientEvent('twopoint_tow:clearActiveCall', src)
    if call.requester then
        notify(call.requester, Config.Messages.callDriverLost or "Your tow driver is no longer available, your call has been re-queued.", "info")
    end

    queueCall(callId)
    TriggerEvent('twopoint_tow:internalDispatchCall', callId)
    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()
end)

RegisterNetEvent('twopoint_tow:driverArrived', function(callId)
    local src = source
    local info = getDriverInfo(src)
    local call = TowCalls[callId]

    if not call or call.assignedDriver ~= src then
        return
    end

    call.status = 'completed'
    dequeueCall(callId)

    info.busy = false
    if info.currentCallId == callId then
        info.currentCallId = nil
    end

    notify(src, Config.Messages.towArrivedDriver or "Tow call completed.", "success")
    if call.requester then
        notify(call.requester, Config.Messages.towArrivedCivilian or "Your tow truck has arrived.", "success")
    end

    tryAssignQueuedCalls()
    sendPhoneAppUpdate(src)
    broadcastPhoneAppUpdate()
end)

-------------------------------------------------
-- Player lifecycle
-------------------------------------------------

AddEventHandler('playerDropped', function(reason)
    local src = source
    local info = TowDrivers[src]
    if not info then return end

    if info.currentCallId then
        local call = TowCalls[info.currentCallId]
        if call and (call.status == 'assigned' or call.status == 'offered') then
            call.status = 'queued'
            call.assignedDriver = nil
            call.offeredTo = nil
            queueCall(call.id)
            if call.requester then
                notify(call.requester, Config.Messages.callDriverLost or "Your tow driver is no longer available, your call has been re-queued.", "info")
            end
        end
    end

    if info.onDuty then
        local session = addDutyTime(src)
        sendDutyWebhook(src, "Off", info.companyName, session)
    end

    TowDrivers[src] = nil
    refreshCompanies()
    broadcastAvailability()
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        loadStats()
        refreshCompanies()
        broadcastAvailability()
        print("[TwoPoint_TowDuty] Standalone Tow Duty started.")
    end
end)

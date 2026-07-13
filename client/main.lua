local activeCallId = nil
local activeCallCoords = nil
local activeTowRouteBlip = nil

local towAvailable = false

local function clearTowRoute()
    if activeTowRouteBlip and DoesBlipExist(activeTowRouteBlip) then
        SetBlipRoute(activeTowRouteBlip, false)
        RemoveBlip(activeTowRouteBlip)
    end
    activeTowRouteBlip = nil
end

local function setTowRoute(coords)
    clearTowRoute()

    if not coords or (Config.TowRoute and Config.TowRoute.enabled == false) then
        return
    end

    local routeCfg = Config.TowRoute or {}
    local x = coords.x + 0.0
    local y = coords.y + 0.0
    local z = (coords.z or 0.0) + 0.0

    if routeCfg.setWaypoint ~= false then
        SetNewWaypoint(x, y)
    end

    if routeCfg.createBlip ~= false then
        activeTowRouteBlip = AddBlipForCoord(x, y, z)
        SetBlipSprite(activeTowRouteBlip, routeCfg.sprite or 68)
        SetBlipDisplay(activeTowRouteBlip, 4)
        SetBlipScale(activeTowRouteBlip, routeCfg.scale or 0.9)
        SetBlipColour(activeTowRouteBlip, routeCfg.colour or 5)
        SetBlipAsShortRange(activeTowRouteBlip, false)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(routeCfg.label or "Tow Call")
        EndTextCommandSetBlipName(activeTowRouteBlip)

        if routeCfg.useBlipRoute ~= false then
            SetBlipRoute(activeTowRouteBlip, true)
            SetBlipRouteColour(activeTowRouteBlip, routeCfg.routeColour or routeCfg.colour or 5)
        end
    end
end
local currentRotationCompany = nil

local promptCallId = nil
local promptEndTime = 0
local tabletOpen = false

local function showNotify(text, nType)
    if not lib then return end
    lib.notify({
        title = Config.Notify.title,
        description = text,
        type = nType or 'info',
        position = Config.Notify.position,
        duration = Config.Notify.duration
    })
end

local function refreshTowAvailability()
    if not lib then return end

    local result = lib.callback.await('twopoint_tow:getAvailability', false)
    if type(result) == 'table' then
        towAvailable = result.available == true
    else
        towAvailable = result == true
    end
end

CreateThread(function()
    local refreshMs = ((Config.Target or {}).availabilityRefreshMs or 30000)
    if refreshMs < 5000 then refreshMs = 5000 end

    Wait(2500)
    while true do
        refreshTowAvailability()
        Wait(refreshMs)
    end
end)

local lbPhoneAppRegistered = false

local function getLBPhoneResource()
    return (Config.LBPhone and Config.LBPhone.resource) or "lb-phone"
end

local function getLBPhoneAppIdentifier()
    return (Config.LBPhone and Config.LBPhone.appIdentifier) or "twopoint_tow"
end

local function lbPhoneAvailable()
    return Config.LBPhone
        and Config.LBPhone.enabled
        and GetResourceState(getLBPhoneResource()) == "started"
end

local function sendPhoneAppMessage(payload)
    if not lbPhoneAppRegistered or not lbPhoneAvailable() then return false end

    local ok, err = pcall(function()
        exports[getLBPhoneResource()]:SendCustomAppMessage(getLBPhoneAppIdentifier(), payload)
    end)

    if not ok then
        print("[TwoPoint_TowDuty] LB Phone app message failed: " .. tostring(err))
        return false
    end

    return true
end

local function sendTowPhoneState()
    if not lbPhoneAvailable() or not lib then return end

    local state = lib.callback.await('twopoint_tow:phoneGetState', false)
    sendPhoneAppMessage({
        action = "state",
        state = state or {}
    })
end

local function sendSupervisorPhoneState()
    if not lbPhoneAvailable() or not lib then return end

    local state = lib.callback.await('twopoint_tow:supervisorGetState', false)
    sendPhoneAppMessage({
        action = "supervisorState",
        state = state or {}
    })
end

local function sendAllTowPhoneState()
    sendTowPhoneState()
    sendSupervisorPhoneState()
end

local function registerLBPhoneApp()
    if lbPhoneAppRegistered or not lbPhoneAvailable() then return end

    Wait(500)

    local cfg = Config.LBPhone or {}
    local appId = getLBPhoneAppIdentifier()
    local resourceName = GetCurrentResourceName()

    local success, errorMessage = exports[getLBPhoneResource()]:AddCustomApp({
        identifier = appId,
        name = cfg.appName or "Tow Duty",
        description = cfg.appDescription or "Tow duty and call queue.",
        developer = cfg.developer or "TwoPoint Development",
        defaultApp = cfg.defaultApp ~= false,
        price = cfg.price or 0,
        ui = resourceName .. "/phone/index.html",
        icon = "https://cfx-nui-" .. resourceName .. "/phone/icon.png",
        fixBlur = true,
        onOpen = function()
            CreateThread(function()
                Wait(250)
                sendAllTowPhoneState()
            end)
        end
    })

    if not success then
        print(("[TwoPoint_TowDuty] Failed to add LB Phone app: %s"):format(errorMessage or "unknown error"))
        return
    end

    lbPhoneAppRegistered = true
    print("[TwoPoint_TowDuty] LB Phone Tow Duty app registered.")
end

CreateThread(function()
    if not Config.LBPhone or not Config.LBPhone.enabled then return end

    local timeout = GetGameTimer() + 30000
    while GetGameTimer() < timeout do
        if lbPhoneAvailable() then
            registerLBPhoneApp()
            return
        end
        Wait(1000)
    end

    print("[TwoPoint_TowDuty] LB Phone not detected; phone app integration skipped.")
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == getLBPhoneResource() then
        CreateThread(function()
            Wait(1500)
            registerLBPhoneApp()
        end)
    end
end)

RegisterNetEvent('twopoint_tow:phoneAppUpdate', function()
    sendTowPhoneState()
end)

RegisterNetEvent('twopoint_tow:phoneSupervisorUpdate', function()
    sendSupervisorPhoneState()
end)

local function fetchTowQueue()
    local result = lib.callback.await('twopoint_tow:getQueue', false)
    if not result then
        showNotify("Unable to fetch tow queue.", "error")
        return nil
    end

    if result.error then
        showNotify(result.error, "error")
        return nil
    end

    return result
end

local function sendTowQueueData()
    local result = fetchTowQueue()
    if not result then return false end

    SendNUIMessage({
        action = "setQueue",
        calls = result.calls or {},
        busy = result.busy or false,
        companyName = result.companyName or "Tow"
    })

    return true
end

local function openTowTablet()
    if not lib then
        print("[TwoPoint_TowDuty] ox_lib not available for towtablet.")
        return
    end

    local result = fetchTowQueue()
    if not result then return end

    tabletOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "open",
        calls = result.calls or {},
        busy = result.busy or false,
        companyName = result.companyName or "Tow"
    })
end

local function closeTowTablet()
    tabletOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
end

-- Availability + rotation info from server (for UI if you ever want it)
RegisterNetEvent('twopoint_tow:updateAvailability', function(available)
    towAvailable = available
end)

RegisterNetEvent('twopoint_tow:updateRotationCompany', function(company)
    currentRotationCompany = company
end)

-- Popup when a new call is offered to this driver
RegisterNetEvent('twopoint_tow:promptCall', function(callId, coords, callerName, timeoutMs, distance)
    if promptCallId then return end

    if Config.CallChime and Config.CallChime.enabled then
        PlaySoundFrontend(
            -1,
            Config.CallChime.soundName or "Event_Start_Text",
            Config.CallChime.soundSet or "HUD_FRONTEND_DEFAULT_SOUNDSET",
            true
        )
    end

    promptCallId = callId
    promptEndTime = GetGameTimer() + (timeoutMs or Config.AcceptTime or 15000)

    local msg = ('New Tow Call from %s\nDistance: %.1fm\n\n[E] Accept    [X] Reject'):format(
        callerName or "Unknown",
        distance or 0.0
    )

    lib.showTextUI(msg, {
        position = "top-center",
        icon = "truck-pickup",
        style = {
            borderRadius = 4,
            backgroundColor = "#111111",
            color = "white"
        }
    })

    CreateThread(function()
        while promptCallId == callId and GetGameTimer() < promptEndTime do
            if IsControlJustReleased(0, 38) then -- E
                lib.hideTextUI()
                promptCallId = nil
                TriggerServerEvent('twopoint_tow:respondToCall', callId, true)
                break
            elseif IsControlJustReleased(0, 73) then -- X
                lib.hideTextUI()
                promptCallId = nil
                TriggerServerEvent('twopoint_tow:respondToCall', callId, false)
                break
            end
            Wait(0)
        end

        if promptCallId == callId then
            lib.hideTextUI()
            promptCallId = nil
        end
    end)
end)

RegisterNetEvent('twopoint_tow:clearPrompt', function(callId)
    if not callId or callId == promptCallId then
        lib.hideTextUI()
        promptCallId = nil
    end
end)

RegisterNetEvent('twopoint_tow:clearAllPrompts', function()
    lib.hideTextUI()
    promptCallId = nil
end)

-- When a call has been fully assigned to this driver
RegisterNetEvent('twopoint_tow:callAssigned', function(callData)
    activeCallId = callData.id
    activeCallCoords = callData.coords

    if activeCallCoords then
        setTowRoute(activeCallCoords)
    end

    showNotify(Config.Messages.callAcceptedDriver or "Tow call assigned.", "success")

    if tabletOpen then
        sendTowQueueData()
    end
    sendTowPhoneState()

    CreateThread(function()
        while activeCallId == callData.id and activeCallCoords do
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dist = #(coords - vector3(activeCallCoords.x, activeCallCoords.y, activeCallCoords.z))

            if dist <= (Config.ArrivalRadius or 20.0) then
                TriggerServerEvent('twopoint_tow:driverArrived', activeCallId)
                activeCallId = nil
                activeCallCoords = nil
                clearTowRoute()
                break
            end

            Wait(1000)
        end
    end)
end)

RegisterNetEvent('twopoint_tow:clearActiveCall', function()
    activeCallId = nil
    activeCallCoords = nil
    clearTowRoute()
    sendTowPhoneState()
end)

-- Generic notify from server
RegisterNetEvent('twopoint_tow:notify', function(payload)
    if type(payload) == "string" then
        showNotify(payload, "info")
    else
        if not payload.title then
            payload.title = Config.Notify.title
        end
        if not payload.position then
            payload.position = Config.Notify.position
        end
        if not payload.duration then
            payload.duration = Config.Notify.duration
        end
        lib.notify(payload)
    end
end)

-- ox_target setup - civilians can third eye ANY vehicle to call tow
CreateThread(function()
    Wait(1000)

    if not exports.ox_target then
        print("[TwoPoint_TowDuty] ox_target not found, target integration disabled.")
        return
    end

    refreshTowAvailability()

    local targetCfg = Config.Target or {}
    local targetDistance = targetCfg.distance or 2.5

    exports.ox_target:addGlobalVehicle({
        {
            name = 'twopoint_calltow',
            icon = targetCfg.callTowIcon or 'fa-solid fa-truck-pickup',
            label = targetCfg.callTowLabel or 'Call Tow',
            distance = targetDistance,
            canInteract = function(entity, distance, coords, name)
                return towAvailable == true
            end,
            onSelect = function(data)
                local veh = data.entity
                if not DoesEntityExist(veh) then return end

                local coords = GetEntityCoords(veh)
                local plate = GetVehicleNumberPlateText(veh)
                local model = GetEntityModel(veh)
                local primaryColour, secondaryColour = GetVehicleColours(veh)

                TriggerServerEvent('twopoint_tow:requestTow', {
                    coords = { x = coords.x, y = coords.y, z = coords.z },
                    vehicleNetId = NetworkGetNetworkIdFromEntity(veh),
                    plate = plate,
                    model = model,
                    primaryColour = primaryColour,
                    secondaryColour = secondaryColour,
                    sourceType = 'target'
                })
            end
        },
        {
            name = 'twopoint_no_tow_available',
            icon = targetCfg.noTowAvailableIcon or 'fa-solid fa-circle-xmark',
            label = targetCfg.noTowAvailableLabel or 'No Tow Available',
            distance = targetDistance,
            canInteract = function(entity, distance, coords, name)
                return towAvailable ~= true
            end,
            onSelect = function(data)
                showNotify(Config.Messages.noTowUnitsWorking or "No tow trucks working currently.", "error")
            end
        }
    })
end)

-- /calltow from current player position (no vehicle required)
RegisterCommand('calltow', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    TriggerServerEvent('twopoint_tow:requestTow', {
        coords = { x = coords.x, y = coords.y, z = coords.z },
        vehicleNetId = 0,
        plate = nil,
        model = 0,
        sourceType = 'command'
    })
end, false)

-- Tow driver cancels their current assignment
RegisterCommand('canceltow', function()
    TriggerServerEvent('twopoint_tow:driverCancelCall')
end, false)

-- Civilian cancels their active tow request
RegisterCommand('canceltowcall', function()
    TriggerServerEvent('twopoint_tow:civilianCancelCall')
end, false)

-- Movable tow queue tablet
RegisterCommand('towtablet', openTowTablet, false)
RegisterCommand('towqueue', openTowTablet, false)

RegisterNUICallback('close', function(_, cb)
    closeTowTablet()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    local ok = sendTowQueueData()
    cb({ ok = ok })
end)

RegisterNUICallback('acceptCall', function(data, cb)
    local callId = tonumber(data and data.callId)
    if not callId then
        cb({ ok = false, error = "Invalid call id." })
        return
    end

    local result = lib.callback.await('twopoint_tow:acceptCallFromQueue', false, callId)
    if not result or not result.ok then
        local err = result and result.error or "Unable to accept tow call."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        sendTowQueueData()
        return
    end

    cb({ ok = true })
    sendTowQueueData()
end)

RegisterNUICallback('phoneGetState', function(_, cb)
    local state = lib.callback.await('twopoint_tow:phoneGetState', false)
    cb(state or {})
end)

RegisterNUICallback('phoneLogin', function(data, cb)
    local result = lib.callback.await('twopoint_tow:phoneLogin', false, data or {})
    if not result or not result.ok then
        local err = result and result.error or "Unable to sign in."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        return
    end

    cb(result)
    sendTowPhoneState()
end)

RegisterNUICallback('phoneLogout', function(_, cb)
    local result = lib.callback.await('twopoint_tow:phoneLogout', false)
    cb(result or { ok = true })
    sendTowPhoneState()
end)

RegisterNUICallback('phoneSetPhoneOnlyMode', function(data, cb)
    local result = lib.callback.await('twopoint_tow:phoneSetPhoneOnlyMode', false, data or {})
    cb(result or { ok = false })
    sendTowPhoneState()
end)

RegisterNUICallback('supervisorGetState', function(_, cb)
    local state = lib.callback.await('twopoint_tow:supervisorGetState', false)
    cb(state or {})
end)

RegisterNUICallback('supervisorLogin', function(data, cb)
    local result = lib.callback.await('twopoint_tow:supervisorLogin', false, data or {})
    if not result or not result.ok then
        local err = result and result.error or "Unable to sign in as supervisor."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        return
    end

    cb(result)
    sendAllTowPhoneState()
end)

RegisterNUICallback('supervisorLogout', function(_, cb)
    local result = lib.callback.await('twopoint_tow:supervisorLogout', false)
    cb(result or { ok = true })
    sendSupervisorPhoneState()
end)

RegisterNUICallback('supervisorUpdateCompany', function(data, cb)
    local result = lib.callback.await('twopoint_tow:supervisorUpdateCompany', false, data or {})
    if not result or not result.ok then
        local err = result and result.error or "Unable to update company settings."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        return
    end

    cb(result)
    sendAllTowPhoneState()
end)

RegisterNUICallback('phoneAcceptCall', function(data, cb)
    local result = lib.callback.await('twopoint_tow:phoneAcceptCall', false, data or {})
    if not result or not result.ok then
        local err = result and result.error or "Unable to accept tow call."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        sendTowPhoneState()
        return
    end

    cb(result)
    sendTowPhoneState()
end)

RegisterNUICallback('phoneRespondToOffer', function(data, cb)
    local result = lib.callback.await('twopoint_tow:phoneRespondToOffer', false, data or {})
    if not result or not result.ok then
        local err = result and result.error or "Unable to update tow call."
        showNotify(err, "error")
        cb({ ok = false, error = err })
        sendTowPhoneState()
        return
    end

    cb(result)
    sendTowPhoneState()
end)

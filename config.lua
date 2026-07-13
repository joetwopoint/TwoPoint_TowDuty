Config = {}

Config.Debug = false

-- Tow company passwords, supervisor passwords, and supervisor identifiers are
-- stored in server_config.lua so they are never downloaded to players.

Config.Notify = {
    title = "Tow Service",
    position = "top-right",
    duration = 7000
}

-- How long (ms) a tow driver has to accept/reject a call popup
Config.AcceptTime = 15000

-- Distance (m) at which the driver is considered "arrived"
Config.ArrivalRadius = 20.0

-- ox_target / third-eye tow request labels.
-- The visible option changes based on whether any tow driver is on duty.
Config.Target = {
    distance = 2.5,

    callTowLabel = "Call Tow",
    callTowIcon = "fa-solid fa-truck-pickup",

    noTowAvailableLabel = "No Tow Available",
    noTowAvailableIcon = "fa-solid fa-circle-xmark",

    -- Fallback refresh in case a client misses the server availability event.
    availabilityRefreshMs = 30000
}

-- Route/waypoint created for the tow driver after accepting a call.
Config.TowRoute = {
    enabled = true,
    setWaypoint = true,      -- creates the GPS waypoint
    createBlip = true,       -- creates a map blip with an active GPS route
    label = "Tow Call",
    sprite = 68,             -- tow/vehicle-style blip
    colour = 5,              -- yellow
    scale = 0.9,
    routeColour = 5
}

-- If a call sits with a company for longer than this (seconds) without
-- being accepted, it can be rotated to the next company.
Config.CompanyTimeoutSeconds = 120

-- Little chime when a call is offered to a tow driver
Config.CallChime = {
    enabled = true,
    soundName = "Event_Start_Text",
    soundSet = "HUD_FRONTEND_DEFAULT_SOUNDSET"
}

Config.Messages = {
    dutyOnCompany           = "You are now on Tow Duty with %s.",
    dutyOff                 = "You are now off Tow Duty.",
    wrongPassword           = "Invalid tow duty company name or password.",
    supervisorDenied        = "You are not authorized to manage that tow company.",
    supervisorWrongPassword = "Invalid supervisor password.",
    companyUpdated          = "Tow company settings updated.",
    unknownCompany          = "Unknown tow company.",
    notOnDuty               = "You are not on tow duty.",
    noTowUnitsWorking       = "No tow trucks working currently.",
    alreadyHasCall          = "You already have an active tow request.",
    towRequestCreated       = "Tow request created. A tow truck is being dispatched.",
    towRequestQueued        = "All Tow units are busy. Your request has been queued.",
    callAcceptedDriver      = "Tow call assigned.",
    callAcceptedCivilian    = "A tow truck is en-route.",
    callRejectedDriver      = "You rejected the tow call.",
    callTimedOut            = "You did not respond to the tow call in time.",
    callTaken               = "This tow call has already been handled.",
    driverNoActiveCall      = "You do not have an active tow call.",
    noActiveCall            = "You do not have an active tow request.",
    callCancelledDriver     = "You cancelled the tow assignment.",
    callCancelledByCivilian = "The civilian cancelled their tow request.",
    callCancelledCivilian   = "You cancelled your tow request.",
    callDriverLost          = "Your tow driver is no longer available, your call has been re-queued.",
    towArrivedDriver        = "Tow call completed.",
    towArrivedCivilian      = "Your tow truck has arrived."
}

-- Webhook for duty on/off + time tracking
Config.Webhooks = {
    Duty = "" -- put your Discord webhook here
}

-- Optional LB Phone integration.
-- Requires lb-phone to be started before this resource.
Config.LBPhone = {
    enabled = true,
    resource = "lb-phone",
    appIdentifier = "twopoint_tow",
    appName = "Tow Duty",
    appDescription = "Tow duty sign-in, call queue, and call alerts.",
    developer = "TwoPoint Development",
    defaultApp = true,
    price = 0,

    -- If true, drivers who sign in through the phone app default to phone-only alerts.
    -- This hides the top-center accept/reject prompt for those phone-duty drivers.
    phoneOnlyModeDefault = true,

    -- If true, the phone-only setting is locked on and the app cannot toggle it off.
    -- With this enabled, phone-duty drivers will only get lb-phone notifications/app alerts,
    -- and the script will not fall back to the on-screen prompt if lb-phone notification fails.
    forcePhoneOnlyMode = true,

    -- If true, LB Phone notifications are only sent to drivers who signed in
    -- through the Tow Duty phone app. Drivers using /towduty keep the normal
    -- on-screen prompt flow unless you disable /towduty separately.
    notificationsRequirePhoneDuty = true
}


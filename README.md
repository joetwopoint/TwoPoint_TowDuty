# TwoPoint_TowDuty (Standalone)

Standalone tow duty + queue system using **ox_lib** and **ox_target**.

## Dependencies

- ox_lib
- ox_target

## Installation

1. Drop the `TwoPoint_TowDuty` folder into your resources.
2. In `server.cfg` (order is important):

   ```
   ensure ox_lib
   ensure ox_target
   ensure TwoPoint_TowDuty
   ```

3. Edit `config.lua`:
   - Set private company names/passwords and default random-company passwords in `Config.TowDutyAuth`.
   - Optional: set `Config.Webhooks.Duty` for Discord logging.


## Tow company passwords

`config.lua` supports both private company logins and the original on-the-fly company behavior:

```lua
Config.TowDutyAuth = {
    Companies = {
        ["SADOT"] = "sadot123",
        ["Los Santos Towing"] = "lstow123"
    },

    AllowRandomCompanyNames = true,
    DefaultPasswords = {
        "tow123"
    }
}
```

How it works:

- If a driver enters a configured/private company name, they must use that company's password.
  - Example: `/towduty SADOT sadot123`
- If a driver enters a company name that is not configured, the script keeps the old behavior and allows them in with a default password.
  - Example: `/towduty Random Tow tow123`
- Set `AllowRandomCompanyNames = false` if you only want configured/private companies to be allowed.
- Company-name checks are case-insensitive, but the configured casing is used for display.

## Commands

- `/towduty [company] <password>`
  - Clock **on** with a company name and password:
    - Example: `/towduty SADOT tow123`
  - If you are already on duty, `/towduty` again **clocks you off** (no password needed).

- `/calltow`
  - Civilian tow request at your current location.

- `/canceltowcall`
  - Civilian cancels their active tow request.

- `/canceltow`
  - Tow driver cancels their current assignment (call is re-queued).

- `/towtablet`
  - On-duty drivers see a simple queue overview using an ox_lib context menu.

## ox_target

Any vehicle can be third-eyed and will show a **"Call Tow"** option.
The server checks if any tow units are on duty:

- If none → player sees `No tow trucks working currently.` and no call is created.
- If at least one → call enters the queue / rotation system.

## Features

- Password-protected duty system with per-company names.
- Each driver may only have **one active call**.
- Smart queue:
  - Calls are queued when all drivers are busy.
  - When a driver clears their job, queued calls are re-dispatched.
- Company rotation:
  - Calls are first assigned to companies in rotation order.
  - If a company rejects a call, it is automatically passed to the next company
    (without going back to the one that rejected it).
- 15s accept/reject popup with keybinds:
  - **E** = Accept
  - **X** = Reject
- Waypoint & auto-arrival:
  - When a driver accepts, a waypoint is set.
  - When they get within `Config.ArrivalRadius` meters, the call auto-completes.
- Duty webhooks (optional):
  - Logs on/off with session time and total duty time.


## LB Phone App (optional)

This version includes an optional **lb-phone** custom app.

Server start order:

```
ensure ox_lib
ensure ox_target
ensure lb-phone
ensure TwoPoint_TowDuty
```

The app is registered automatically when `lb-phone` is running and `Config.LBPhone.enabled = true`.
Drivers open the **Tow Duty** phone app, enter a company name and the duty password, then sign in.

Phone app behavior:

- Phone sign-in clocks the driver onto tow duty.
- Phone notifications are only sent to drivers who signed in through the phone app.
- The **Phone-only alerts** toggle hides the top-center on-screen accept/reject prompt and sends call offers through LB Phone notifications/app controls instead.
- Drivers can accept or reject incoming offers inside the app.
- Drivers can view and accept eligible queued calls inside the app.

- Uses the included black/yellow Tow Duty app icon (`phone/icon.png`) for the LB Phone app tile and sign-in screen.

Drivers using `/towduty [company] <password>` still get the normal on-screen prompt flow.

### Tow route / GPS

When a tow driver accepts a call, the script now creates a GPS waypoint and an active route blip to the vehicle needing tow. Configure it in `Config.TowRoute`. The route/blip is cleared when the driver arrives, cancels, or the call is cancelled.

### Phone-only config

For LB Phone-only operation, keep:

```lua
Config.LBPhone.enabled = true
Config.LBPhone.phoneOnlyModeDefault = true
Config.LBPhone.forcePhoneOnlyMode = true
Config.LBPhone.notificationsRequirePhoneDuty = true
```

With `forcePhoneOnlyMode = true`, phone-duty drivers do not get the top-center on-screen accept/reject prompt, and the app toggle is locked on.


## v1.7.0

- Fixed LB Phone app black-screen issue by registering the custom app UI with the full resource-qualified path (`GetCurrentResourceName() .. "/phone/index.html"`), matching LB Phone's vanilla template pattern.
- Kept phone sign-in, phone-only alerts, configured company passwords, default/random company passwords, app notifications, queue, and route/blip features intact.


## v1.8.0

- Restyled the LB Phone Tow Duty app to match the earlier polished preview more closely while keeping the black/gold color theme from the in-game screenshot.
- Lowered the app content inside the phone so the sign-in and duty screens do not sit too high under the phone status bar.
- Applied the same color/card/button style across sign-in, duty, incoming call, and queue screens.

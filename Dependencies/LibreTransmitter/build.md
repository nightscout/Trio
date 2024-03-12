NB! This project requires LoopWorkspace dev. You *must* use the workspace to buid this.

## Start with a clean LoopWorkspace based on dev

* Download a fresh copy of LoopWorkspace dev, which now includes the LibreTransmitter module by default.
  
## Give Loop Extra background permissions
 The LibreTransmitter plugin will run as a part of Loop. If you want LibreTransmitter to be able to give vibrations for low/high glucose, this is a necessary step
* In Xcode, Open the Loop Project (not the LibreTransmitter project) in the navigator, go to "Signing & Capabilities", then under "background modes", select "Audio, AirPlay, and Picture in picture". This will allow Libretransmitter to use vibration when the phone is locked.
* It should look like this: ![Loop_xcodeproj](https://user-images.githubusercontent.com/442324/111884302-14777a80-89c1-11eb-9171-76ffcef2f345.jpg "Audio/Vibrate capability added into Loop For libretransmitter to work in background")
* In code, search for and set glucoseAlarmsAlsoCauseVibration to true



## Give Libretransmitter Critical Alerts permissions
Libretransmitter will by default send alarms as "timesensitve", appearing immediately on the lock screen.
If you mute or set your phone to do not disturb, you can potentially miss out on such alarms.
To remedy this, LibreTransmitter can be configured to try to upgrade any glucose alarms to "critical". 
Critical alarms will sound even if your phone is set to to mute or "do not disturb" mode.

For this to be possible, you will have to request special permissions from Apple.
This process is documented at https://stackoverflow.com/questions/66057840/ios-how-do-you-implement-critical-alerts-for-your-app-when-you-dont-have-an-en . 
The linked article describes some necessary code changes, but the code changes mentioned there should be ignored as the necessary code changes are already in place for Libretransmitter. 

For critical alerts to function, a custom provisioning profile must be selected. This is typically the provisioning profile you get after a successful application to Apple

It's worth mentioning again that those permissions must be given to Loop itself, not to the LibreTransmitter package. The
com.apple.developer.usernotifications.critical-alerts permission must be added to Loop/Loop.entitlement file in the Loop folder (not inside LibreTransmitter

Next, choose one of these two methods to enable this feature:


### Method 1
Using this method, only the LibreTransmitter cgm alarms can become critical

You should only change the shouldOverrideRequestCriticalPermissions toggle in the NotificationHelperOverride.swift file to true, like this:

```swift
enum NotificationHelperOverride {
    static var shouldOverrideRequestCriticalPermissions : Bool {
        // if you want LibreTransmitter to try upgrading to critical notifications, change this
        true
    }
}

```
### Method 2
Using this method, both Loop pump, cgm alarms and LibreTransmitter alarms will become critical

Go to the Loop Project (not target)→Build settings → Swift Compiler → Custom flags → Other swift flags section and edit the different configuration flags. Add the flag “CRITICAL_ALERTS_ENABLED” (without the quotes).

## Build the LoopWorkspace 
* In xcode, build the LoopWorkspace as normal

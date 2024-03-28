# FAQ

## fffHow to get the Medtronic pump ready?

- Set your temporary basal to units (not percents!).
- Turn on the remote control with any ID (for example 00000).

## Can I use Bolus assistant on a Medtronic pump?

- You may, but you shouldn't to avoid control conflicts.
- Carbs, entered through the bolus assistant on pump won't be counted in FreeAPS X.
- Insulin, delivered through the bolus assistant on pump will be counted in FreeAPS X

## Does the insulin model affect anything when connecting the pump?

- No. This is a legacy screen of rileylink_ios library.
- You can change an actual insulin type in Preferences -> Insulin Curve. Ultra-rapid for Fiast and Lyumjev, rapid-acting for others.

## Can we manually set TBR?

- Yes. For that you need to open the loop in settings and the button will appear on the main screen.

## How to run the loop on demand manually?

- There is no way of doing that. You can force the data update by long-tapping the loop icon. If this actions gets any new data, loop will be recalculated.

## How to get BG values from Spike/Diabox?

- Settings -> Nightscout -> Use Local Glucose Server, and set the port of a local server. Spike - 1979, Diabox - 17580

## How to see raw data that is used inside the app?

- Preferences -> Edit settings json. Set "debugOptions": true, and restart the app.
- In Files application on iPhone.
- You can also download all the data to your computer through iTunes or Finder.


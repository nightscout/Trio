# FAQs

## General FAQs
<details>

<summary><b>Is Open-iAPS using my profile ISF, Autotuned ISF, Autosens ISF, or Dynamic ISF?</b></summary>
This depends on which settings you currently have enabled. 

Autotune and the Dynamic ISF are disabled with the default settings. In this case, Autosens will start changing your ISF profile when it has enough data. 

When enabled, Autotune runs each night, creating separate Autotune profiles that are then adjusted with Autosens. 

The order of adjustment is Profile ISF -> Autotune -> Autosens / Dynamic ISF.
</details>

<details>
<summary><b>What is the difference between a Temp Target (TT) and a Profile?</b></summary>
Think of Profiles as your new defaults or pump settings, used for shorter or longer periods or always like your normal profile. There isn’t any hard-coded limit to the duration of profiles when the duration is set to indefinitely. 

Think of temporary targets as a temporary change that could be used on top of a custom profile. 

TT is only changing your target glucose. Under certain conditions, when combined with certain settings, it will adjust your current basal rate. When combined with a profile, the target glucose set with TT dominates the profile’s target glucose. 

Profiles can change ISF, CR, basal rates, SMB basal minutes, UAM basal minutes, target glucose, and SMBs. You can also schedule when SMBs are on or off during the day. Profiles can be used for shorter temporary changes or indefinitely un-l you return to your normal profile. In short, Profiles can do everything a TT can and much more. 
</details>

<details>

<summary><b>How do I make super micro boluses (SMBs) more aggressive?</b></summary>
SMBs are limited by your Max Basal Minutes settings. The 30-minute default is too conservative for most users, especially when coming from another AID system without limits for max auto bolus amount (Loop). 

Raising the basal minute setting will allow for bigger SMBs. 60 basal minutes means a max auto bolus of 1 hour of your current basal rate. If your basal rate is 1U/h, then 1U is the new max SMB amount. 

You need to decide for yourself how much you want to limit (or not limit) your SMBs.
</details>

<details>

<summary><b>Why isn’t Open-iAPS looping or delivering insulin when CGM glucose is 400 mg/dl (22 mmol/l) or higher?</b></summary>
Open-iAPS can’t determine the glucose value when over 400mg/dL (22 mmol/L). This is why the CGM apps from Dexcom and Libre display “High.” A “High” reading is also sometimes due to a sensor error or a faulty sensor needing replacement. 

Without knowing the glucose value or if it’s rising or falling, Open-iAPS can’t safely make a glucose prediction.
</details>

<details>

<summary><b>Why isn’t Open-iAPS looping when CGM glucose is 40 mg/dl (2.2 mmol/l) or lower?</b></summary>
Open-iAPS can’t determine the glucose value when under 40mg/dL (2.2 mmol/L). This is why the CGM apps from Dexcom and Libre are displaying “Low.” A “Low” reading is also sometimes due to a sensor error or a faulty sensor needing replacement. 

Without knowing the glucose value or if it’s rising or falling, Open-iAPS can’t safely make a glucose prediction.
</details>

## Autosens FAQs
<details>

<summary><b>Which settings are adjusted by Autosens?</b></summary>

Autosens is adjusting your ISF. Under certain conditions, Autosens will also adjust your target glucose and/or current basal rate. 

If you’re using Autotune, Autosens will adjust your autotuned ISF. If you’re not using Autotune, Autosens will adjust your profile ISF. 

Autosens can also sometimes adjust your target glucose, but only when you have one or both settings, `Sensitivity Raises Target` and `Resistance Lowers Target` enabled in Open-iAPS preferences.
</details>

## Autotune FAQs
<details>

<summary><b>Which settings are adjusted by Autotune (AT)?</b></summary>

Autotune is adjusting your profile ISF, CR, and profile basal rates. There’s an option to have Autotune adjust profile basal rates only.
</details>

<details>

<summary><b>How often is Autotune run?</b></summary>
Every 24 hours
</details>

## Other FAQs
<details>

<summary><b>How do I view my raw data that is used inside the app?</b></summary>

- `Settings` → `Debug Options` (toggle ON) → `Edit settings json`
- In the `Files` application on iPhone.
- You can also download all the data to your computer through iTunes or Finder.
</details>
  


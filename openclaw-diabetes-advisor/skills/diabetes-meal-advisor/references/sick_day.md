# Sick Day Management for T1D

Sources: ADA, ISPAD 2022, JDRF/Breakthrough T1D, CDC, NHS, IDF,
Dana Lewis (OpenAPS), Know Diabetes

## Cardinal Rule

**NEVER stop basal insulin, even if not eating.**

Stress hormones (cortisol, catecholamines, growth hormone) during illness increase
hepatic glucose output and decrease peripheral uptake. Stopping insulin triggers
rapid ketone production and DKA, which kills. Mealtime bolus may be reduced or
omitted, but basal must ALWAYS continue.

## Monitoring Frequency

- BG: every 1-2 hours (ISPAD) or 2-3 hours minimum
- Blood ketones: every 2-4 hours
- ALWAYS check ketones when BG >250 mg/dL
- ALWAYS check ketones when nausea/vomiting present, regardless of BG
- Blood ketone monitoring preferred over urine — urine ketones lag 6-8 hours

## Blood Ketone Action Thresholds

| Blood Ketones (mmol/L) | Risk Level | Action |
|------------------------|------------|--------|
| <0.6 | Normal | Continue monitoring |
| 0.6-0.9 | Slightly elevated | Extra fluids, check insulin delivery, recheck 1-2 hr |
| 1.0-1.4 | Moderate risk | Supplemental insulin (10% of TDD), aggressive hydration, recheck 1-2 hr |
| 1.5-2.9 | HIGH RISK | Give 15-20% of TDD, aggressive hydration, CONTACT HEALTHCARE TEAM or go to ER |
| ≥3.0 | DKA LIKELY | SEEK EMERGENCY CARE IMMEDIATELY |

## Fluid Guidelines

- BG >200 mg/dL: sugar-free fluids (water, broth, diet drinks)
- BG <200 mg/dL: sugar-containing fluids (to prevent starvation ketones + hypoglycemia)
- If vomiting: small sips of ~1 tablespoon every 5-10 minutes
- Dehydration accelerates DKA — hydration is a medical priority

## GI Illness (Vomiting/Diarrhea) — Special Danger

GI illness is uniquely dangerous because:
1. Cannot keep food down to prevent hypoglycemia
2. Stopping insulin risks DKA
3. EUGLYCEMIC DKA can occur — ketoacidosis at NORMAL blood glucose
4. Makes ketone monitoring essential regardless of BG level

Key interventions:
- Ondansetron (Zofran) should be prescribed proactively and kept on hand
- Mini-dose glucagon protocol if oral intake fails (see hypo_treatment.md)
- Consider reducing bolus insulin but maintain basal
- If unable to keep fluids down for >4 hours → ER

## Fever and Infection

- Typically increases insulin needs 10-50%
- ISPAD 2022: consider 10-20% basal increase for illness lasting ≥3 days
- Can increase up to 50% if needed
- Ketone-based supplemental dosing:
  - Ketones 0.6-1.5: give 10% of TDD
  - Ketones 1.5-3.0: give 15-20% of TDD
- Insulin needs normalize within 24-48 hours after fever breaks — taper gradually

## AID Systems During Illness

Generally beneficial — adjust insulin every 5 min in response to changing BG.
Dana Lewis documented OpenAPS maintaining 85-160 mg/dL through 5+ days of
norovirus without eating for 24+ hours.

However:
- CGM accuracy may degrade (dehydration, fever affect sensor readings)
- Require fingerstick confirmation when readings seem off
- No AID system monitors ketones — must be done manually
- CHANGE INFUSION SETS if BG unexpectedly high — site failure during illness
  is a leading cause of DKA in pump users

## When to Go to the ER

- Blood ketones ≥3.0 mmol/L
- Persistent vomiting (>4 hours, can't keep fluids down)
- Signs of DKA: fruity breath, rapid breathing, abdominal pain, confusion
- BG >300 mg/dL not responding to 2 correction doses
- Altered consciousness or inability to self-manage
- Moderate ketones (1.5+) not resolving after 2 hours of treatment

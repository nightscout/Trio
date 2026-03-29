# Exercise and T1D — Riddell et al. 2017 Consensus + ISPAD 2022

Primary source: Riddell et al. 2017, Lancet Diabetes Endocrinol 5(5):377-390 (JDRF, 21 experts)
Secondary: García-García et al. 2015 meta-analysis, ISPAD 2022, DirecNet (Tsalikian 2007)

## BG Response by Exercise Type

### Aerobic (running, cycling, swimming, walking)
- BG drops ~80 mg/dL/hour (95% CI: -109 to -50)
- Mechanism: insulin-independent GLUT4 translocation, up to 50x muscle glucose uptake
- Subcutaneous insulin cannot decrease fast enough to compensate
- Effects persist 24-48 hours post-exercise (glycogen replenishment)

### Anaerobic / Resistance (weightlifting, sprinting)
- BG typically RISES acutely from catecholamine release + hepatic glucose output
- Better glucose stability than continuous aerobic (-2.61 mmol/L/hr, not significant vs rest)
- Delayed-onset hypoglycemia still occurs in recovery hours later

### HIIT / Mixed
- Tends toward glucose stability
- Resistance BEFORE aerobic attenuates hypoglycemia during aerobic portion
- A sprint before or after aerobic sessions reduces hypo risk

### Competition / Adrenaline
- Can cause significant BG rises from stress hormones
- May need correction bolus AFTER event, but be cautious (see nocturnal hypo warning)

## Basal Reduction and Targets

Consensus: 50-80% basal reduction, started 60-90 min before aerobic exercise (pump users)
Target range: 126-180 mg/dL (7-10 mmol/L) for aerobic exercise

Commercial AID exercise modes for reference:
- Tandem Control-IQ: target 140-160 mg/dL
- Medtronic 780G: target 150 mg/dL
- ISPAD 2022: recommends 145-198 mg/dL for medium/high hypo risk

## Meal Bolus Reductions (exercise within 90 min of meal)

| Intensity | 30 min exercise | 60 min exercise |
|-----------|----------------|----------------|
| Mild (~25% VO2max) | -25% | -50% |
| Moderate (~50% VO2max) | -50% | -75% |
| Heavy (70-75% VO2max) | -75% | N/A |
| Intense/anaerobic (>80%) | No reduction | N/A |

Source: Riddell et al. 2017 consensus

## Post-Exercise Nocturnal Hypoglycemia

CRITICAL SAFETY DATA:
- DirecNet study: nocturnal hypo (≤60 mg/dL) in 48% of youth after afternoon exercise
  vs 28% on sedentary days — with identical insulin doses
- Biphasic pattern: delayed glucose-requirement peak 7-11 hours post-exercise (overnight)
- Mechanism: continued GLUT4-mediated glycogen replenishment + blunted counterregulation (HAAF)

Prevention strategies:
1. Low-GI bedtime snack (0.4g carbs/kg body weight) without full insulin coverage
2. ~20% overnight basal reduction for 6 hours at bedtime
3. Reduce post-exercise meal bolus by ~50%
4. CGM with low alarms set

⚠️ CRITICAL WARNING from Riddell et al.:
"Overcorrection of post-exercise hyperglycemia with insulin can cause severe nocturnal
hypoglycaemia and lead to death" — linked to dead-in-bed syndrome.
The copilot MUST display this warning when detecting a post-exercise correction bolus.

## When NOT to Exercise

Contraindications from Riddell + ISPAD:
- Blood ketones ≥1.5 mmol/L or large urine ketones — exercise contraindicated until resolved
- BG >270 mg/dL with unexplained hyperglycemia — check ketones first
- Severe hypoglycemia within previous 24 hours
- BG <90 mg/dL — calculate carbs needed to reach ~130 using user's weight-based rise_per_gram, ingest, delay until BG rises

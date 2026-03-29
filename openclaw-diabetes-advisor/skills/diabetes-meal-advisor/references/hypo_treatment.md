# Hypoglycemia Treatment Reference

Sources: ADA, ISPAD 2022, Scheiner (DiaTribe), REVERSIBLE Trial 2024,
Carlson et al. 2017 (Emergency Medicine Journal)

## CRITICAL: Always Calculate, Never Use Generic Amounts

The "15-15 rule" (15g carbs, recheck in 15 min) is a population average from
the 1980s. It is WRONG for most individuals:

- A person with ICR 1:5 and ISF 25: 15g raises BG by 75 mg/dL — massive overshoot
- A person with ICR 1:15 and ISF 100: 15g raises BG by only 25 mg/dL — may undertreat

**The copilot must ALWAYS calculate from the user's actual settings.**

## Personalized Treatment Formula

```
Step 1: Estimate where BG is heading
  remaining_drop = IOB × current_ISF
  effective_low = current_BG - remaining_drop

Step 2: Calculate the deficit
  bg_deficit = target_BG - effective_low

Step 3: Calculate grams needed (weight-based rise per gram)
  grams_needed = bg_deficit / rise_per_gram

Step 4: Apply safety bounds
  minimum = 10g (safety floor — never recommend less)
  if grams_needed > 40g: treat in stages (20-25g, recheck, repeat)
```

If IOB is unknown, calculate from BG deficit alone but flag that IOB could
make it worse and ask for their IOB.

## Weight-Based BG Rise per Gram of Glucose

The rise per gram is stored in the user's profile. If not set, use this table:

| Body Weight | BG rise per 1g glucose |
|-------------|----------------------|
| ~60 lbs (27 kg) | 6-10 mg/dL |
| ~100 lbs (45 kg) | ~5 mg/dL |
| ~140 lbs (64 kg) | ~4 mg/dL |
| ~180 lbs (82 kg) | ~3 mg/dL |
| ~220+ lbs (100 kg) | ~2-3 mg/dL |

Source: Gary Scheiner, DiaTribe

Active IOB, recent exercise, and rate of decline all modulate actual response.
When in doubt, treat with MORE rather than less — undertreating a low is dangerous.

## Severity Escalation

Even though treatment grams should be personalized, urgency escalates by level:

| Level | BG Range | Urgency |
|-------|----------|---------|
| Level 1 | 55-70 mg/dL | Calculate and treat. Recheck in 15 min. |
| Level 2 | <54 mg/dL | URGENT — treat immediately. Err on the high side of your calculation. |
| Level 3 | <40 or unable to self-treat | GLUCAGON — no oral treatment if consciousness impaired. |

Note: REVERSIBLE Trial (2024, Diabetes Care) found only 45% of Level 1 episodes
resolved within 15 min in pump users on hybrid closed-loop.

## Fast-Acting Carb Ranking (fastest to slowest)

1. **Glucose tablets / Smarties-Rockets** (pure dextrose): onset 5-10 min, peak 10-15 min
2. **Glucose gel**: onset 10-15 min, peak 15-20 min
3. **Regular soda**: onset 10-15 min, peak 15-25 min (sucrose = 50% fructose)
4. **Juice** (grape fastest > orange > apple): onset 10-15 min, peak 20-30 min
5. **Honey**: onset 10-15 min, peak 20-30 min
6. **Milk**: onset 15-30 min, peak 30-45 min — TOO SLOW for acute treatment

CRITICAL: Fructose does NOT directly raise blood glucose — must be liver-metabolized.
Fat delays gastric emptying. Chocolate bars and candy with fat are POOR choices for
acute hypoglycemia treatment.

## Glucagon Options

| Product | Route | Dose (≥12yr adult) | Onset | Notes |
|---------|-------|---------------------|-------|-------|
| Baqsimi | Nasal | 3 mg | ~16 min | No reconstitution, ≥1 year |
| Gvoke HypoPen | IM autoinjector | 1 mg | ~10 min | Pre-filled, <12yr = 0.5mg |
| Zegalogue (dasiglucagon) | SC pre-filled | 0.6 mg | ~10 min | ≥6 years |

All achieve treatment success (BG ≥70 or rise ≥20 mg/dL) in >98% of cases.

## Mini-Dose Glucagon Protocol (for GI illness / can't eat)

For preventing hypoglycemia when oral intake fails. Originally Haymond & Schreiner,
endorsed by ISPAD 2022.

| Age | Dose |
|-----|------|
| ≤2 years | 20 µg (2 units on insulin syringe) |
| 3-15 years | 10 µg per year of age |
| >15 years / adults | 150 µg (15 units on insulin syringe) |

Reconstituted glucagon kit works 24 hours refrigerated.
Expected rise: 60-90 mg/dL within 30 min without full-dose nausea.
Can repeat every 30-60 min up to 3 times.
Caveat: requires adequate hepatic glycogen — prolonged fasting depletes stores.

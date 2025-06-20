import Foundation

struct SimpleCob {
    /// Calculate COB using simple piecewise linear absorption
    /// Returns (totalCarbs, currentCOB)
    static func calculate(
        treatments: [MealInput],
        currentTime: Date,
        absorptionHours: Decimal = 3  // Default 3 hours
    ) -> (carbs: Decimal, cob: Decimal) {
        
        var totalCarbs: Decimal = 0
        var totalCOB: Decimal = 0
        
        let absorptionMinutes = absorptionHours * 60
        let delayMinutes: Decimal = 15     // 15 min delay before absorption starts
        let peakMinutes: Decimal = 60      // Peak at 1 hour (50% absorbed)
        
        for treatment in treatments {
            guard let carbs = treatment.carbs, carbs > 0 else { continue }
            
            let minutesSinceMeal = Decimal(currentTime.timeIntervalSince(treatment.timestamp) / 60)
            
            // Skip future meals or fully absorbed meals
            guard minutesSinceMeal >= 0, minutesSinceMeal <= absorptionMinutes else { continue }
            
            totalCarbs += carbs
            
            // Calculate absorption fraction
            let absorbed: Decimal
            if minutesSinceMeal < delayMinutes {
                // No absorption yet
                absorbed = 0
            } else if minutesSinceMeal < peakMinutes {
                // Linear ramp to 50% at peak
                absorbed = 0.5 * (minutesSinceMeal - delayMinutes) / (peakMinutes - delayMinutes)
            } else {
                // Linear ramp from 50% to 100%
                absorbed = 0.5 + 0.5 * (minutesSinceMeal - peakMinutes) / (absorptionMinutes - peakMinutes)
            }
            
            let remaining = carbs * (1 - absorbed)
            totalCOB += remaining
        }
        
        return (totalCarbs, max(0, totalCOB))
    }
}

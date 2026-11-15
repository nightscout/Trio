import Foundation

extension SettingsAnalysis {
    struct Detection {
        /// All occurrences inside the time frame, newest first.
        var occurrences: [Occurrence]
        /// The most common circumstance, e.g. "64% after breakfast".
        var pattern: String
        /// Selects advice wording when the cause differs from the usual case.
        var variant: AdviceVariant? = nil
    }

    /// Why a meal-related scenario happened, when it changes which setting to look at.
    enum AdviceVariant: Equatable {
        /// Mostly unannounced meals covered by SMBs only.
        case unannounced
        /// Mostly unannounced meals with a manual prebolus.
        case prebolus
    }

    /// How a user tells Trio about meals, derived from the time frame.
    enum AnnouncementStyle: Equatable {
        case announced
        case partial
        case unannounced
    }

    struct MealProfile: Equatable {
        /// Logged meals (carb entries merged within 30 min, at least 10 g) per day.
        var loggedPerDay: Double
        /// Meal-like rises without logged carbs per day.
        var unannouncedPerDay: Double
        /// Share of unannounced meals with a manual prebolus, 0–1, or nil without any.
        var prebolusShare: Double?
        var loggedCount: Int

        var style: AnnouncementStyle {
            if loggedPerDay >= Detectors.Threshold.announcedMealsPerDay { return .announced }
            if loggedPerDay < Detectors.Threshold.unannouncedMealsPerDay { return .unannounced }
            return .partial
        }
    }

    /// Thresholds are in mg/dL and match `Scenario.detectionRule(units:)`.
    struct Detectors {
        enum Threshold {
            static let low = 70
            static let high = 180
            static let mealRise = 60
            static let dawnRise = 50
            static let activityDrop = 50
            /// A rise this large within `unannouncedRiseWindow` with no logged carbs is treated as a meal.
            static let unannouncedRise = 45
            static let unannouncedRiseWindow: TimeInterval = 30 * 60
            /// A manual bolus up to this long before such a rise is its prebolus.
            static let prebolusWindow: TimeInterval = 60 * 60
            /// Meal announcement cut-offs (logged meals per day). Provisional.
            static let announcedMealsPerDay = 2.0
            static let unannouncedMealsPerDay = 0.3
            /// A gap longer than this ends a low or high episode.
            static let maxGap: TimeInterval = 15 * 60
        }

        struct Episode {
            let points: [GlucosePoint]
            var start: Date { points.first!.date }
            var end: Date { points.last!.date }
            var duration: TimeInterval { end.timeIntervalSince(start) }
            var nadir: Int { points.map(\.value).min() ?? 0 }
            var mean: Double { Double(points.map(\.value).reduce(0, +)) / Double(max(points.count, 1)) }
        }

        struct Meal {
            let date: Date
            let grams: Double
        }

        /// A meal-like rise with no logged carbs.
        struct InferredMeal {
            /// Start of the rise.
            let start: Date
            /// Manual bolus up to 1 h before the rise.
            let prebolus: BolusEvent?
            /// SMBs in the 2 h after the rise started.
            let smbUnits: Double
        }

        let history: History
        let timeFrame: TimeFrame
        let units: GlucoseUnits
        let calendar: Calendar

        let lowEpisodes: [Episode]
        let highEpisodes: [Episode]
        let manualBoluses: [BolusEvent]
        let inferredMeals: [InferredMeal]

        init(history: History, timeFrame: TimeFrame, units: GlucoseUnits, calendar: Calendar = .current) {
            self.history = history
            self.timeFrame = timeFrame
            self.units = units
            self.calendar = calendar
            // Two readings (about 10 min) so a single noisy value is not an episode.
            lowEpisodes = Self.episodes(in: history.glucose, minPoints: 2) { $0 < Threshold.low }
            highEpisodes = Self.episodes(in: history.glucose, minPoints: 2) { $0 > Threshold.high }
            manualBoluses = history.boluses.filter { !$0.isSMB }
            inferredMeals = Self.inferMeals(history: history, lowEpisodes: lowEpisodes, manualBoluses: manualBoluses)
        }

        func detect(_ scenario: Scenario) -> Detection {
            switch scenario {
            case .mealSpike: return mealSpike()
            case .bolusThenHypo: return bolusThenHypo()
            case .reboundHigh: return reboundHigh()
            case .dawnPhenomenon: return dawnPhenomenon()
            case .overnightLow: return overnightLow()
            case .persistentHigh: return persistentHigh()
            case .delayedMealRise: return delayedMealRise()
            case .exerciseDrop: return exerciseDrop()
            case .unannouncedMeal: return unannouncedMealRise()
            }
        }

        // MARK: Scenarios

        /// Carb entry, then a rise of more than 60 mg/dL to above 180 within 2 h.
        private func mealSpike() -> Detection {
            var found: [(Occurrence, Meal)] = []
            for meal in meals(minGrams: 10) where inFrame(meal.date) {
                guard let base = glucose(in: meal.date.addingTimeInterval(-20 * 60) ... meal.date.addingTimeInterval(5 * 60))
                    .last,
                    let peak = glucose(in: meal.date ... meal.date.addingTimeInterval(2 * 3600))
                    .max(by: { $0.value < $1.value }),
                    peak.value > Threshold.high, peak.value - base.value > Threshold.mealRise
                else { continue }
                let detail =
                    String(localized: "Peak \(peak.value.formatted(withUnits: units)) after \(Int(meal.grams.rounded())) g carbs")
                found.append((Occurrence(date: meal.date, detail: detail), meal))
            }
            return Detection(occurrences: sorted(found.map(\.0)), pattern: mealSlotPattern(found.map(\.1.date)))
        }

        /// Manual bolus, or SMBs after an unannounced meal, then a low within 4 h, with no carbs eaten in between.
        private func bolusThenHypo() -> Detection {
            enum Cause: Int { case correction, mealBolus, prebolus, unannouncedSMB }
            var occurrences: [Occurrence] = []
            var causes: [Cause: Int] = [:]

            for low in lowEpisodes where inFrame(low.start) {
                let windowStart = low.start.addingTimeInterval(-4 * 3600)
                let bolus = manualBoluses.last {
                    $0.date <= low.start.addingTimeInterval(-15 * 60) && $0.date >= windowStart
                }
                let meal = inferredMeals.last {
                    $0.start <= low.start.addingTimeInterval(-30 * 60) && $0.start >= windowStart
                }

                let cause: Cause
                let causeDate: Date
                // A later correction bolus is the more direct cause than the meal before it.
                if let meal, meal.prebolus != nil || meal.smbUnits >= 1,
                   bolus.map({ $0.date <= meal.start.addingTimeInterval(15 * 60) }) ?? true
                {
                    cause = meal.prebolus != nil ? .prebolus : .unannouncedSMB
                    causeDate = meal.prebolus?.date ?? meal.start
                } else if let bolus {
                    let withCarbs = !carbs(in: bolus.date.addingTimeInterval(-30 * 60) ... bolus.date.addingTimeInterval(15 * 60))
                        .isEmpty
                    // A bolus without carbs that is followed by a meal-like rise was a prebolus, not a correction.
                    let isPrebolus = !withCarbs && inferredMeals.contains { $0.prebolus == bolus }
                    cause = withCarbs ? .mealBolus : isPrebolus ? .prebolus : .correction
                    causeDate = bolus.date
                } else {
                    continue
                }

                // Carbs after the bolus would explain the low.
                guard carbs(in: causeDate.addingTimeInterval(15 * 60) ... low.start).isEmpty else { continue }
                causes[cause, default: 0] += 1

                let hours = (low.start.timeIntervalSince(causeDate) / 360).rounded() / 10
                let nadir = low.nadir.formatted(withUnits: units)
                let detail = cause == .unannouncedSMB
                    ? String(localized: "Low \(nadir) \(hours.formatted()) h after an unannounced meal")
                    : String(localized: "Low \(nadir) \(hours.formatted()) h after bolus")
                occurrences.append(Occurrence(date: low.start, detail: detail))
            }

            let total = occurrences.count
            guard total > 0 else { return Detection(occurrences: [], pattern: "") }

            let unannounced = (causes[.prebolus] ?? 0) + (causes[.unannouncedSMB] ?? 0)
            let top = causes.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }
            let pct = percent(top?.value ?? 0, of: total)
            let pattern: String
            switch top?.key ?? .correction {
            case .correction: pattern = String(localized: "\(pct)% after correction boluses")
            case .mealBolus: pattern = String(localized: "\(pct)% after meal boluses")
            case .prebolus: pattern = String(localized: "\(pct)% after a prebolus for an unannounced meal")
            case .unannouncedSMB: pattern = String(localized: "\(pct)% after SMBs for an unannounced meal")
            }

            var variant: AdviceVariant?
            if unannounced * 2 > total {
                variant = (causes[.prebolus] ?? 0) >= (causes[.unannouncedSMB] ?? 0) ? .prebolus : .unannounced
            }
            return Detection(occurrences: sorted(occurrences), pattern: pattern, variant: variant)
        }

        /// Low, then above 180 within 3 h of the low ending.
        private func reboundHigh() -> Detection {
            var occurrences: [Occurrence] = []
            var largeTreatments = 0
            for low in lowEpisodes where inFrame(low.start) {
                guard let peak = glucose(in: low.end ... low.end.addingTimeInterval(3 * 3600)).max(by: { $0.value < $1.value }),
                      peak.value > Threshold.high
                else { continue }
                let treatment = carbs(in: low.start.addingTimeInterval(-15 * 60) ... low.end.addingTimeInterval(30 * 60))
                    .reduce(0) { $0 + $1.grams }
                if treatment > 20 { largeTreatments += 1 }
                let peakText = peak.value.formatted(withUnits: units)
                let detail = treatment > 0
                    ? String(localized: "\(Int(treatment.rounded())) g treatment, then peak \(peakText)")
                    : String(localized: "No carbs logged, then peak \(peakText)")
                occurrences.append(Occurrence(date: low.start, detail: detail))
            }
            let pattern = largeTreatments * 2 >= occurrences.count && largeTreatments > 0
                ?
                String(
                    localized: "\(percent(largeTreatments, of: occurrences.count))% after treating a low with more than 20 g carbs"
                )
                : timeOfDayPattern(occurrences.map(\.date))
            return Detection(occurrences: sorted(occurrences), pattern: pattern)
        }

        /// Rise of more than 50 mg/dL between 03:00 and 08:00 with no low that night. The window ends at
        /// the first carbs, manual bolus or unannounced meal; nights with one before 03:00 are skipped.
        private func dawnPhenomenon() -> Detection {
            var occurrences: [Occurrence] = []
            var riseStartMinutes: [Int] = []
            var nightsWithData = 0

            for day in days() {
                guard let from = time(3, on: day), let to = time(8, on: day), let lateEvening = time(1, on: day),
                      from >= timeFrame.start, to <= timeFrame.end
                else { continue }
                // Breakfast (logged, bolused or only seen as a fast rise) ends the window early.
                let mealLike = carbs(in: lateEvening ... to).map(\.date)
                    + manualBoluses.filter { $0.date >= lateEvening && $0.date <= to }.map(\.date)
                    + inferredMeals.filter { $0.start >= lateEvening && $0.start <= to }.map(\.start)
                let cutoff = mealLike.min() ?? to
                let window = cutoff.timeIntervalSince(from)
                // At least 2 h of night, with most readings present (one every 5 min).
                guard window >= 2 * 3600 else { continue }
                let readings = glucose(in: from ... cutoff)
                guard Double(readings.count) >= window / 300 * 0.6 else { continue }
                nightsWithData += 1

                guard !glucose(in: day ... cutoff).contains(where: { $0.value < Threshold.low }) else { continue }

                var lowest = readings[readings.startIndex]
                var bestRise = 0
                var riseStart = lowest.date
                for point in readings {
                    // `<=` so the rise starts at the last minimum, not the first.
                    if point.value <= lowest.value { lowest = point }
                    if point.value - lowest.value > bestRise {
                        bestRise = point.value - lowest.value
                        riseStart = lowest.date
                    }
                }
                guard bestRise > Threshold.dawnRise else { continue }

                let detail = String(localized: "Rise of \(bestRise.formatted(withUnits: units)) before waking")
                occurrences.append(Occurrence(date: riseStart, detail: detail))
                let components = calendar.dateComponents([.hour, .minute], from: riseStart)
                riseStartMinutes.append((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }

            var pattern = ""
            if !riseStartMinutes.isEmpty {
                let median = riseStartMinutes.sorted()[riseStartMinutes.count / 2]
                let rounded = (median + 7) / 15 * 15
                let clock = calendar.date(bySettingHour: rounded / 60, minute: rounded % 60, second: 0, of: Date())
                    .map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
                pattern =
                    String(localized: "Starts around \(clock) on \(percent(occurrences.count, of: nightsWithData))% of nights")
            }
            return Detection(occurrences: sorted(occurrences), pattern: pattern)
        }

        /// Low starting between 00:00 and 06:00.
        private func overnightLow() -> Detection {
            var occurrences: [Occurrence] = []
            var hourCounts = [Int](repeating: 0, count: 6)
            for low in lowEpisodes where inFrame(low.start) {
                let hour = calendar.component(.hour, from: low.start)
                guard hour < 6 else { continue }
                hourCounts[hour] += 1
                let minutes = Int((low.duration / 60).rounded()) + 5
                let detail = String(localized: "Nadir \(low.nadir.formatted(withUnits: units)), \(minutes) min below range")
                occurrences.append(Occurrence(date: low.start, detail: detail))
            }

            var pattern = ""
            if !occurrences.isEmpty {
                let best = (0 ..< 5).max { hourCounts[$0] + hourCounts[$0 + 1] < hourCounts[$1] + hourCounts[$1 + 1] } ?? 0
                let pct = percent(hourCounts[best] + hourCounts[best + 1], of: occurrences.count)
                pattern = String(localized: "\(pct)% between \(clock(best)) and \(clock(best + 2))")
            }
            return Detection(occurrences: sorted(occurrences), pattern: pattern)
        }

        /// Above 180 for more than 3 h, with no carbs or unannounced meal from an hour before until the end.
        private func persistentHigh() -> Detection {
            var occurrences: [Occurrence] = []
            var siteDays: [Int] = []
            for high in highEpisodes where inFrame(high.start) && high.duration > 3 * 3600 {
                guard carbs(in: high.start.addingTimeInterval(-3600) ... high.end).isEmpty,
                      !inferredMeals.contains(where: {
                          $0.start >= high.start.addingTimeInterval(-3600) && $0.start <= high.end
                      })
                else { continue }
                let hours = (high.duration / 360).rounded() / 10
                let detail =
                    String(localized: "Mean \(Int(high.mean.rounded()).formatted(withUnits: units)) for \(hours.formatted()) h")
                occurrences.append(Occurrence(date: high.start, detail: detail))
                if let change = history.siteChanges.last(where: { $0 <= high.start }),
                   high.start.timeIntervalSince(change) < HistoryLoader.siteLookback
                {
                    siteDays.append(Int(high.start.timeIntervalSince(change) / 86400) + 1)
                }
            }

            var pattern = timeOfDayPattern(occurrences.map(\.date))
            if siteDays.count * 2 >= occurrences.count, !siteDays.isEmpty {
                let counts = Dictionary(grouping: siteDays, by: { $0 }).mapValues(\.count)
                if let best = mostCommon(counts), best.count * 5 >= occurrences.count * 2 {
                    pattern =
                        String(localized: "\(percent(best.count, of: occurrences.count))% on day \(best.key) of an infusion site")
                }
            }
            return Detection(occurrences: sorted(occurrences), pattern: pattern)
        }

        /// In range 2 h after a meal, then above 180 3–6 h after it, with no further carbs.
        private func delayedMealRise() -> Detection {
            let occurrences = delayedRises().filter { inFrame($0.meal.date) }.map { rise in
                let hours = Int((rise.peak.date.timeIntervalSince(rise.meal.date) / 3600).rounded())
                let detail = String(localized: "Peak \(rise.peak.value.formatted(withUnits: units)) \(hours) h after meal")
                return Occurrence(date: rise.meal.date, detail: detail)
            }
            return Detection(occurrences: sorted(occurrences), pattern: mealSlotPattern(occurrences.map(\.date)))
        }

        private func delayedRises() -> [(meal: Meal, peak: GlucosePoint)] {
            meals(minGrams: 20).compactMap { meal in
                let twoHours = meal.date.addingTimeInterval(2 * 3600)
                guard let atTwoHours = glucose(in: twoHours.addingTimeInterval(-15 * 60) ... twoHours.addingTimeInterval(15 * 60))
                    .min(by: { abs($0.date.timeIntervalSince(twoHours)) < abs($1.date.timeIntervalSince(twoHours)) }),
                    (Threshold.low ... Threshold.high).contains(atTwoHours.value),
                    carbs(in: meal.date.addingTimeInterval(30 * 60) ... meal.date.addingTimeInterval(6 * 3600)).isEmpty,
                    let peak = glucose(in: meal.date.addingTimeInterval(3 * 3600) ... meal.date.addingTimeInterval(6 * 3600))
                    .max(by: { $0.value < $1.value }),
                    peak.value > Threshold.high
                else { return nil }
                return (meal, peak)
            }
        }

        /// Rise of more than 45 mg/dL within 30 min with no carbs logged, then above 180 within 2 h.
        private func unannouncedMealRise() -> Detection {
            // A late rise after a logged meal belongs to Delayed Meal Rise.
            let delayed = delayedRises().map(\.meal.date)
            var occurrences: [Occurrence] = []
            var prebolused = 0

            for meal in inferredMeals where inFrame(meal.start) {
                guard !delayed.contains(where: {
                    meal.start >= $0.addingTimeInterval(2 * 3600) && meal.start <= $0.addingTimeInterval(6 * 3600)
                }),
                    let peak = glucose(in: meal.start ... meal.start.addingTimeInterval(2 * 3600))
                    .max(by: { $0.value < $1.value }),
                    peak.value > Threshold.high
                else { continue }

                let peakText = peak.value.formatted(withUnits: units)
                let detail: String
                if let bolus = meal.prebolus {
                    prebolused += 1
                    let minutes = Int((meal.start.timeIntervalSince(bolus.date) / 60).rounded())
                    let amount = insulin(bolus.units)
                    detail = minutes > 0
                        ? String(localized: "Peak \(peakText), prebolus \(amount) U \(minutes) min before the rise")
                        : String(localized: "Peak \(peakText), bolus \(amount) U at the start of the rise")
                } else {
                    detail = String(localized: "Peak \(peakText), \(insulin(meal.smbUnits)) U SMB in 2 h, no manual bolus")
                }
                occurrences.append(Occurrence(date: meal.start, detail: detail))
            }

            let total = occurrences.count
            let mostlyPrebolused = prebolused > 0 && prebolused * 2 >= total
            let pattern = mostlyPrebolused
                ? String(localized: "\(percent(prebolused, of: total))% with a manual prebolus")
                : mealSlotPattern(occurrences.map(\.date))
            return Detection(
                occurrences: sorted(occurrences),
                pattern: pattern,
                variant: total == 0 ? nil : mostlyPrebolused ? .prebolus : .unannounced
            )
        }

        /// How meals are announced over the time frame.
        var mealProfile: MealProfile {
            let days = max(timeFrame.days, 1.0 / 24)
            let logged = meals(minGrams: 10).filter { inFrame($0.date) }.count
            let unannounced = inferredMeals.filter { inFrame($0.start) }
            let prebolused = unannounced.filter { $0.prebolus != nil }.count
            return MealProfile(
                loggedPerDay: Double(logged) / days,
                unannouncedPerDay: Double(unannounced.count) / days,
                prebolusShare: unannounced.isEmpty ? nil : Double(prebolused) / Double(unannounced.count),
                loggedCount: logged
            )
        }

        /// Drop of more than 50 mg/dL within 1 h, during an activity period or the hour after it.
        private func exerciseDrop() -> Detection {
            var occurrences: [Occurrence] = []
            var withIOB = 0
            var highIOB = 0
            for activity in history.activity {
                let window = glucose(in: activity.start ... activity.end.addingTimeInterval(3600))
                guard let drop = largestDrop(in: window, within: 3600), drop.amount > Threshold.activityDrop,
                      inFrame(drop.start)
                else { continue }
                let minutes = Int((drop.end.timeIntervalSince(drop.start) / 60).rounded())
                let detail = String(localized: "Dropped \(drop.amount.formatted(withUnits: units)) in \(minutes) min")
                occurrences.append(Occurrence(date: drop.start, detail: detail))
                if let iob = history.iob
                    .last(where: { $0.date <= drop.start && drop.start.timeIntervalSince($0.date) < 15 * 60 })
                {
                    withIOB += 1
                    if iob.iob > 2 { highIOB += 1 }
                }
            }
            let pattern = !occurrences.isEmpty && withIOB * 2 >= occurrences.count && highIOB * 2 >= withIOB && highIOB > 0
                ? String(localized: "\(percent(highIOB, of: withIOB))% with more than 2 U insulin on board")
                : timeOfDayPattern(occurrences.map(\.date))
            return Detection(occurrences: sorted(occurrences), pattern: pattern)
        }

        // MARK: Glucose helpers

        static func episodes(in glucose: [GlucosePoint], minPoints: Int, where matches: (Int) -> Bool) -> [Episode] {
            var episodes: [Episode] = []
            var current: [GlucosePoint] = []
            func close() {
                if current.count >= minPoints { episodes.append(Episode(points: current)) }
                current = []
            }
            for point in glucose {
                if matches(point.value) {
                    if let last = current.last, point.date.timeIntervalSince(last.date) > Threshold.maxGap { close() }
                    current.append(point)
                } else {
                    close()
                }
            }
            close()
            return episodes
        }

        /// Finds meal-like rises with no logged carbs. One meal per 3 h; rises right after a low
        /// (rebounds) and rises next to a carb entry (logged meals) are skipped.
        static func inferMeals(history: History, lowEpisodes: [Episode], manualBoluses: [BolusEvent]) -> [InferredMeal] {
            let glucose = history.glucose
            var meals: [InferredMeal] = []
            var nextAllowed = Date.distantPast

            for (index, start) in glucose.enumerated() where start.date >= nextAllowed && start.value >= Threshold.low {
                var rises = false
                var next = index + 1
                while next < glucose.count, glucose[next].date.timeIntervalSince(start.date) <= Threshold.unannouncedRiseWindow {
                    if glucose[next].value - start.value >= Threshold.unannouncedRise {
                        rises = true
                        break
                    }
                    next += 1
                }
                guard rises else { continue }
                nextAllowed = start.date.addingTimeInterval(3 * 3600)

                let isRebound = lowEpisodes.contains {
                    $0.end <= start.date && start.date.timeIntervalSince($0.end) < 2 * 3600
                }
                // Carbs are often logged a little before or after eating.
                let isLogged = history.carbs.contains {
                    $0.date >= start.date.addingTimeInterval(-45 * 60) && $0.date <= start.date.addingTimeInterval(30 * 60)
                }
                guard !isRebound, !isLogged else { continue }

                let prebolus = manualBoluses.last {
                    $0.date >= start.date.addingTimeInterval(-Threshold.prebolusWindow) && $0.date <= start.date
                        .addingTimeInterval(15 * 60)
                }
                let smbUnits = history.boluses
                    .filter { $0.isSMB && $0.date >= start.date && $0.date <= start.date.addingTimeInterval(2 * 3600) }
                    .reduce(0) { $0 + $1.units }
                meals.append(InferredMeal(start: start.date, prebolus: prebolus, smbUnits: smbUnits))
            }
            return meals
        }

        /// Readings in the range, using binary search on the sorted history.
        func glucose(in range: ClosedRange<Date>) -> ArraySlice<GlucosePoint> {
            let glucose = history.glucose
            var low = 0
            var high = glucose.count
            while low < high {
                let mid = (low + high) / 2
                if glucose[mid].date < range.lowerBound { low = mid + 1 } else { high = mid }
            }
            var end = low
            while end < glucose.count, glucose[end].date <= range.upperBound { end += 1 }
            return glucose[low ..< end]
        }

        private func largestDrop(
            in readings: ArraySlice<GlucosePoint>,
            within interval: TimeInterval
        ) -> (amount: Int, start: Date, end: Date)? {
            let points = Array(readings)
            var best: (amount: Int, start: Date, end: Date)?
            for i in points.indices {
                var j = i + 1
                while j < points.count, points[j].date.timeIntervalSince(points[i].date) <= interval {
                    let amount = points[i].value - points[j].value
                    if amount > (best?.amount ?? 0) { best = (amount, points[i].date, points[j].date) }
                    j += 1
                }
            }
            return best
        }

        // MARK: Treatment helpers

        private func carbs(in range: ClosedRange<Date>) -> [CarbEvent] {
            history.carbs.filter { range.contains($0.date) }
        }

        /// Carb entries within 30 min of each other count as one meal.
        func meals(minGrams: Double) -> [Meal] {
            var meals: [Meal] = []
            for entry in history.carbs.sorted(by: { $0.date < $1.date }) {
                if let last = meals.last, entry.date.timeIntervalSince(last.date) <= 30 * 60 {
                    meals[meals.count - 1] = Meal(date: last.date, grams: last.grams + entry.grams)
                } else {
                    meals.append(Meal(date: entry.date, grams: entry.grams))
                }
            }
            return meals.filter { $0.grams >= minGrams }
        }

        // MARK: Time helpers

        private func inFrame(_ date: Date) -> Bool {
            date >= timeFrame.start && date <= timeFrame.end
        }

        private func days() -> [Date] {
            var days: [Date] = []
            var day = calendar.startOfDay(for: timeFrame.start)
            while day < timeFrame.end {
                days.append(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return days
        }

        private func time(_ hour: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }

        private func insulin(_ units: Double) -> String {
            units.formatted(.number.precision(.fractionLength(1)))
        }

        private func clock(_ hour: Int) -> String {
            String(format: "%02d:00", hour % 24)
        }

        private func sorted(_ occurrences: [Occurrence]) -> [Occurrence] {
            occurrences.sorted { $0.date > $1.date }
        }

        private func percent(_ part: Int, of total: Int) -> Int {
            total == 0 ? 0 : Int((Double(part) / Double(total) * 100).rounded())
        }

        // MARK: Patterns

        /// Highest count; ties go to the lower key so results are stable.
        private func mostCommon(_ counts: [Int: Int]) -> (key: Int, count: Int)? {
            counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }.map { ($0.key, $0.value) }
        }

        private func timeOfDayPattern(_ dates: [Date]) -> String {
            guard !dates.isEmpty else { return "" }
            let buckets = Dictionary(grouping: dates) { date -> Int in
                switch calendar.component(.hour, from: date) {
                case 0 ..< 6: return 0
                case 6 ..< 11: return 1
                case 11 ..< 15: return 2
                case 15 ..< 18: return 3
                default: return 4
                }
            }.mapValues(\.count)
            guard let best = mostCommon(buckets) else { return "" }
            let pct = percent(best.count, of: dates.count)
            switch best.key {
            case 0: return String(localized: "\(pct)% at night")
            case 1: return String(localized: "\(pct)% in the morning")
            case 2: return String(localized: "\(pct)% around midday")
            case 3: return String(localized: "\(pct)% in the afternoon")
            default: return String(localized: "\(pct)% in the evening")
            }
        }

        private func mealSlotPattern(_ dates: [Date]) -> String {
            guard !dates.isEmpty else { return "" }
            let slots = Dictionary(grouping: dates) { date -> Int in
                switch calendar.component(.hour, from: date) {
                case 4 ..< 10: return 0
                case 10 ..< 15: return 1
                case 17 ..< 22: return 2
                default: return 3
                }
            }.mapValues(\.count)
            guard let best = mostCommon(slots) else { return "" }
            let pct = percent(best.count, of: dates.count)
            switch best.key {
            case 0: return String(localized: "\(pct)% after breakfast")
            case 1: return String(localized: "\(pct)% after lunch")
            case 2: return String(localized: "\(pct)% after dinner")
            default: return String(localized: "\(pct)% after snacks")
            }
        }
    }
}

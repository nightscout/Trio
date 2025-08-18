import LoopKit

enum RefillSteps: Int {
    case reservoir = 1
    case tube = 2
    case prime = 3
    case done = 4

    func nextStep() -> RefillSteps? {
        switch self {
        case .reservoir:
            return .tube
        case .tube:
            return .prime
        case .prime:
            return .done
        case .done:
            return nil
        }
    }
}

class DanaKitRefillReservoirCannulaViewModel: ObservableObject {
    @Published var cannulaOnly: Bool
    @Published var currentStep: RefillSteps

    @Published var reservoirAmount: UInt16 = 300
    @Published var tubeAmount: Double = 7
    @Published var primeAmount: Double = 0.3

    @Published var loadingReservoirAmount = false
    @Published var loadingTubeAmount = false
    @Published var loadingPrimeAmount = false

    @Published var failedReservoirAmount = false
    @Published var failedTubeAmount = false
    @Published var failedPrimeAmount = false

    @Published var tubeDeliveredUnits: Double = 0
    @Published var primeDeliveredUnits: Double = 0

    @Published var tubeProgress: Double = 0
    @Published var primeProgress: Double = 0

    private let pumpManager: DanaKitPumpManager?
    private var primeReporter: DoseProgressReporter?
    private let processQueue = DispatchQueue(label: "DanaKit.prime.processQueue")

    init(pumpManager: DanaKitPumpManager?, cannulaOnly: Bool) {
        self.pumpManager = pumpManager
        self.cannulaOnly = cannulaOnly
        currentStep = cannulaOnly ? RefillSteps.prime : RefillSteps.reservoir
    }

    func setReservoirAmount() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        loadingReservoirAmount = true
        let model = PacketGeneralSetUserOption(
            isTimeDisplay24H: pumpManager.state.isTimeDisplay24H,
            isButtonScrollOnOff: pumpManager.state.isButtonScrollOnOff,
            beepAndAlarm: pumpManager.state.beepAndAlarm.rawValue,
            lcdOnTimeInSec: pumpManager.state.lcdOnTimeInSec,
            backlightOnTimeInSec: pumpManager.state.backlightOnTimInSec,
            selectedLanguage: pumpManager.state.selectedLanguage,
            units: pumpManager.state.units,
            shutdownHour: pumpManager.state.shutdownHour,
            lowReservoirRate: pumpManager.state.lowReservoirRate,
            cannulaVolume: pumpManager.state.cannulaVolume,
            refillAmount: reservoirAmount,
            targetBg: pumpManager.state.targetBg
        )

        pumpManager.setUserSettings(data: model) { success in
            DispatchQueue.main.async {
                self.loadingReservoirAmount = false

                guard success else {
                    self.failedReservoirAmount = true
                    return
                }

                self.failedReservoirAmount = false
                self.currentStep = self.currentStep.nextStep() ?? .done
            }
        }
    }

    func primeTube() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        loadingTubeAmount = true
        tubeDeliveredUnits = 0
        tubeProgress = 0
        currentStep = .tube
        pumpManager.enactPrime(unit: tubeAmount) { error in
            if error != nil {
                self.failedTubeAmount = true
                return
            }

            self.failedTubeAmount = false
            self.primeReporter = pumpManager.createBolusProgressReporter(reportingOn: self.processQueue)

            guard let primeReporter = self.primeReporter else {
                self.loadingPrimeAmount = false
                self.failedPrimeAmount = true
                return
            }

            primeReporter.addObserver(self)
        }
    }

    func primeCannula() {
        guard let pumpManager = self.pumpManager else {
            return
        }

        loadingPrimeAmount = true
        primeDeliveredUnits = 0
        primeProgress = 0
        currentStep = .prime
        pumpManager.enactPrime(unit: primeAmount) { error in
            if error != nil {
                self.loadingPrimeAmount = false
                self.failedPrimeAmount = true
                return
            }

            self.failedPrimeAmount = false
            self.primeReporter = pumpManager.createBolusProgressReporter(reportingOn: self.processQueue)

            guard let primeReporter = self.primeReporter else {
                self.loadingPrimeAmount = false
                self.failedPrimeAmount = true
                return
            }

            primeReporter.addObserver(self)
        }
    }
}

extension DanaKitRefillReservoirCannulaViewModel: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: any LoopKit.DoseProgressReporter) {
        switch currentStep {
        case .tube:
            tubeDeliveredUnits = doseProgressReporter.progress.deliveredUnits
            tubeProgress = doseProgressReporter.progress.percentComplete
        case .prime:
            primeDeliveredUnits = doseProgressReporter.progress.deliveredUnits
            primeProgress = doseProgressReporter.progress.percentComplete
        default:
            break
        }

        guard doseProgressReporter.progress.isComplete else {
            return
        }

        primeReporter = nil
        loadingTubeAmount = false
        loadingPrimeAmount = false
        currentStep = currentStep.nextStep() ?? .done
    }
}

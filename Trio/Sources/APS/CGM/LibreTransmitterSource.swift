import Combine
import Foundation
import LibreTransmitter
import LoopKitUI
import Swinject

protocol LibreTransmitterSource: GlucoseSource {
    var manager: LibreTransmitterManager? { get set }
}

final class BaseLibreTransmitterSource: LibreTransmitterSource, Injectable {
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .libreTransmitter

    private let processQueue = DispatchQueue(label: "BaseLibreTransmitterSource.processQueue")

    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var calibrationService: CalibrationService!

    private var promise: Future<[BloodGlucose], Error>.Promise?

    var glucoseManager: FetchGlucoseManager?

    var manager: LibreTransmitterManager? {
        didSet {
            configured = manager != nil
            manager?.cgmManagerDelegate = self
        }
    }

    @Persisted(key: "LibreTransmitterManager.configured") private(set) var configured = false

    init(resolver: Resolver) {
        if configured {
            manager = LibreTransmitterManager()
            manager?.cgmManagerDelegate = self
        }
        injectServices(resolver)
    }

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func sourceInfo() -> [String: Any]? {
        if let battery = manager?.battery {
            return ["transmitterBattery": battery]
        }
        return nil
    }
}

extension BaseLibreTransmitterSource: LibreTransmitterManagerDelegate {
    var queue: DispatchQueue { processQueue }

    func startDateToFilterNewData(for _: LibreTransmitterManager) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManager(_ manager: LibreTransmitterManager, hasNew result: Result<[LibreGlucose], Error>) {
        switch result {
        case let .success(newGlucose):
            let glucose = newGlucose.map { value -> BloodGlucose in
                BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: Int(value.glucose),
                    direction: manager.glucoseDisplay?.trendType
                        .map { .init(trendType: $0) },
                    date: Decimal(Int(value.startDate.timeIntervalSince1970 * 1000)),
                    dateString: value.startDate,
                    unfiltered: Decimal(value.unsmoothedGlucose),
                    filtered: nil,
                    noise: nil,
                    glucose: Int(value.glucose),
                    type: "sgv",
                    activationDate: value.sensorStartDate ?? manager.sensorStartDate,
                    sessionStartDate: value.sensorStartDate ?? manager.sensorStartDate,
                    transmitterID: manager.sensorSerialNumber
                )
            }
            NSLog("Debug Libre \(glucose)")
            promise?(.success(glucose))

        case let .failure(error):
            warning(.service, "LibreTransmitter error:", error: error)
            promise?(.failure(error))
        }
    }

    func overcalibration(for _: LibreTransmitterManager) -> ((Double) -> (Double))? {
        calibrationService.calibrate
    }
}

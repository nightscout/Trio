import Foundation
import LibreTransmitter
import Swinject

struct Calibration: JSON, Hashable, Identifiable {
    let x: Double
    let y: Double
    var date = Date()

    static let zero = Calibration(x: 0, y: 0)

    var id = UUID()
}

protocol CalibrationService {
    var slope: Double { get }
    var intercept: Double { get }
    var calibrations: [Calibration] { get }

    func addCalibration(_ calibration: Calibration)
    func removeCalibration(_ calibration: Calibration)
    func removeAllCalibrations()
    func removeLast()

    func calibrate(value: Int) -> Double
}

final class BaseCalibrationService: CalibrationService, Injectable {
    private enum Config {
        static let minSlope = 0.8
        static let maxSlope = 1.25
        static let minIntercept = -100.0
        static let maxIntercept = 100.0
        static let maxValue = 500.0
        static let minValue = 0.0
    }

    @Injected() var storage: FileStorage!
    @Injected() var notificationCenter: NotificationCenter!
    private var lifetime = Lifetime()

    private(set) var calibrations: [Calibration] = [] {
        didSet {
            storage.save(calibrations, as: OpenAPS.Trio.calibrations)
        }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        calibrations = storage.retrieve(OpenAPS.Trio.calibrations, as: [Calibration].self) ?? []
        subscribe()
    }

    private func subscribe() {
//        notificationCenter.publisher(for: .newSensorDetected)
//            .sink { [weak self] _ in
//                self?.removeAllCalibrations()
//            }
//            .store(in: &lifetime)
    }

    var slope: Double {
        guard calibrations.count >= 2 else {
            return 1
        }

        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)
        let sum1 = average(multiply(xs, ys)) - average(xs) * average(ys)
        let sum2 = average(multiply(xs, xs)) - pow(average(xs), 2)
        let slope = sum1 / sum2

        return min(max(slope, Config.minSlope), Config.maxSlope)
    }

    var intercept: Double {
        guard calibrations.count >= 1 else {
            return 0
        }
        let xs = calibrations.map(\.x)
        let ys = calibrations.map(\.y)

        let intercept = average(ys) - slope * average(xs)

        return min(max(intercept, Config.minIntercept), Config.maxIntercept)
    }

    func calibrate(value: Int) -> Double {
        linearRegression(value)
    }

    func addCalibration(_ calibration: Calibration) {
        calibrations.append(calibration)
    }

    func removeCalibration(_ calibration: Calibration) {
        calibrations.removeAll { $0 == calibration }
    }

    func removeAllCalibrations() {
        calibrations.removeAll()
    }

    func removeLast() {
        calibrations.removeLast()
    }

    private func average(_ input: [Double]) -> Double {
        input.reduce(0, +) / Double(input.count)
    }

    private func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(*)
    }

    private func linearRegression(_ x: Int) -> Double {
        (intercept + slope * Double(x)).clamped(Config.minValue ... Config.maxValue)
    }
}

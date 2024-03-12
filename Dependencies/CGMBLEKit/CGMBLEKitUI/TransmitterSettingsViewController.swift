//
//  TransmitterSettingsViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit
import Combine
import HealthKit
import LoopKit
import LoopKitUI
import CGMBLEKit
import ShareClientUI

class TransmitterSettingsViewController: UITableViewController {

    let cgmManager: TransmitterManager & CGMManagerUI

    private let displayGlucosePreference: DisplayGlucosePreference

    private lazy var cancellables = Set<AnyCancellable>()

    init(cgmManager: TransmitterManager & CGMManagerUI, displayGlucosePreference: DisplayGlucosePreference) {
        self.cgmManager = cgmManager
        self.displayGlucosePreference = displayGlucosePreference

        super.init(style: .grouped)

        cgmManager.addObserver(self, queue: .main)

        displayGlucosePreference.$unit
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = cgmManager.localizedTitle

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44

        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 55

        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: SwitchTableViewCell.className)
        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        self.navigationItem.setRightBarButton(button, animated: false)
    }

    @objc func doneTapped(_ sender: Any) {
        complete()
    }

    private func complete() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        if clearsSelectionOnViewWillAppear {
            // Manually invoke the delegate for rows deselecting on appear
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                _ = tableView(tableView, willDeselectRowAt: indexPath)
            }
        }

        super.viewWillAppear(animated)
    }

    // MARK: - UITableViewDataSource

    private enum Section: Int, CaseIterable {
        case transmitterID
        case remoteDataSync
        case latestReading
        case latestCalibration
        case latestConnection
        case ages
        case share
        case delete
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    private enum LatestReadingRow: Int, CaseIterable {
        case glucose
        case date
        case trend
        case status
    }

    private enum LatestCalibrationRow: Int, CaseIterable {
        case glucose
        case date
    }

    private enum LatestConnectionRow: Int, CaseIterable {
        case date
    }

    private enum AgeRow: Int, CaseIterable {
        case sensorAge
        case sensorCountdown
        case sensorExpirationDate
        case transmitter
    }

    private enum ShareRow: Int, CaseIterable {
        case settings
        case openApp
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .transmitterID:
            return 1
        case .remoteDataSync:
            return 1
        case .latestReading:
            return LatestReadingRow.allCases.count
        case .latestCalibration:
            return LatestCalibrationRow.allCases.count
        case .latestConnection:
            return LatestConnectionRow.allCases.count
        case .ages:
            return AgeRow.allCases.count
        case .share:
            return ShareRow.allCases.count
        case .delete:
            return 1
        }
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
    
    private lazy var sensorExpirationFullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        //formatter.dateStyle = .full
        //formatter.timeStyle = .short
        //formatter.doesRelativeDateFormatting = true
        formatter.setLocalizedDateFormatFromTemplate("E, MMM d, hh:mm")
        return formatter
    }()
    
    private lazy var sensorExpirationRelativeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
    
    private lazy var sensorExpirationRelativeFormatterWithTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
    
    private lazy var sensorExpAbsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        return formatter
    }()
    
    private lazy var sessionLengthFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private lazy var transmitterLengthFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        return formatter
    }()

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .transmitterID:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell

            cell.textLabel?.text = LocalizedString("Transmitter ID", comment: "The title text for the Dexcom G5/G6 transmitter ID config value")

            cell.detailTextLabel?.text = cgmManager.transmitter.ID

            return cell
        case .remoteDataSync:
            let switchCell = tableView.dequeueReusableCell(withIdentifier: SwitchTableViewCell.className, for: indexPath) as! SwitchTableViewCell

            switchCell.selectionStyle = .none
            switchCell.switch?.isOn = cgmManager.shouldSyncToRemoteService
            switchCell.textLabel?.text = LocalizedString("Upload Readings", comment: "The title text for the upload glucose switch cell")

            switchCell.switch?.addTarget(self, action: #selector(uploadEnabledChanged(_:)), for: .valueChanged)

            return switchCell
        case .latestReading:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let glucose = cgmManager.latestReading

            switch LatestReadingRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.setGlucose(glucose?.glucose, formatter: displayGlucosePreference.formatter, isDisplayOnly: glucose?.isDisplayOnly ?? false)
            case .date:
                cell.setGlucoseDate(glucose?.readDate, formatter: dateFormatter)
            case .trend:
                cell.textLabel?.text = LocalizedString("Trend", comment: "Title describing glucose trend")

                if let trendRate = glucose?.trendRate {
                    cell.detailTextLabel?.text = displayGlucosePreference.formatMinuteRate(trendRate)
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            case .status:
                cell.textLabel?.text = LocalizedString("Status", comment: "Title describing CGM calibration and battery state")

                if let stateDescription = glucose?.stateDescription, !stateDescription.isEmpty {
                    cell.detailTextLabel?.text = stateDescription
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            }

            return cell
        case .latestCalibration:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let calibration = cgmManager.latestReading?.lastCalibration

            switch LatestCalibrationRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.setGlucose(calibration?.glucose, formatter: displayGlucosePreference.formatter  , isDisplayOnly: false)
            case .date:
                cell.setGlucoseDate(calibration?.date, formatter: dateFormatter)
            }

            return cell
        case .latestConnection:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let connection = cgmManager.latestConnection

            switch LatestConnectionRow(rawValue: indexPath.row)! {
            case .date:
                cell.setGlucoseDate(connection, formatter: dateFormatter)
                cell.accessoryType = .disclosureIndicator
            }

            return cell
        case .ages:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let glucose = cgmManager.latestReading
            
            switch AgeRow(rawValue: indexPath.row)! {
            case .sensorAge:
                cell.textLabel?.text = LocalizedString("Session Age", comment: "Title describing sensor session age")
                
                if let stateDescription = glucose?.stateDescription, !stateDescription.isEmpty && !stateDescription.contains("stopped") {
                    if let sessionStart = cgmManager.latestReading?.sessionStartDate {
                        cell.detailTextLabel?.text = sessionLengthFormatter.string(from: Date().timeIntervalSince(sessionStart))
                    } else {
                        cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                    }
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
                
            case .sensorCountdown:
                cell.textLabel?.text = LocalizedString("Sensor Expires", comment: "Title describing sensor sensor expiration")
                
                if let stateDescription = glucose?.stateDescription, !stateDescription.isEmpty && !stateDescription.contains("stopped") {
                    if let sessionExp = cgmManager.latestReading?.sessionExpDate {
                        let sessionCountDown = sessionExp.timeIntervalSince(Date())
                        if sessionCountDown < 0 {
                            cell.textLabel?.text = LocalizedString("Sensor Expired", comment: "Title describing past sensor sensor expiration")
                            cell.detailTextLabel?.text = (sessionLengthFormatter.string(from: sessionCountDown * -1) ?? "") + " ago"
                        } else {
                            cell.detailTextLabel?.text = sessionLengthFormatter.string(from: sessionCountDown)
                        }
                    } else {
                        cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                    }
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
                
            case .sensorExpirationDate:
                cell.textLabel?.text = ""
                if let stateDescription = glucose?.stateDescription, !stateDescription.isEmpty && !stateDescription.contains("stopped") {
                    if let sessionExp = cgmManager.latestReading?.sessionExpDate {
                        if sensorExpirationRelativeFormatter.string(from: sessionExp) == sensorExpAbsFormatter.string(from: sessionExp) {
                            cell.detailTextLabel?.text = sensorExpirationFullFormatter.string(from: sessionExp)
                        } else {
                            cell.detailTextLabel?.text = sensorExpirationRelativeFormatterWithTime.string(from: sessionExp)
                        }
                    } else {
                        cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                    }
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            
            case .transmitter:
                cell.textLabel?.text = LocalizedString("Transmitter Age", comment: "Title describing transmitter session age")

                if let activation = cgmManager.latestReading?.activationDate {
                    cell.detailTextLabel?.text = transmitterLengthFormatter.string(from: Date().timeIntervalSince(activation))
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            }

            return cell
        case .share:
            switch ShareRow(rawValue: indexPath.row)! {
            case .settings:
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
                let service = cgmManager.shareManager.shareService

                cell.textLabel?.text = service.title
                cell.detailTextLabel?.text = service.username ?? SettingsTableViewCell.TapToSetString
                cell.accessoryType = .disclosureIndicator

                return cell
            case .openApp:
                let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)

                cell.textLabel?.text = LocalizedString("Open App", comment: "Button title to open CGM app")

                return cell
            }
        case .delete:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell

            cell.textLabel?.text = LocalizedString("Delete CGM", comment: "Title text for the button to remove a CGM from Loop")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .transmitterID:
            return nil
        case .remoteDataSync:
            return LocalizedString("Remote Data Synchronization", comment: "Section title for remote data synchronization")
        case .latestReading:
            return LocalizedString("Latest Reading", comment: "Section title for latest glucose reading")
        case .latestCalibration:
            return LocalizedString("Latest Calibration", comment: "Section title for latest glucose calibration")
        case .latestConnection:
            return LocalizedString("Latest Connection", comment: "Section title for latest connection date")
        case .ages:
            return nil
        case .share:
            return nil
        case .delete:
            return " "  // Use an empty string for more dramatic spacing
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section)! {
        case .transmitterID:
            return false
        case .remoteDataSync:
            return false
        case .latestReading:
            return false
        case .latestCalibration:
            return false
        case .latestConnection:
            return true
        case .ages:
            return false
        case .share:
            return true
        case .delete:
            return true
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if self.tableView(tableView, shouldHighlightRowAt: indexPath) {
            return indexPath
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .transmitterID:
            break
        case .remoteDataSync:
            break
        case .latestReading:
            break
        case .latestCalibration:
            break
        case .latestConnection:
            let vc = CommandResponseViewController(command: { (completionHandler) -> String in
                return String(reflecting: self.cgmManager)
            })
            vc.title = self.title
            show(vc, sender: nil)
        case .ages:
            break
        case .share:
            switch ShareRow(rawValue: indexPath.row)! {
            case .settings:
                let vc = ShareClientSettingsViewController(cgmManager: cgmManager.shareManager, displayGlucosePreference: displayGlucosePreference, allowsDeletion: false)
                show(vc, sender: nil)
                return // Don't deselect
            case .openApp:
                if let appURL = URL(string: "dexcomg6://") {
                    UIApplication.shared.open(appURL)
                }
            }
        case .delete:
            let confirmVC = UIAlertController(cgmDeletionHandler: {
                self.cgmManager.notifyDelegateOfDeletion {
                    DispatchQueue.main.async {
                        self.complete()
                    }
                }
            })

            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section)! {
        case .transmitterID:
            break
        case .remoteDataSync:
            break
        case .latestReading:
            break
        case .latestCalibration:
            break
        case .latestConnection:
            break
        case .ages:
            break
        case .share:
            switch ShareRow(rawValue: indexPath.row)! {
            case .settings:
                tableView.reloadRows(at: [indexPath], with: .fade)
            case .openApp:
                break
            }
        case .delete:
            break
        }

        return indexPath
    }
    
    @objc private func uploadEnabledChanged(_ sender: UISwitch) {
        cgmManager.shouldSyncToRemoteService = sender.isOn
    }
}


extension TransmitterSettingsViewController: TransmitterManagerObserver {
    func transmitterManagerDidUpdateLatestReading(_ manager: TransmitterManager) {
        tableView.reloadData()
    }
}


private extension UIAlertController {
    convenience init(cgmDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to delete this CGM?", comment: "Confirmation message for deleting a CGM"),
            preferredStyle: .actionSheet
        )

        addAction(UIAlertAction(
            title: LocalizedString("Delete CGM", comment: "Button title to delete CGM"),
            style: .destructive,
            handler: { (_) in
                handler()
            }
        ))

        let cancel = LocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
    }
}


private extension SettingsTableViewCell {
    func setGlucose(_ glucose: HKQuantity?, formatter: QuantityFormatter, isDisplayOnly: Bool) {
        if isDisplayOnly {
            textLabel?.text = LocalizedString("Glucose (Adjusted)", comment: "Describes a glucose value adjusted to reflect a recent calibration")
        } else {
            textLabel?.text = LocalizedString("Glucose", comment: "Title describing glucose value")
        }

        if let quantity = glucose, let formatted = formatter.string(from: quantity) {
            detailTextLabel?.text = formatted
        } else {
            detailTextLabel?.text = SettingsTableViewCell.NoValueString
        }
    }

    func setGlucoseDate(_ date: Date?, formatter: DateFormatter) {
        textLabel?.text = LocalizedString("Date", comment: "Title describing glucose date")

        if let date = date {
            detailTextLabel?.text = formatter.string(from: date)
        } else {
            detailTextLabel?.text = SettingsTableViewCell.NoValueString
        }
    }
}

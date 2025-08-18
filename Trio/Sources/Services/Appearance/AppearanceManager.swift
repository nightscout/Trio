import UIKit
protocol AppearanceManager {
    func setupGlobalAppearance()
}

final class BaseAppearanceManager: AppearanceManager {
    func setupGlobalAppearance() {
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().backgroundColor = .clear
        UITableViewHeaderFooterView.appearance().tintColor = .clear
    }
}

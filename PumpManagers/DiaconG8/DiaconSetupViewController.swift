// DiaconSetupViewController.swift
// Diacon G8 펌프 설정 화면 (BLE 스캔 및 연결)

import UIKit

class DiaconSetupViewController: UIViewController {
    var onSetupComplete: (() -> Void)?

    private let connectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Connect Diacon G8", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor.systemBlue
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Setup Diacon G8"
        view.backgroundColor = .systemBackground

        view.addSubview(connectButton)
        connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        connectButton.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        connectButton.widthAnchor.constraint(equalToConstant: 240).isActive = true
        connectButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
    }

    @objc private func connectTapped() {
        // 이 부분에 BLE 연결 로직을 구현하거나 BleManager를 활용하여 연결 시도
        // 현재는 연결 성공했다고 가정하고 완료 콜백 호출
        onSetupComplete?()
    }
}

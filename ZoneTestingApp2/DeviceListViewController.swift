//
//  DeviceListViewController.swift
//  ZoneTestingApp
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import UIKit

class DeviceListViewController: UIViewController {
    
    private var tableView: UITableView!
    private var scanButton: UIButton!
    private var clearButton: UIButton!
    private var statusLabel: UILabel!
    private var lastSessionLabel: UILabel!
    
    private let bleManager = BLEManager.shared
    private var devices: [BLEDevice] = []
    private let customNamesDefaultsKey = "CustomDeviceNames"
    
    // Last session data
    private var lastConnectionDuration: TimeInterval = 0
    private var lastWorkoutDuration: TimeInterval = 0
    private var lastDeviceName: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBLEManager()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Ensure this view controller is the delegate when it appears
        bleManager.delegate = self
        print("DeviceListViewController: Set as BLE delegate")
        
        updateScanButtonState()
        updateUI()
    }
    
    private func setupUI() {
        title = nil
        let titleLabel = UILabel()
        titleLabel.text = "Zone Devices"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 20)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.sizeToFit()
        navigationItem.titleView = titleLabel
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        
        // Create UI elements programmatically since we don't have a storyboard
        view.backgroundColor = .systemBackground
        
        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Ready to scan for Zone devices"
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 16)
        statusLabel.textColor = .systemBlue
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Last session label
        lastSessionLabel = UILabel()
        lastSessionLabel.text = ""
        lastSessionLabel.textAlignment = .center
        lastSessionLabel.font = UIFont.systemFont(ofSize: 14)
        lastSessionLabel.textColor = .systemGray
        lastSessionLabel.numberOfLines = 3
        lastSessionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lastSessionLabel)
        
        // Scan button
        scanButton = UIButton(type: .system)
        scanButton.setTitle("Scan", for: .normal)
        scanButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        scanButton.backgroundColor = .systemBlue
        scanButton.setTitleColor(.white, for: .normal)
        scanButton.layer.cornerRadius = 8
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.addTarget(self, action: #selector(scanButtonTapped), for: .touchUpInside)
        view.addSubview(scanButton)
        
        // Clear button
        clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        clearButton.backgroundColor = .systemRed
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.layer.cornerRadius = 8
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        view.addSubview(clearButton)
        
        // Table view
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DeviceTableViewCell.self, forCellReuseIdentifier: "DeviceCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Status label
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Last session label
            lastSessionLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            lastSessionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lastSessionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Scan button
            scanButton.topAnchor.constraint(equalTo: lastSessionLabel.bottomAnchor, constant: 20),
            scanButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scanButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),
            scanButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Clear button
            clearButton.topAnchor.constraint(equalTo: lastSessionLabel.bottomAnchor, constant: 20),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            clearButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),
            clearButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Table view
            tableView.topAnchor.constraint(equalTo: scanButton.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupBLEManager() {
        bleManager.delegate = self
        
        // Observe changes to discovered devices
        devices = bleManager.discoveredDevices
        print("DeviceListViewController: BLE manager setup complete")
    }

    // MARK: - Custom Names
    private func deviceKey(_ device: BLEDevice) -> String? {
        // Prefer serial number for stability, fall back to peripheral UUID
        return device.serialNumber ?? device.id
    }
    
    private func loadCustomNames() -> [String: String] {
        let dict = UserDefaults.standard.dictionary(forKey: customNamesDefaultsKey) as? [String: String]
        return dict ?? [:]
    }
    
    private func saveCustomNames(_ names: [String: String]) {
        UserDefaults.standard.set(names, forKey: customNamesDefaultsKey)
    }
    
    private func customName(for device: BLEDevice) -> String? {
        guard let key = deviceKey(device) else { return nil }
        return loadCustomNames()[key]
    }
    
    private func setCustomName(_ name: String?, for device: BLEDevice) {
        guard let key = deviceKey(device) else { return }
        var names = loadCustomNames()
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            names[key] = name
        } else {
            names.removeValue(forKey: key)
        }
        saveCustomNames(names)
        updateUI()
    }
    
    private func updateScanButtonState() {
        if bleManager.isScanning {
            scanButton.setTitle("Stop Scan", for: .normal)
            scanButton.backgroundColor = .systemOrange
        } else {
            scanButton.setTitle("Start Scan", for: .normal)
            scanButton.backgroundColor = .systemBlue
        }
    }
    
    @objc private func scanButtonTapped() {
        print("Scan button tapped - current isScanning: \(bleManager.isScanning)")
        
        if bleManager.isScanning {
            bleManager.stopScanning()
            print("Stopped scanning via button")
        } else {
            bleManager.startScanning()
            print("Started scanning via button")
        }
        
        // Update UI after a brief delay to ensure state changes are reflected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateScanButtonState()
            self.updateStatusLabel()
        }
    }
    
    @objc private func clearButtonTapped() {
        // Stop scanning if currently scanning
        if bleManager.isScanning {
            bleManager.stopScanning()
        }
        
        // Clear devices from BLE manager and local array
        bleManager.clearDevices()
        devices.removeAll()
        tableView.reloadData()
        
        // Clear last session data
        lastConnectionDuration = 0
        lastWorkoutDuration = 0
        lastDeviceName = ""
        updateLastSessionDisplay()
        
        // Update UI state after a brief delay to ensure BLE manager state is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateScanButtonState()
            self.updateStatusLabel()
        }
        
        print("Device list cleared by user")
    }
    
    private func updateStatusLabel() {
        let scanningStatus = bleManager.isScanning ? "📡 Scanning..." : "⏸️ Not scanning"
        
        print("UpdateStatusLabel - isScanning: \(bleManager.isScanning), devices count: \(devices.count)")
        
        if devices.isEmpty {
            if bleManager.isScanning {
                statusLabel.text = "\(scanningStatus)\nSearching for Zone devices..."
                statusLabel.textColor = .systemOrange
            } else {
                statusLabel.text = "\(scanningStatus)\nReady to scan for Zone devices"
                statusLabel.textColor = .systemBlue
            }
        } else {
            statusLabel.text = "\(scanningStatus)\nFound \(devices.count) Zone device(s)"
            statusLabel.textColor = bleManager.isScanning ? .systemOrange : .systemGreen
        }
    }
    
    private func updateLastSessionDisplay() {
        if lastConnectionDuration > 0 || lastWorkoutDuration > 0 {
            let connectionTime = formatTime(lastConnectionDuration)
            let workoutTime = formatTime(lastWorkoutDuration)
            lastSessionLabel.text = "Last Session: \(lastDeviceName)\nConnected: \(connectionTime)\nWorkout: \(workoutTime)"
            lastSessionLabel.textColor = .systemGray
        } else {
            lastSessionLabel.text = ""
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func updateLastSession(deviceName: String, connectionDuration: TimeInterval, workoutDuration: TimeInterval) {
        lastDeviceName = deviceName
        lastConnectionDuration = connectionDuration
        lastWorkoutDuration = workoutDuration
        updateLastSessionDisplay()
    }
    
    private func updateUI() {
        DispatchQueue.main.async {
            self.devices = self.bleManager.discoveredDevices.sorted { $0.rssi > $1.rssi }
            self.tableView.reloadData()
            self.updateStatusLabel()
        }
    }
}

// MARK: - UITableViewDataSource
extension DeviceListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath) as! DeviceTableViewCell
        let device = devices[indexPath.row]
        let displayName = customName(for: device) ?? device.name
        cell.configure(with: device, displayName: displayName)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension DeviceListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let device = devices[indexPath.row]
        print("DeviceListViewController: User selected device: \(device.name)")
        print("DeviceListViewController: Current BLE manager isConnected: \(bleManager.isConnected)")

        statusLabel.text = "Connecting to \(customName(for: device) ?? device.name)..."

        bleManager.connect(to: device)
        print("DeviceListViewController: Called bleManager.connect()")
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - BLEManagerDelegate
extension DeviceListViewController: BLEManagerDelegate {
    func didDiscoverDevice(_ device: BLEDevice) {
        print("DeviceListViewController: Discovered device: \(device.name)")
        updateUI()
    }
    
    func didConnectToDevice(_ device: BLEDevice) {
        print("DeviceListViewController: Connected to device: \(device.name)")
        DispatchQueue.main.async {
            self.statusLabel.text = "Connected to \(device.name)"
            
            // Navigate to workout control screen
            let workoutVC = WorkoutControlViewController()
            workoutVC.connectedDevice = device
            print("DeviceListViewController: Navigating to workout control screen")
            self.navigationController?.pushViewController(workoutVC, animated: true)
        }
    }
    
    func didDisconnectFromDevice(_ device: BLEDevice) {
        print("DeviceListViewController: Disconnected from device: \(device.name)")
        DispatchQueue.main.async {
            self.statusLabel.text = "Disconnected from \(device.name)"
        }
    }
    
    func didFailToConnect(_ device: BLEDevice, error: Error?) {
        print("DeviceListViewController: Failed to connect to device: \(device.name), error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            self.statusLabel.text = "Failed to connect to \(device.name)"
            
            let alert = UIAlertController(title: "Connection Failed", 
                                        message: "Could not connect to \(device.name). \(error?.localizedDescription ?? "")", 
                                        preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    func didUpdateSerialNumber(_ device: BLEDevice) {
        print("DeviceListViewController: Updated serial number for device: \(device.name)")
        updateUI()
    }

    func didUpdateFirmwareVersion(_ device: BLEDevice, version: String) {
        // Not shown on this screen; handled in workout controller
        print("DeviceListViewController: Firmware version for \(device.name): \(version)")
    }

    func didUpdateBatteryLevel(_ device: BLEDevice, percent: Int) {
        // Not displayed here
        print("DeviceListViewController: Battery for \(device.name): \(percent)%")
    }
}

// MARK: - Custom Table View Cell
class DeviceTableViewCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let serialLabel = UILabel()
    private let rssiLabel = UILabel()
    private let signalImageView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        // Name label
        nameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        nameLabel.textColor = .label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        
        // Serial number label
        serialLabel.font = UIFont.systemFont(ofSize: 14)
        serialLabel.textColor = .systemBlue
        serialLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(serialLabel)
        
        // RSSI label
        rssiLabel.font = UIFont.systemFont(ofSize: 14)
        rssiLabel.textColor = .secondaryLabel
        rssiLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rssiLabel)

        // Signal strength image
        signalImageView.contentMode = .scaleAspectFit
        signalImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(signalImageView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: signalImageView.leadingAnchor, constant: -8),
            
            serialLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            serialLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            serialLabel.trailingAnchor.constraint(equalTo: signalImageView.leadingAnchor, constant: -8),
            
            rssiLabel.topAnchor.constraint(equalTo: serialLabel.bottomAnchor, constant: 2),
            rssiLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rssiLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            signalImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            signalImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            signalImageView.widthAnchor.constraint(equalToConstant: 24),
            signalImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    func configure(with device: BLEDevice, displayName: String? = nil) {
        nameLabel.text = displayName ?? device.name
        
        // Use the serial number from the Device Information Service
        if let serialNumber = device.serialNumber {
            serialLabel.text = "Serial: \(serialNumber)"
        } else {
            serialLabel.text = "Serial: Reading..."
        }
        
        rssiLabel.text = "RSSI: \(device.rssi) dBm"
        
        // Set signal strength icon based on RSSI
        let signalStrength = getSignalStrength(rssi: device.rssi)
        signalImageView.image = UIImage(systemName: signalStrength.iconName)
        signalImageView.tintColor = signalStrength.color
    }
    
    private func getSignalStrength(rssi: Int) -> (iconName: String, color: UIColor) {
        switch rssi {
        case -50...0:
            return ("wifi", .systemGreen)
        case -70..<(-50):
            return ("wifi", .systemYellow)
        case -90..<(-70):
            return ("wifi", .systemOrange)
        default:
            return ("wifi", .systemRed)
        }
    }
} 
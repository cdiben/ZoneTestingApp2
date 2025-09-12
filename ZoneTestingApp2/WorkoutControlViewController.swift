//
//  WorkoutControlViewController.swift
//  ZoneTestingApp
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import UIKit
import UniformTypeIdentifiers

class WorkoutControlViewController: UIViewController {
    
    var connectedDevice: BLEDevice?
    
    private let bleManager = BLEManager.shared
    private var deviceNameLabel: UILabel!
    private var firmwareVersionLabel: UILabel!
    private var connectionStatusLabel: UILabel!
    
    private var startWorkoutButton: UIButton!
    private var stopWorkoutButton: UIButton!
    private var disconnectButton: UIButton!
    private var commandStatusLabel: UILabel!
    private var updateFirmwareButton: UIButton!
    private var firmwareProgressLabel: UILabel!
    private var batteryLabel: UILabel!
    private var blueLedButton: UIButton!
    private var backToScanButton: UIButton!
    
    // Track last two commands and replies for on-screen log
    private var recentSentCommands: [String] = []
    private var recentReplies: [String] = []
    
    // Recording state for workout byte stream
    private var isRecordingWorkout: Bool = false
    private var isAwaitingStartAck: Bool = false
    private var recordedWorkoutData: Data = Data()
    private var workoutStartDate: Date?
    // Track intent for document picker (firmware vs export)
    private var isSelectingFirmwareFile: Bool = false
    private var isExportingWorkoutFile: Bool = false
    private var exportShouldPopToScan: Bool = false
    // Streaming parser buffers for timestamped samples
    private var streamAssemblyBuffer: [UInt8] = []
    private var capturedSamples: [(timestamp: UInt32, bytes: [UInt8])] = []
    // Incremental recording to file
    private var recordingFileURL: URL?
    private var recordingFileHandle: FileHandle?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBLEManager()
        
        print("WorkoutControlViewController: View loaded for device: \(connectedDevice?.name ?? "Unknown")")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Set this view controller as the delegate when it appears
        bleManager.delegate = self
        print("WorkoutControlViewController: Set as BLE delegate")
        
        updateConnectionStatus()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        print("WorkoutControlViewController: View will disappear")
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Device name label
        deviceNameLabel = UILabel()
        deviceNameLabel.text = connectedDevice?.name ?? "Unknown Device"
        deviceNameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        deviceNameLabel.textAlignment = .center
        deviceNameLabel.textColor = .label
        deviceNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deviceNameLabel)
        deviceNameLabel.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(renameDeviceTapped))
        deviceNameLabel.addGestureRecognizer(tapGesture)

        // Firmware version label
        firmwareVersionLabel = UILabel()
        firmwareVersionLabel.text = ""
        firmwareVersionLabel.font = UIFont.systemFont(ofSize: 14)
        firmwareVersionLabel.textAlignment = .center
        firmwareVersionLabel.textColor = .secondaryLabel
        firmwareVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(firmwareVersionLabel)
        
        // Connection status label
        connectionStatusLabel = UILabel()
        connectionStatusLabel.text = "Connected"
        connectionStatusLabel.font = UIFont.systemFont(ofSize: 18)
        connectionStatusLabel.textAlignment = .center
        connectionStatusLabel.textColor = .systemGreen
        connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionStatusLabel)
        
        
        
        // Start workout button
        startWorkoutButton = UIButton(type: .system)
        startWorkoutButton.setTitle("Start Workout", for: .normal)
        startWorkoutButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
        startWorkoutButton.backgroundColor = .systemGreen
        startWorkoutButton.setTitleColor(.white, for: .normal)
        startWorkoutButton.layer.cornerRadius = 12
        startWorkoutButton.translatesAutoresizingMaskIntoConstraints = false
        startWorkoutButton.addTarget(self, action: #selector(startWorkoutTapped), for: .touchUpInside)
        view.addSubview(startWorkoutButton)
        
        // Stop workout button
        stopWorkoutButton = UIButton(type: .system)
        stopWorkoutButton.setTitle("Stop Workout", for: .normal)
        stopWorkoutButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
        stopWorkoutButton.backgroundColor = .systemRed
        stopWorkoutButton.setTitleColor(.white, for: .normal)
        stopWorkoutButton.layer.cornerRadius = 12
        stopWorkoutButton.translatesAutoresizingMaskIntoConstraints = false
        stopWorkoutButton.addTarget(self, action: #selector(stopWorkoutTapped), for: .touchUpInside)
        view.addSubview(stopWorkoutButton)
        
        // Command status label
        commandStatusLabel = UILabel()
        commandStatusLabel.text = "Ready to send commands"
        commandStatusLabel.font = UIFont.systemFont(ofSize: 16)
        commandStatusLabel.textAlignment = .center
        commandStatusLabel.textColor = .systemBlue
        commandStatusLabel.numberOfLines = 0
        commandStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commandStatusLabel)
        
        // Disconnect button
        disconnectButton = UIButton(type: .system)
        disconnectButton.setTitle("Disconnect", for: .normal)
        disconnectButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        disconnectButton.backgroundColor = .systemOrange
        disconnectButton.setTitleColor(.white, for: .normal)
        disconnectButton.layer.cornerRadius = 10
        disconnectButton.translatesAutoresizingMaskIntoConstraints = false
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
        view.addSubview(disconnectButton)

        // Update Firmware button
        updateFirmwareButton = UIButton(type: .system)
        updateFirmwareButton.setTitle("Update Firmware", for: .normal)
        updateFirmwareButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        updateFirmwareButton.backgroundColor = .systemIndigo
        updateFirmwareButton.setTitleColor(.white, for: .normal)
        updateFirmwareButton.layer.cornerRadius = 10
        updateFirmwareButton.translatesAutoresizingMaskIntoConstraints = false
        updateFirmwareButton.addTarget(self, action: #selector(updateFirmwareTapped), for: .touchUpInside)
        view.addSubview(updateFirmwareButton)

        // Firmware progress label
        firmwareProgressLabel = UILabel()
        firmwareProgressLabel.text = ""
        firmwareProgressLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        firmwareProgressLabel.textAlignment = .center
        firmwareProgressLabel.textColor = .systemIndigo
        firmwareProgressLabel.numberOfLines = 2
        firmwareProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(firmwareProgressLabel)

        // Battery label
        batteryLabel = UILabel()
        batteryLabel.text = "Battery: --%"
        batteryLabel.font = UIFont.systemFont(ofSize: 14)
        batteryLabel.textAlignment = .center
        batteryLabel.textColor = .label
        batteryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(batteryLabel)

        // Blue LED button
        blueLedButton = UIButton(type: .system)
        blueLedButton.setTitle("Blue LED", for: .normal)
        blueLedButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        blueLedButton.backgroundColor = .systemBlue
        blueLedButton.setTitleColor(.white, for: .normal)
        blueLedButton.layer.cornerRadius = 10
        blueLedButton.translatesAutoresizingMaskIntoConstraints = false
        blueLedButton.addTarget(self, action: #selector(blueLedTapped), for: .touchUpInside)
        view.addSubview(blueLedButton)

        // Back to Scan button (top-left)
        backToScanButton = UIButton(type: .system)
        backToScanButton.setTitle("Back to Scan", for: .normal)
        backToScanButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        backToScanButton.setTitleColor(.systemBlue, for: .normal)
        backToScanButton.translatesAutoresizingMaskIntoConstraints = false
        backToScanButton.addTarget(self, action: #selector(backToScanTapped), for: .touchUpInside)
        view.addSubview(backToScanButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Device name label
            deviceNameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            deviceNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            deviceNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Firmware version label
            firmwareVersionLabel.topAnchor.constraint(equalTo: deviceNameLabel.bottomAnchor, constant: 4),
            firmwareVersionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            firmwareVersionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Battery label (moved under firmware version)
            batteryLabel.topAnchor.constraint(equalTo: firmwareVersionLabel.bottomAnchor, constant: 6),
            batteryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            batteryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Connection status label
            connectionStatusLabel.topAnchor.constraint(equalTo: batteryLabel.bottomAnchor, constant: 10),
            connectionStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectionStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            

            // Firmware progress label moved under Stop Workout and above command status
            firmwareProgressLabel.topAnchor.constraint(equalTo: stopWorkoutButton.bottomAnchor, constant: 10),
            firmwareProgressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            firmwareProgressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Start workout button (now directly below connection status with extra spacing)
            startWorkoutButton.topAnchor.constraint(equalTo: connectionStatusLabel.bottomAnchor, constant: 80),
            startWorkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            startWorkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            startWorkoutButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Stop workout button
            stopWorkoutButton.topAnchor.constraint(equalTo: startWorkoutButton.bottomAnchor, constant: 20),
            stopWorkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stopWorkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            stopWorkoutButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Command status label (now below firmware status)
            commandStatusLabel.topAnchor.constraint(equalTo: firmwareProgressLabel.bottomAnchor, constant: 10),
            commandStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            commandStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Disconnect button
            disconnectButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            disconnectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            disconnectButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            disconnectButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Place firmware button above disconnect button
        NSLayoutConstraint.activate([
            updateFirmwareButton.bottomAnchor.constraint(equalTo: disconnectButton.topAnchor, constant: -16),
            updateFirmwareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            updateFirmwareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            updateFirmwareButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // (Battery label is constrained near the top above)

        // Blue LED button constraints (place just above Start Workout button, matching spacing)
        NSLayoutConstraint.activate([
            blueLedButton.bottomAnchor.constraint(equalTo: startWorkoutButton.topAnchor, constant: -16),
            blueLedButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            blueLedButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            blueLedButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Back to Scan button constraints (top-left)
        NSLayoutConstraint.activate([
            backToScanButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backToScanButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12)
        ])
        
        // Add some visual enhancements
        addButtonShadows()
    }
    
    private func addButtonShadows() {
        let buttons = [startWorkoutButton, stopWorkoutButton, disconnectButton, updateFirmwareButton, blueLedButton]
        
        for button in buttons {
            button?.layer.shadowColor = UIColor.black.cgColor
            button?.layer.shadowOffset = CGSize(width: 0, height: 2)
            button?.layer.shadowOpacity = 0.2
            button?.layer.shadowRadius = 4
        }
    }
    
    private func setupBLEManager() {
        bleManager.delegate = self
        bleManager.firmwareDelegate = self
    }

    @objc private func renameDeviceTapped() {
        guard let device = connectedDevice else { return }
        let alert = UIAlertController(title: "Rename Device", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Enter name"
            textField.text = self.loadCustomNames()[self.deviceKey(device) ?? ""] ?? device.name
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let name = alert.textFields?.first?.text
            self.setCustomName(name, for: device)
            self.deviceNameLabel.text = name?.isEmpty == false ? name : device.name
        }))
        present(alert, animated: true)
    }

    private func deviceKey(_ device: BLEDevice) -> String? {
        return device.serialNumber ?? device.id
    }
    private func loadCustomNames() -> [String: String] {
        let dict = UserDefaults.standard.dictionary(forKey: "CustomDeviceNames") as? [String: String]
        return dict ?? [:]
    }
    private func saveCustomNames(_ names: [String: String]) {
        UserDefaults.standard.set(names, forKey: "CustomDeviceNames")
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
    }
    
    // MARK: - Timer Management
    
    private func stopAllTimers() {}
    
    private func updateConnectionStatus() {
        if bleManager.isConnected {
            connectionStatusLabel.text = "Connected"
            connectionStatusLabel.textColor = .systemGreen
            startWorkoutButton.isEnabled = true
            stopWorkoutButton.isEnabled = true
            startWorkoutButton.alpha = 1.0
            stopWorkoutButton.alpha = 1.0
        } else {
            connectionStatusLabel.text = "Disconnected"
            connectionStatusLabel.textColor = .systemRed
            startWorkoutButton.isEnabled = false
            stopWorkoutButton.isEnabled = false
            startWorkoutButton.alpha = 0.5
            stopWorkoutButton.alpha = 0.5
        }
    }
    
    @objc private func startWorkoutTapped() {
        guard bleManager.isConnected else {
            showAlert(title: "Not Connected", message: "Device is not connected")
            return
        }
        
        // Send set time first, then start workout
        bleManager.setTimeThenStartWorkout()
        commandStatusLabel.text = "Sent: Set Time (0x4004 + 4 bytes), then Start (0x4008)"
        commandStatusLabel.textColor = .systemGreen
        
        // Add visual feedback
        animateButton(startWorkoutButton)
    }
    
    @objc private func stopWorkoutTapped() {
        guard bleManager.isConnected else {
            showAlert(title: "Not Connected", message: "Device is not connected")
            return
        }
        
        bleManager.stopWorkout()
        commandStatusLabel.text = "Sent: Stop Workout (0x4009)"
        commandStatusLabel.textColor = .systemRed
        
        // Add visual feedback
        animateButton(stopWorkoutButton)
    }
    
    @objc private func disconnectTapped() {
        // If already disconnected or no peripheral, just go back to scan
        if !bleManager.isConnected {
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(title: "Disconnect Device",
                                      message: "Are you sure you want to disconnect from \(connectedDevice?.name ?? "this device")?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { _ in
            self.stopAllTimers()
            self.bleManager.disconnect()
        })
        present(alert, animated: true)
    }

    @objc private func backToScanTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func updateFirmwareTapped() {
        if bleManager.isFirmwareUpdating {
            // Stop update
            bleManager.cancelFirmwareUpdate()
            updateFirmwareButton.setTitle("Update Firmware", for: .normal)
            updateFirmwareButton.backgroundColor = .systemIndigo
        } else {
            isSelectingFirmwareFile = true
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data])
            picker.allowsMultipleSelection = false
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    @objc private func blueLedTapped() {
        guard bleManager.isConnected else {
            showAlert(title: "Not Connected", message: "Device is not connected")
            return
        }
        bleManager.sendBlueLedCommand()
        commandStatusLabel.text = "Sent: Blue LED (0x4021 4B 00 00 00 32)"
        commandStatusLabel.textColor = .systemBlue
        animateButton(blueLedButton)
    }
    
    private func animateButton(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = CGAffineTransform.identity
            }
        }
    }
    
    private func stopRecordingAndPromptSave() {
        // End any pending start state
        isAwaitingStartAck = false
        guard !recordedWorkoutData.isEmpty || !capturedSamples.isEmpty else {
            showAlert(title: "No BLE Data", message: "")
            // Reset state
            isRecordingWorkout = false
            workoutStartDate = nil
            recordedWorkoutData.removeAll(keepingCapacity: false)
            capturedSamples.removeAll(keepingCapacity: false)
            streamAssemblyBuffer.removeAll(keepingCapacity: false)
            closeIncrementalRecording()
            return
        }
        // Ask user whether to save or discard
        let confirm = UIAlertController(title: "Save Data?", message: "Would you like to save the workout data?", preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { _ in
            // Discard data and reset state
            self.isRecordingWorkout = false
            self.workoutStartDate = nil
            self.recordedWorkoutData.removeAll(keepingCapacity: false)
            self.capturedSamples.removeAll(keepingCapacity: false)
            self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
            self.closeIncrementalRecording(deleteFile: true)
            // Stay on workout screen (user stayed connected)
        }))
        confirm.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            // Capture data and date, then reset state before exporting
            let dataToSave = self.recordedWorkoutData
            let samplesToSave = self.capturedSamples
            let exportStartDate = self.workoutStartDate
            self.isRecordingWorkout = false
            self.workoutStartDate = nil
            self.recordedWorkoutData.removeAll(keepingCapacity: false)
            self.capturedSamples.removeAll(keepingCapacity: false)
            self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
            let incrementalURL = self.recordingFileURL
            self.closeIncrementalRecording()
            // Build filename
            let formatter = DateFormatter()
            formatter.dateFormat = "MMddyyyy_HHmm"
            let stamp = formatter.string(from: exportStartDate ?? Date())
            let serialDigits = (self.connectedDevice?.serialNumber ?? "").filter { $0.isNumber }
            let lastFiveRaw = String(serialDigits.suffix(5))
            let lastFive = (lastFiveRaw.count < 5) ? String(repeating: "0", count: 5 - lastFiveRaw.count) + lastFiveRaw : lastFiveRaw
            let fileName = "ZonePcks_\(lastFive)_\(stamp).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                // If we have an incremental file, prefer that; else compose from memory
                if let incURL = incrementalURL, FileManager.default.fileExists(atPath: incURL.path) {
                    // Move/rename the incremental file to final name
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.moveItem(at: incURL, to: tempURL)
                } else {
                    // Compose from in-memory samples as fallback
                    var lines: [String] = []
                    if !samplesToSave.isEmpty {
                        lines = samplesToSave.map { sample in
                            let tsStr = String(sample.timestamp)
                            let hex = sample.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                            return tsStr + "," + hex
                        }
                    } else {
                        let bytes = [UInt8](dataToSave)
                        var index = 0
                        let sampleLength = 83
                        while index + sampleLength <= bytes.count {
                            if bytes[index] == 0x40 && bytes[index + 1] == 0xE1 {
                                let sample = bytes[index..<(index + sampleLength)]
                                let tsStr = String(UInt32(Date().timeIntervalSince1970))
                                let hex = sample.map { String(format: "%02X", $0) }.joined(separator: " ")
                                lines.append(tsStr + "," + hex)
                                index += sampleLength
                            } else {
                                index += 1
                            }
                        }
                    }
                    guard !lines.isEmpty else {
                        self.showAlert(title: "No BLE Data", message: "")
                        return
                    }
                    let csvString = lines.joined(separator: "\n") + "\n"
                    let csvData = Data(csvString.utf8)
                    try csvData.write(to: tempURL, options: .atomic)
                }
                let picker = UIDocumentPickerViewController(forExporting: [tempURL])
                picker.allowsMultipleSelection = false
                picker.delegate = self
                self.isSelectingFirmwareFile = false
                self.isExportingWorkoutFile = true
                self.exportShouldPopToScan = false
                self.present(picker, animated: true)
            } catch {
                self.showAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }))
        present(confirm, animated: true)
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r\t")
        let cleanedScalars = name.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined()
        return cleanedScalars.isEmpty ? "workout" : cleanedScalars
    }
    
    // MARK: - Incremental Recording Helpers
    private func startIncrementalRecording() {
        // Close previous if any
        closeIncrementalRecording()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMddyyyy_HHmm"
        let stamp = formatter.string(from: Date())
        let serialDigits = (self.connectedDevice?.serialNumber ?? "").filter { $0.isNumber }
        let lastFiveRaw = String(serialDigits.suffix(5))
        let lastFive = (lastFiveRaw.count < 5) ? String(repeating: "0", count: 5 - lastFiveRaw.count) + lastFiveRaw : lastFiveRaw
        let tempName = "ZonePcks_\(lastFive)_\(stamp)_recording.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(tempName)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: url)
            recordingFileURL = url
            recordingFileHandle = handle
        } catch {
            recordingFileURL = nil
            recordingFileHandle = nil
        }
    }
    
    private func appendSampleToRecordingFile(timestamp: UInt32, bytes: [UInt8]) {
        guard let handle = recordingFileHandle else { return }
        let tsStr = String(timestamp)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let line = tsStr + "," + hex + "\n"
        if let data = line.data(using: .utf8) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Ignore write errors silently during capture
            }
        }
    }
    
    private func closeIncrementalRecording(deleteFile: Bool = false) {
        if let handle = recordingFileHandle {
            try? handle.close()
        }
        if deleteFile, let url = recordingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingFileHandle = nil
        recordingFileURL = nil
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    deinit {
        stopAllTimers()
    }
}

// MARK: - BLEManagerDelegate
extension WorkoutControlViewController: BLEManagerDelegate {
    func didDiscoverDevice(_ device: BLEDevice) {
        // Not needed in this view controller
        print("WorkoutControlViewController: Discovered device (unexpected): \(device.name)")
    }
    
    func didConnectToDevice(_ device: BLEDevice) {
        print("WorkoutControlViewController: Connected to device: \(device.name)")
        DispatchQueue.main.async {
            self.updateConnectionStatus()
            self.commandStatusLabel.text = "Connected! Ready to send commands"
            self.commandStatusLabel.textColor = .systemBlue
            // Use custom name if available
            let names = UserDefaults.standard.dictionary(forKey: "CustomDeviceNames") as? [String: String] ?? [:]
            let key = device.serialNumber ?? device.id
            self.deviceNameLabel.text = names[key] ?? device.name
        }
    }

    func didSendCommand(_ command: [UInt8]) {
        let hex = command.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        DispatchQueue.main.async {
            // Recognize workout start/stop commands to control recording lifecycle
            let startBytes: [UInt8] = [0x40, 0x08, 0x08, 0x07]
            let stopBytes: [UInt8] = [0x40, 0x09]
            if command == startBytes {
                self.isAwaitingStartAck = true
                self.isRecordingWorkout = false
                self.recordedWorkoutData.removeAll(keepingCapacity: false)
                self.workoutStartDate = nil
                self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
                self.capturedSamples.removeAll(keepingCapacity: false)
                // Prepare incremental file
                self.startIncrementalRecording()
            }
            if command == stopBytes {
                if self.isRecordingWorkout || self.isAwaitingStartAck {
                    self.stopRecordingAndPromptSave()
                }
            }
            // Maintain stack of last two commands
            self.recentSentCommands.insert("Sent: \(hex)", at: 0)
            if self.recentSentCommands.count > 2 { self.recentSentCommands.removeLast() }
            // Compose with last two replies
            let combined = zip(self.recentSentCommands, self.recentReplies + ["", ""]).map { sent, reply in
                reply.isEmpty ? sent : "\(sent)\nReply: \(reply)"
            }
            self.commandStatusLabel.text = combined.prefix(2).joined(separator: "\n")
            self.commandStatusLabel.textColor = .systemGreen
        }
    }

    func didReceiveReply(_ bytes: [UInt8]) {
        let hex = bytes.map { String(format: "0x%02X", $0) }.joined(separator: " ")
        DispatchQueue.main.async {
            // Start recording after the first reply following Start command.
            // Do NOT write the 0x40 0x88 0x00 start-ack bytes; only record data after it.
            var payloadToAppend: [UInt8] = bytes
            if self.isAwaitingStartAck {
                self.isAwaitingStartAck = false
                self.isRecordingWorkout = true
                self.workoutStartDate = Date()
                let startAck: [UInt8] = [0x40, 0x88, 0x00]
                if bytes.count >= startAck.count && Array(bytes.prefix(startAck.count)) == startAck {
                    payloadToAppend = Array(bytes.dropFirst(startAck.count))
                }
            }
            if self.isRecordingWorkout && !payloadToAppend.isEmpty {
                // Append to raw buffer (legacy)
                self.recordedWorkoutData.append(contentsOf: payloadToAppend)
                // Feed streaming parser to extract 83-byte samples prefixed by 0x40 0xE1
                self.streamAssemblyBuffer.append(contentsOf: payloadToAppend)
                let sampleLength = 83
                // scan for headers; produce samples up to last complete one, keep remainder in buffer
                var i = 0
                while i + 2 <= self.streamAssemblyBuffer.count {
                    if self.streamAssemblyBuffer[i] == 0x40 && self.streamAssemblyBuffer[i+1] == 0xE1 {
                        if i + sampleLength <= self.streamAssemblyBuffer.count {
                            let sample = Array(self.streamAssemblyBuffer[i..<(i + sampleLength)])
                            // capture epoch seconds (UInt32, truncating)
                            let ts = UInt32(Date().timeIntervalSince1970)
                            self.capturedSamples.append((timestamp: ts, bytes: sample))
                            // Append incrementally to file as CSV line: ts,HEX...
                            self.appendSampleToRecordingFile(timestamp: ts, bytes: sample)
                            i += sampleLength
                        } else {
                            // wait for more bytes to complete this sample
                            break
                        }
                    } else {
                        i += 1
                    }
                }
                if i > 0 {
                    self.streamAssemblyBuffer.removeFirst(i)
                }
            }
            self.recentReplies.insert(hex, at: 0)
            if self.recentReplies.count > 2 { self.recentReplies.removeLast() }
            // Re-compose with sends
            let combined = zip(self.recentSentCommands + ["", ""], self.recentReplies).map { sent, reply in
                sent.isEmpty ? "Reply: \(reply)" : "\(sent)\nReply: \(reply)"
            }
            self.commandStatusLabel.text = combined.prefix(2).joined(separator: "\n")
            self.commandStatusLabel.textColor = .systemGreen
        }
    }
    
    func didDisconnectFromDevice(_ device: BLEDevice) {
        print("WorkoutControlViewController: Disconnected from device: \(device.name)")
        DispatchQueue.main.async {
            // Pass timer values back to device list
            if let deviceListVC = self.navigationController?.viewControllers.first as? DeviceListViewController {
                deviceListVC.updateLastSession(
                    deviceName: device.name,
                    connectionDuration: 0,
                    workoutDuration: 0
                )
                print("WorkoutControlViewController: Updated last session data")
            }
            
            // If we have unsaved data, offer to save before leaving
            if !self.recordedWorkoutData.isEmpty {
                self.isAwaitingStartAck = false
                let confirm = UIAlertController(title: "Save Data?", message: "Device disconnected. Save the recorded data?", preferredStyle: .alert)
                confirm.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { _ in
                    // Discard data and reset, then navigate back
                    self.isRecordingWorkout = false
                    self.workoutStartDate = nil
                    self.recordedWorkoutData.removeAll(keepingCapacity: false)
                    self.capturedSamples.removeAll(keepingCapacity: false)
                    self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
                    self.closeIncrementalRecording(deleteFile: true)
                    print("WorkoutControlViewController: Discarded unsaved data after disconnect")
                    self.navigationController?.popViewController(animated: true)
                }))
                confirm.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
                    // Capture data and date, then reset state before exporting
                    let dataToSave = self.recordedWorkoutData
                    let samplesToSave = self.capturedSamples
                    let exportStartDate = self.workoutStartDate
                    self.isRecordingWorkout = false
                    self.workoutStartDate = nil
                    self.recordedWorkoutData.removeAll(keepingCapacity: false)
                    self.capturedSamples.removeAll(keepingCapacity: false)
                    self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
                    let incrementalURL = self.recordingFileURL
                    self.closeIncrementalRecording()
                    // Build filename
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMddyyyy_HHmm"
                    let stamp = formatter.string(from: exportStartDate ?? Date())
                    let serialDigits = (self.connectedDevice?.serialNumber ?? "").filter { $0.isNumber }
                    let lastFiveRaw = String(serialDigits.suffix(5))
                    let lastFive = (lastFiveRaw.count < 5) ? String(repeating: "0", count: 5 - lastFiveRaw.count) + lastFiveRaw : lastFiveRaw
                    let fileName = "ZonePcks_\(lastFive)_\(stamp).csv"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    do {
                        // Prefer incremental file if present
                        if let incURL = incrementalURL, FileManager.default.fileExists(atPath: incURL.path) {
                            try? FileManager.default.removeItem(at: tempURL)
                            try FileManager.default.moveItem(at: incURL, to: tempURL)
                        } else {
                            // Compose from memory with epoch prefix
                            var lines: [String] = []
                            if !samplesToSave.isEmpty {
                                lines = samplesToSave.map { sample in
                                    let tsStr = String(sample.timestamp)
                                    let hex = sample.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                                    return tsStr + "," + hex
                                }
                            } else {
                                let bytes = [UInt8](dataToSave)
                                var index = 0
                                let sampleLength = 83
                                while index + sampleLength <= bytes.count {
                                    if bytes[index] == 0x40 && bytes[index + 1] == 0xE1 {
                                        let sample = bytes[index..<(index + sampleLength)]
                                        let tsStr = String(UInt32(Date().timeIntervalSince1970))
                                        let hex = sample.map { String(format: "%02X", $0) }.joined(separator: " ")
                                        lines.append(tsStr + "," + hex)
                                        index += sampleLength
                                    } else {
                                        index += 1
                                    }
                                }
                            }
                            if lines.isEmpty {
                                self.showAlert(title: "No BLE Data", message: "")
                                return
                            }
                            let csvString = lines.joined(separator: "\n") + "\n"
                            let csvData = Data(csvString.utf8)
                            try csvData.write(to: tempURL, options: .atomic)
                        }
                        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
                        picker.allowsMultipleSelection = false
                        picker.delegate = self
                        self.isSelectingFirmwareFile = false
                        self.isExportingWorkoutFile = true
                        self.exportShouldPopToScan = true
                        self.present(picker, animated: true)
                    } catch {
                        self.showAlert(title: "Save Failed", message: error.localizedDescription)
                    }
                }))
                self.present(confirm, animated: true)
            } else {
                // Navigate back to device list
                print("WorkoutControlViewController: Navigating back to device list")
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    func didFailToConnect(_ device: BLEDevice, error: Error?) {
        print("WorkoutControlViewController: Failed to connect to device: \(device.name), error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            // Pass timer values back to device list
            if let deviceListVC = self.navigationController?.viewControllers.first as? DeviceListViewController {
                deviceListVC.updateLastSession(
                    deviceName: device.name,
                    connectionDuration: 0,
                    workoutDuration: 0
                )
                print("WorkoutControlViewController: Updated last session data after failure")
            }
            
            self.showAlert(title: "Connection Lost", 
                          message: "Lost connection to \(device.name). \(error?.localizedDescription ?? "")")
        }
    }
    
    func didUpdateSerialNumber(_ device: BLEDevice) {
        print("WorkoutControlViewController: Updated serial number for device: \(device.name)")
        // Update the connected device if it matches
        if connectedDevice?.id == device.id {
            connectedDevice = device
            // Refresh displayed name using saved custom name keyed by serial if available
            let names = UserDefaults.standard.dictionary(forKey: "CustomDeviceNames") as? [String: String] ?? [:]
            let key = device.serialNumber ?? device.id
            let display = names[key] ?? device.name
            DispatchQueue.main.async {
                self.deviceNameLabel.text = display
            }
        }
    }

    func didUpdateFirmwareVersion(_ device: BLEDevice, version: String) {
        guard connectedDevice?.id == device.id else { return }
        DispatchQueue.main.async {
            self.firmwareVersionLabel.text = "Firmware: \(version)"
        }
    }
} 

// MARK: - Firmware Delegate
extension WorkoutControlViewController: BLEFirmwareUpdateDelegate {
    func firmwareUpdateProgress(bytesSent: Int, totalBytes: Int) {
        DispatchQueue.main.async {
            let percent = totalBytes > 0 ? Int((Double(bytesSent) / Double(totalBytes)) * 100.0) : 0
            self.firmwareProgressLabel.text = "Firmware Update: \(bytesSent)/\(totalBytes) (\(percent)%)"
            if self.bleManager.isFirmwareUpdating {
                self.updateFirmwareButton.setTitle("Stop Update", for: .normal)
                self.updateFirmwareButton.backgroundColor = .systemRed
            }
        }
    }
    
    func firmwareUpdateCompleted() {
        DispatchQueue.main.async {
            self.firmwareProgressLabel.text = "Firmware Update: Completed"
            self.updateFirmwareButton.setTitle("Update Firmware", for: .normal)
            self.updateFirmwareButton.backgroundColor = .systemIndigo
        }
    }
    
    func firmwareUpdateFailed(error: String) {
        DispatchQueue.main.async {
            self.firmwareProgressLabel.text = "Firmware Update: Failed - \(error)"
            self.updateFirmwareButton.setTitle("Update Firmware", for: .normal)
            self.updateFirmwareButton.backgroundColor = .systemIndigo
        }
    }
}

// MARK: - Document Picker
extension WorkoutControlViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // If this callback is for export, just dismiss and go back to scan screen
        if isExportingWorkoutFile {
            let shouldPop = exportShouldPopToScan
            isExportingWorkoutFile = false
            exportShouldPopToScan = false
            if shouldPop {
                self.navigationController?.popViewController(animated: true)
            }
            return
        }
        guard isSelectingFirmwareFile else { return }
        guard let url = urls.first else { return }
        var data: Data?
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                data = try Data(contentsOf: coordinatedURL)
            } catch {
                data = nil
            }
        }
        if data == nil {
            // Fallback: copy to a temporary location and read
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                data = try Data(contentsOf: tempURL)
            } catch {
                data = nil
            }
        }
        if let rawData = data {
            let effectiveData = parseHexFileIfNeeded(rawData)
            firmwareProgressLabel.text = "Firmware file loaded: \(effectiveData.count) bytes"
            let first5 = [UInt8](effectiveData.prefix(5)).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("Firmware first 5 bytes: \(first5)")
            bleManager.startFirmwareUpdate(with: effectiveData)
        } else {
            let message = coordinatorError?.localizedDescription ?? "The file could not be opened."
            firmwareProgressLabel.text = "Failed to load file: \(message)"
        }
        isSelectingFirmwareFile = false
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if isExportingWorkoutFile {
            let shouldPop = exportShouldPopToScan
            isExportingWorkoutFile = false
            exportShouldPopToScan = false
            if shouldPop {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
}

// MARK: - Battery Updates
extension WorkoutControlViewController {
    func didUpdateBatteryLevel(_ device: BLEDevice, percent: Int) {
        guard connectedDevice?.id == device.id else { return }
        DispatchQueue.main.async {
            self.batteryLabel.text = "Battery: \(percent)%"
        }
    }
}
 
private extension WorkoutControlViewController {
    func parseHexFileIfNeeded(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFabcdefxX:-_,; \n\r\t")
        let isHexLike = text.unicodeScalars.allSatisfy { allowed.contains($0) }
        guard isHexLike else { return data }
        var cleaned = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
        let hexSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        cleaned = String(cleaned.unicodeScalars.filter { hexSet.contains($0) })
        guard cleaned.count >= 2, cleaned.count % 2 == 0 else { return data }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            let byteStr = cleaned[idx..<next]
            if let value = UInt8(byteStr, radix: 16) {
                bytes.append(value)
            } else {
                return data
            }
            idx = next
        }
        return Data(bytes)
    }
}

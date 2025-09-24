//
//  WorkoutControlViewController.swift
//  ZoneTestingApp
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import UIKit
import AudioToolbox
import AVFoundation
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
    private var liveDataToggleButton: UIButton!
    private var batteryButton: UIButton!
    private var liveDataContainerView: UIView!
    private var liveDataStackView: UIStackView!
    private var triggerSettingsButton: UIButton!
    private var triggersPanelView: UIView!
    private var hrTriggerSwitch: UISwitch!
    private var algoTriggerSwitch: UISwitch!
    private var hrResetLabel: UILabel!
    private var hrResetTriggerSwitch: UISwitch!
    private var algorithmValueLabel: UILabel!
    private var heartRateValueLabel: UILabel!
    private var hrConfValueLabel: UILabel!
    private var skinDetectValueLabel: UILabel!
    private var isLiveDataVisible: Bool = false
    private let speechSynth = AVSpeechSynthesizer()
    private var lastAlarmSpokenAt: Date?
    private let alarmCooldownSeconds: TimeInterval = 8.0
    // Trigger enable flags (default off)
    private var isHRTriggerEnabled: Bool = false
    private var isAlgorithmTriggerEnabled: Bool = false
    private var isHRResetTriggerEnabled: Bool = false
    
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
    // Reconnect management for unexpected disconnects
    private var pendingReconnectDevice: BLEDevice?
    private var reconnectDeadline: Date?
    private var reconnectTimer: Timer?
    private var isAttemptingReconnect: Bool = false
    private var forcePopToScanOnSave: Bool = false
    private var reconnectAlert: UIAlertController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBLEManager()
        
        print("WorkoutControlViewController: View loaded for device: \(connectedDevice?.name ?? "Unknown")")
        // Configure audio session so alerts play audibly (and mix with other audio)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal; continue without special audio session
        }
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

        // Trigger settings button (top-right, square like Live)
        triggerSettingsButton = UIButton(type: .system)
        triggerSettingsButton.setTitle("Trig", for: .normal)
        triggerSettingsButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        triggerSettingsButton.setTitleColor(.white, for: .normal)
        triggerSettingsButton.backgroundColor = .systemIndigo
        triggerSettingsButton.layer.cornerRadius = 8
        triggerSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        triggerSettingsButton.addTarget(self, action: #selector(triggerSettingsTapped), for: .touchUpInside)
        view.addSubview(triggerSettingsButton)

        // Live Data toggle button
        liveDataToggleButton = UIButton(type: .system)
        liveDataToggleButton.setTitle("Live", for: .normal)
        liveDataToggleButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        liveDataToggleButton.backgroundColor = .systemBlue
        liveDataToggleButton.setTitleColor(.white, for: .normal)
        liveDataToggleButton.layer.cornerRadius = 8
        liveDataToggleButton.translatesAutoresizingMaskIntoConstraints = false
        liveDataToggleButton.addTarget(self, action: #selector(toggleLiveDataTapped), for: .touchUpInside)
        // Debug: long-press to play test beep
        let liveLongPress = UILongPressGestureRecognizer(target: self, action: #selector(debugBeepGesture(_:)))
        liveLongPress.minimumPressDuration = 0.5
        liveDataToggleButton.addGestureRecognizer(liveLongPress)
        liveDataToggleButton.isHidden = true
        view.addSubview(liveDataToggleButton)

        // Live Data container
        liveDataContainerView = UIView()
        liveDataContainerView.backgroundColor = UIColor.secondarySystemBackground
        liveDataContainerView.layer.cornerRadius = 10
        liveDataContainerView.layer.borderColor = UIColor.separator.cgColor
        liveDataContainerView.layer.borderWidth = 1
        liveDataContainerView.isHidden = true
        liveDataContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(liveDataContainerView)

        // Triggers panel (hidden by default)
        triggersPanelView = UIView()
        triggersPanelView.backgroundColor = .secondarySystemBackground
        triggersPanelView.layer.cornerRadius = 10
        triggersPanelView.layer.borderColor = UIColor.separator.cgColor
        triggersPanelView.layer.borderWidth = 1
        triggersPanelView.isHidden = true
        triggersPanelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(triggersPanelView)

        let hrLabel = UILabel()
        hrLabel.text = "HR"
        hrLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        hrLabel.translatesAutoresizingMaskIntoConstraints = false
        hrTriggerSwitch = UISwitch()
        hrTriggerSwitch.isOn = isHRTriggerEnabled
        hrTriggerSwitch.addTarget(self, action: #selector(hrSwitchChanged(_:)), for: .valueChanged)
        hrTriggerSwitch.translatesAutoresizingMaskIntoConstraints = false

        let algoLabel = UILabel()
        algoLabel.text = "Alg=8"
        algoLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        algoLabel.translatesAutoresizingMaskIntoConstraints = false
        algoTriggerSwitch = UISwitch()
        algoTriggerSwitch.isOn = isAlgorithmTriggerEnabled
        algoTriggerSwitch.addTarget(self, action: #selector(algoSwitchChanged(_:)), for: .valueChanged)
        algoTriggerSwitch.translatesAutoresizingMaskIntoConstraints = false

        triggersPanelView.addSubview(hrLabel)
        triggersPanelView.addSubview(hrTriggerSwitch)
        triggersPanelView.addSubview(algoLabel)
        triggersPanelView.addSubview(algoTriggerSwitch)
        // HR=10 Reset controls
        hrResetLabel = UILabel()
        hrResetLabel.text = "HR=10 Reset"
        hrResetLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        hrResetLabel.translatesAutoresizingMaskIntoConstraints = false
        hrResetTriggerSwitch = UISwitch()
        hrResetTriggerSwitch.isOn = isHRResetTriggerEnabled
        hrResetTriggerSwitch.addTarget(self, action: #selector(hrResetSwitchChanged(_:)), for: .valueChanged)
        hrResetTriggerSwitch.translatesAutoresizingMaskIntoConstraints = false
        triggersPanelView.addSubview(hrResetLabel)
        triggersPanelView.addSubview(hrResetTriggerSwitch)

        func makeValueLabel(_ title: String) -> UILabel {
            let label = UILabel()
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            label.textColor = .label
            label.text = "\(title): --"
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }
        func makeLargeValueLabel(_ title: String) -> UILabel {
            let label = UILabel()
            // Make value big, header small on first line
            let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold)
            let headerFont = UIFont.systemFont(ofSize: 10, weight: .regular)
            let header = NSAttributedString(string: "\(title)\n", attributes: [.font: headerFont, .foregroundColor: UIColor.secondaryLabel])
            let value = NSAttributedString(string: "--", attributes: [.font: valueFont, .foregroundColor: UIColor.label])
            let combined = NSMutableAttributedString()
            combined.append(header)
            combined.append(value)
            label.attributedText = combined
            label.textAlignment = .center
            label.numberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }
        algorithmValueLabel = makeLargeValueLabel("Algorithm")
        heartRateValueLabel = makeLargeValueLabel("Heart Rate")
        hrConfValueLabel = makeLargeValueLabel("HR Conf")
        skinDetectValueLabel = makeLargeValueLabel("Skin Detect")
        liveDataStackView = UIStackView(arrangedSubviews: [algorithmValueLabel, heartRateValueLabel, hrConfValueLabel, skinDetectValueLabel])
        liveDataStackView.axis = .horizontal
        liveDataStackView.distribution = .fillEqually
        liveDataStackView.alignment = .fill
        liveDataStackView.spacing = 12
        liveDataStackView.translatesAutoresizingMaskIntoConstraints = false
        liveDataContainerView.addSubview(liveDataStackView)
        
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
            
            // Start workout button now below live data container for more space
            startWorkoutButton.topAnchor.constraint(equalTo: liveDataContainerView.bottomAnchor, constant: 16),
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

        // Live Data toggle top-right and square
        NSLayoutConstraint.activate([
            liveDataToggleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            liveDataToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            liveDataToggleButton.widthAnchor.constraint(equalToConstant: 44),
            liveDataToggleButton.heightAnchor.constraint(equalTo: liveDataToggleButton.widthAnchor)
        ])

        // Battery (Bat) button under Live
        batteryButton = UIButton(type: .system)
        batteryButton.setTitle("Bat", for: .normal)
        batteryButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        batteryButton.backgroundColor = .systemGray
        batteryButton.setTitleColor(.white, for: .normal)
        batteryButton.layer.cornerRadius = 8
        batteryButton.translatesAutoresizingMaskIntoConstraints = false
        batteryButton.addTarget(self, action: #selector(batteryTapped), for: .touchUpInside)
        view.addSubview(batteryButton)
        NSLayoutConstraint.activate([
            batteryButton.topAnchor.constraint(equalTo: liveDataToggleButton.bottomAnchor, constant: 8),
            batteryButton.centerXAnchor.constraint(equalTo: liveDataToggleButton.centerXAnchor),
            batteryButton.widthAnchor.constraint(equalToConstant: 44),
            batteryButton.heightAnchor.constraint(equalTo: batteryButton.widthAnchor)
        ])

        // Trigger settings button to the left of Live
        NSLayoutConstraint.activate([
            triggerSettingsButton.centerYAnchor.constraint(equalTo: liveDataToggleButton.centerYAnchor),
            triggerSettingsButton.trailingAnchor.constraint(equalTo: liveDataToggleButton.leadingAnchor, constant: -12),
            triggerSettingsButton.widthAnchor.constraint(equalToConstant: 44),
            triggerSettingsButton.heightAnchor.constraint(equalTo: triggerSettingsButton.widthAnchor)
        ])

        // Live Data container constraints
        NSLayoutConstraint.activate([
            liveDataContainerView.topAnchor.constraint(equalTo: connectionStatusLabel.bottomAnchor, constant: 8),
            liveDataContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            liveDataContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
        // Triggers panel constraints (below the buttons row)
        NSLayoutConstraint.activate([
            triggersPanelView.topAnchor.constraint(equalTo: liveDataContainerView.bottomAnchor, constant: 8),
            triggersPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            triggersPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            // Make the panel taller while keeping its top fixed
            triggersPanelView.heightAnchor.constraint(equalToConstant: 120)
        ])
        NSLayoutConstraint.activate([
            // HR controls on the left (extra top spacing)
            hrLabel.topAnchor.constraint(equalTo: triggersPanelView.topAnchor, constant: 20),
            hrLabel.leadingAnchor.constraint(equalTo: triggersPanelView.leadingAnchor, constant: 12),
            hrTriggerSwitch.centerYAnchor.constraint(equalTo: hrLabel.centerYAnchor),
            hrTriggerSwitch.leadingAnchor.constraint(equalTo: hrLabel.trailingAnchor, constant: 8),

            // Algorithm controls on the right
            algoTriggerSwitch.centerYAnchor.constraint(equalTo: hrLabel.centerYAnchor),
            algoTriggerSwitch.trailingAnchor.constraint(equalTo: triggersPanelView.trailingAnchor, constant: -12),
            algoLabel.centerYAnchor.constraint(equalTo: hrLabel.centerYAnchor),
            algoLabel.trailingAnchor.constraint(equalTo: algoTriggerSwitch.leadingAnchor, constant: -8),

            // Second row: HR=10 Reset aligned below first row
            hrResetLabel.topAnchor.constraint(equalTo: hrLabel.bottomAnchor, constant: 16),
            hrResetLabel.leadingAnchor.constraint(equalTo: triggersPanelView.leadingAnchor, constant: 12),
            hrResetTriggerSwitch.centerYAnchor.constraint(equalTo: hrResetLabel.centerYAnchor),
            hrResetTriggerSwitch.leadingAnchor.constraint(equalTo: hrResetLabel.trailingAnchor, constant: 8),

            // Panel bottom padding (allow extra space)
            hrResetLabel.bottomAnchor.constraint(lessThanOrEqualTo: triggersPanelView.bottomAnchor, constant: -12)
        ])
        // Stack fills container with padding
        NSLayoutConstraint.activate([
            liveDataStackView.topAnchor.constraint(equalTo: liveDataContainerView.topAnchor, constant: 8),
            liveDataStackView.leadingAnchor.constraint(equalTo: liveDataContainerView.leadingAnchor, constant: 8),
            liveDataStackView.trailingAnchor.constraint(equalTo: liveDataContainerView.trailingAnchor, constant: -8),
            liveDataStackView.bottomAnchor.constraint(equalTo: liveDataContainerView.bottomAnchor, constant: -8)
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
            // Ensure Live button is visible when connected
            liveDataToggleButton.isHidden = false
        } else {
            connectionStatusLabel.text = "Disconnected"
            connectionStatusLabel.textColor = .systemRed
            startWorkoutButton.isEnabled = false
            stopWorkoutButton.isEnabled = false
            startWorkoutButton.alpha = 0.5
            stopWorkoutButton.alpha = 0.5
            // Hide Live UI when disconnected
            liveDataToggleButton.isHidden = true
            isLiveDataVisible = false
            liveDataContainerView.isHidden = true
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
    
    @objc private func batteryTapped() {
        guard bleManager.isConnected else {
            showAlert(title: "Not Connected", message: "Device is not connected")
            return
        }
        bleManager.requestBatteryLevel()
    }
    
    @objc private func toggleLiveDataTapped() {
        isLiveDataVisible.toggle()
        liveDataContainerView.isHidden = !isLiveDataVisible
        liveDataToggleButton.backgroundColor = isLiveDataVisible ? .systemGreen : .systemBlue
    }

    @objc private func triggerSettingsTapped() {
        // Toggle panel visibility; stays open until user taps button again
        let willShow = triggersPanelView.isHidden
        triggersPanelView.isHidden = !willShow
        // Keep switches in sync with current state
        hrTriggerSwitch.isOn = isHRTriggerEnabled
        algoTriggerSwitch.isOn = isAlgorithmTriggerEnabled
        hrResetTriggerSwitch.isOn = isHRResetTriggerEnabled
    }

    @objc private func hrSwitchChanged(_ sender: UISwitch) {
        isHRTriggerEnabled = sender.isOn
    }

    @objc private func algoSwitchChanged(_ sender: UISwitch) {
        isAlgorithmTriggerEnabled = sender.isOn
    }

    @objc private func hrResetSwitchChanged(_ sender: UISwitch) {
        isHRResetTriggerEnabled = sender.isOn
    }

    @objc private func debugBeepGesture(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            // Debug: if algorithm trigger is enabled, test that; else test HR trigger
            if isAlgorithmTriggerEnabled {
                playAlgorithmAlarm(ignoreCooldown: true)
            } else {
                playHeartRateAlarm(ignoreCooldown: true)
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
                        let sampleLength = 100
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
    
    private func dismissReconnectAlertIfShowing() {
        if let a = reconnectAlert {
            a.dismiss(animated: true)
            reconnectAlert = nil
        } else if let presented = self.presentedViewController as? UIAlertController,
                  presented.title == "Reconnecting..." {
            presented.dismiss(animated: true)
            reconnectAlert = nil
        }
    }
    
    private func updateLiveDataView(with sample: [UInt8]) {
        // Ensure sample has at least the original 83 bytes (new bytes are appended at the end)
        guard sample.count >= 83 else { return }
        // Byte indices are 1-based in description; adjust for 0-based array
        // 64th byte -> index 63
        let algorithm = Int(sample[63])
        // Next two bytes (65th, 66th) MSB first -> indices 64, 65
        let hrRaw: Int = (Int(sample[64]) << 8) | Int(sample[65])
        let heartRate: Int = hrRaw / 10
        // Next byte (67th) -> index 66
        let hrConf = Int(sample[66])
        // 83rd byte -> index 82 (unchanged; extra bytes are appended beyond this)
        let skinDetect = Int(sample[82])
        func setAttributed(_ label: UILabel, header: String, value: String) {
            let headerAttr = NSAttributedString(string: "\(header)\n", attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ])
            let valueAttr = NSAttributedString(string: value, attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor.label
            ])
            let combined = NSMutableAttributedString()
            combined.append(headerAttr)
            combined.append(valueAttr)
            label.attributedText = combined
        }
        setAttributed(algorithmValueLabel, header: "Algorithm", value: "\(algorithm)")
        setAttributed(heartRateValueLabel, header: "Heart Rate", value: "\(heartRate)")
        setAttributed(hrConfValueLabel, header: "HR Conf", value: "\(hrConf)")
        setAttributed(skinDetectValueLabel, header: "Skin Detect", value: "\(skinDetect)")
        // Play longer alarm sound if HR out of range and live view is visible
        if isLiveDataVisible && isHRTriggerEnabled && ((heartRate > 0 && heartRate < 40) || heartRate > 200) {
            playHeartRateAlarm(ignoreCooldown: false)
        }
        if isLiveDataVisible && isHRResetTriggerEnabled && heartRate == 10 {
            playHeartRateAlarm(ignoreCooldown: false)
        }
        if isLiveDataVisible && isAlgorithmTriggerEnabled && algorithm == 8 {
            playAlgorithmAlarm(ignoreCooldown: false)
        }
    }

    private func playHeartRateAlarm(ignoreCooldown: Bool) {
        let now = Date()
        if ignoreCooldown || lastAlarmSpokenAt == nil || now.timeIntervalSince(lastAlarmSpokenAt!) > alarmCooldownSeconds {
            lastAlarmSpokenAt = now
            let utterance = AVSpeechUtterance(string: "Heart rate alert")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.45
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0
            speechSynth.speak(utterance)
            // Also trigger system alert sound as fallback
            AudioServicesPlayAlertSound(1005)
        }
    }

    private func playAlgorithmAlarm(ignoreCooldown: Bool) {
        let now = Date()
        if ignoreCooldown || lastAlarmSpokenAt == nil || now.timeIntervalSince(lastAlarmSpokenAt!) > alarmCooldownSeconds {
            lastAlarmSpokenAt = now
            let utterance = AVSpeechUtterance(string: "Algorithm eight alert")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.45
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0
            speechSynth.speak(utterance)
            AudioServicesPlayAlertSound(1005)
        }
    }
    
    // MARK: - Reconnect logic on unexpected disconnect
    private func presentReconnectAlertAndStartLoop() {
        reconnectTimer?.invalidate()
        guard let target = pendingReconnectDevice else { return }
        // Present non-blocking alert with Cancel option
        let alert = UIAlertController(title: "Reconnecting...",
                                      message: "Attempting to reconnect to the device. You can stop and save now.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Stop and Save", style: .destructive, handler: { _ in
            self.reconnectTimer?.invalidate()
            self.isAttemptingReconnect = false
            self.pendingReconnectDevice = nil
            self.dismissReconnectAlertIfShowing()
            self.presentSaveAfterReconnectFailure()
        }))
        self.reconnectAlert = alert
        present(alert, animated: true)
        attemptReconnect(to: target)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.bleManager.isConnected {
                // Reconnected; dismiss alert and continue
                timer.invalidate()
                self.isAttemptingReconnect = false
                self.pendingReconnectDevice = nil
                self.dismissReconnectAlertIfShowing()
                return
            }
            // Keep attempting reconnect until user cancels
            self.attemptReconnect(to: target)
        }
    }
    
    private func attemptReconnect(to device: BLEDevice) {
        // If we still have the peripheral reference, ask BLEManager to connect without timeout UX
        bleManager.connect(to: device, isReconnect: true)
    }
    
    private func presentSaveAfterReconnectFailure() {
        // Reuse the same save dialog but ensure we pop to scan after export
        guard !recordedWorkoutData.isEmpty || !capturedSamples.isEmpty else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        isAwaitingStartAck = false
        let confirm = UIAlertController(title: "Save Data?", message: "Could not reconnect. Save the recorded data?", preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { _ in
            self.isRecordingWorkout = false
            self.workoutStartDate = nil
            self.recordedWorkoutData.removeAll(keepingCapacity: false)
            self.capturedSamples.removeAll(keepingCapacity: false)
            self.streamAssemblyBuffer.removeAll(keepingCapacity: false)
            self.closeIncrementalRecording(deleteFile: true)
            self.navigationController?.popViewController(animated: true)
        }))
        confirm.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
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
            let formatter = DateFormatter()
            formatter.dateFormat = "MMddyyyy_HHmm"
            let stamp = formatter.string(from: exportStartDate ?? Date())
            let serialDigits = (self.connectedDevice?.serialNumber ?? "").filter { $0.isNumber }
            let lastFiveRaw = String(serialDigits.suffix(5))
            let lastFive = (lastFiveRaw.count < 5) ? String(repeating: "0", count: 5 - lastFiveRaw.count) + lastFiveRaw : lastFiveRaw
            let fileName = "ZonePcks_\(lastFive)_\(stamp).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                if let incURL = incrementalURL, FileManager.default.fileExists(atPath: incURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.moveItem(at: incURL, to: tempURL)
                } else {
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
                        let sampleLength = 100
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
                self.exportShouldPopToScan = true
                self.present(picker, animated: true)
            } catch {
                self.showAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }))
        present(confirm, animated: true)
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
            // If we were showing reconnect alert, dismiss it now
            self.dismissReconnectAlertIfShowing()
            // Use custom name if available
            let names = UserDefaults.standard.dictionary(forKey: "CustomDeviceNames") as? [String: String] ?? [:]
            let key = device.serialNumber ?? device.id
            self.deviceNameLabel.text = names[key] ?? device.name
            // Show Live button on connection
            self.liveDataToggleButton.isHidden = false
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
                let sampleLength = 100
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
                            // Ensure toggle button appears as soon as 40 E1 data is seen
                            // Live button now shows on connect; no-op here
                            // Update live data view if visible
                            if self.isLiveDataVisible {
                                self.updateLiveDataView(with: sample)
                            }
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
            
            // If we have unsaved data, attempt reconnect for up to 3 minutes before prompting to save
            if !self.recordedWorkoutData.isEmpty || !self.capturedSamples.isEmpty {
                self.isAwaitingStartAck = false
                self.pendingReconnectDevice = device
                self.isAttemptingReconnect = true
                self.forcePopToScanOnSave = true
                self.presentReconnectAlertAndStartLoop()
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
            // Suppress user-facing alerts during our reconnect attempts
            if self.isAttemptingReconnect {
                return
            }
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
    func didUpdateBatteryLevel(_ device: BLEDevice, percent: Int, voltage: Double) {
        guard connectedDevice?.id == device.id else { return }
        DispatchQueue.main.async {
            let voltageStr = String(format: "%.3fV", voltage)
            self.batteryLabel.text = "Battery: \(percent)%  \(voltageStr)"
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

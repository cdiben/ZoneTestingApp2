//
//  WorkoutControlViewController.swift
//  ZoneTestingApp
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import UIKit

class WorkoutControlViewController: UIViewController {
    
    var connectedDevice: BLEDevice?
    
    private let bleManager = BLEManager.shared
    private var deviceNameLabel: UILabel!
    private var connectionStatusLabel: UILabel!
    private var connectionTimerLabel: UILabel!
    private var workoutTimerLabel: UILabel!
    private var startWorkoutButton: UIButton!
    private var stopWorkoutButton: UIButton!
    private var disconnectButton: UIButton!
    private var commandStatusLabel: UILabel!
    
    // Timer properties
    private var connectionTimer: Timer?
    private var workoutTimer: Timer?
    private var connectionStartTime: Date?
    private var workoutStartTime: Date?
    private var isWorkoutActive = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBLEManager()
        startConnectionTimer()
        print("WorkoutControlViewController: View loaded for device: \(connectedDevice?.name ?? "Unknown")")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Set this view controller as the delegate when it appears
        bleManager.delegate = self
        print("WorkoutControlViewController: Set as BLE delegate")
        
        updateConnectionStatus()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("WorkoutControlViewController: View will disappear")
    }
    
    private func setupUI() {
        title = "Workout Control"
        view.backgroundColor = .systemBackground
        
        // Device name label
        deviceNameLabel = UILabel()
        deviceNameLabel.text = connectedDevice?.name ?? "Unknown Device"
        deviceNameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        deviceNameLabel.textAlignment = .center
        deviceNameLabel.textColor = .label
        deviceNameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deviceNameLabel)
        
        // Connection status label
        connectionStatusLabel = UILabel()
        connectionStatusLabel.text = "Connected"
        connectionStatusLabel.font = UIFont.systemFont(ofSize: 18)
        connectionStatusLabel.textAlignment = .center
        connectionStatusLabel.textColor = .systemGreen
        connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionStatusLabel)
        
        // Connection timer label
        connectionTimerLabel = UILabel()
        connectionTimerLabel.text = "Connected: 00:00:00"
        connectionTimerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        connectionTimerLabel.textAlignment = .center
        connectionTimerLabel.textColor = .systemBlue
        connectionTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionTimerLabel)
        
        // Workout timer label
        workoutTimerLabel = UILabel()
        workoutTimerLabel.text = "Workout: 00:00:00"
        workoutTimerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        workoutTimerLabel.textAlignment = .center
        workoutTimerLabel.textColor = .systemGray
        workoutTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(workoutTimerLabel)
        
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
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Device name label
            deviceNameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            deviceNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            deviceNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Connection status label
            connectionStatusLabel.topAnchor.constraint(equalTo: deviceNameLabel.bottomAnchor, constant: 10),
            connectionStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectionStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Connection timer label
            connectionTimerLabel.topAnchor.constraint(equalTo: connectionStatusLabel.bottomAnchor, constant: 15),
            connectionTimerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectionTimerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Workout timer label
            workoutTimerLabel.topAnchor.constraint(equalTo: connectionTimerLabel.bottomAnchor, constant: 10),
            workoutTimerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            workoutTimerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Start workout button
            startWorkoutButton.topAnchor.constraint(equalTo: workoutTimerLabel.bottomAnchor, constant: 40),
            startWorkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            startWorkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            startWorkoutButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Stop workout button
            stopWorkoutButton.topAnchor.constraint(equalTo: startWorkoutButton.bottomAnchor, constant: 20),
            stopWorkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stopWorkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            stopWorkoutButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Command status label
            commandStatusLabel.topAnchor.constraint(equalTo: stopWorkoutButton.bottomAnchor, constant: 30),
            commandStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            commandStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Disconnect button
            disconnectButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            disconnectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            disconnectButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            disconnectButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Add some visual enhancements
        addButtonShadows()
    }
    
    private func addButtonShadows() {
        let buttons = [startWorkoutButton, stopWorkoutButton, disconnectButton]
        
        for button in buttons {
            button?.layer.shadowColor = UIColor.black.cgColor
            button?.layer.shadowOffset = CGSize(width: 0, height: 2)
            button?.layer.shadowOpacity = 0.2
            button?.layer.shadowRadius = 4
        }
    }
    
    private func setupBLEManager() {
        bleManager.delegate = self
    }
    
    // MARK: - Timer Management
    
    private func startConnectionTimer() {
        connectionStartTime = Date()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateConnectionTimerDisplay()
        }
        print("Connection timer started")
    }
    
    private func startWorkoutTimer() {
        workoutStartTime = Date()
        workoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateWorkoutTimerDisplay()
        }
        isWorkoutActive = true
        workoutTimerLabel.textColor = .systemGreen
        print("Workout timer started")
    }
    
    private func stopWorkoutTimer() {
        workoutTimer?.invalidate()
        workoutTimer = nil
        isWorkoutActive = false
        workoutTimerLabel.textColor = .systemGray
        print("Workout timer stopped")
    }
    
    private func stopAllTimers() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectionStartTime = nil
        
        workoutTimer?.invalidate()
        workoutTimer = nil
        workoutStartTime = nil
        isWorkoutActive = false
        
        print("All timers stopped")
    }
    
    private func updateConnectionTimerDisplay() {
        guard let startTime = connectionStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        connectionTimerLabel.text = "Connected: \(formatTime(elapsed))"
    }
    
    private func updateWorkoutTimerDisplay() {
        guard let startTime = workoutStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        workoutTimerLabel.text = "Workout: \(formatTime(elapsed))"
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
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
        startWorkoutTimer()
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
        stopWorkoutTimer()
        commandStatusLabel.text = "Sent: Stop Workout (0x4009)"
        commandStatusLabel.textColor = .systemRed
        
        // Add visual feedback
        animateButton(stopWorkoutButton)
    }
    
    @objc private func disconnectTapped() {
        let alert = UIAlertController(title: "Disconnect Device", 
                                    message: "Are you sure you want to disconnect from \(connectedDevice?.name ?? "this device")?", 
                                    preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { _ in
            // Calculate final timer values before stopping
            let finalConnectionDuration = self.connectionStartTime?.timeIntervalSinceNow.magnitude ?? 0
            let finalWorkoutDuration = self.workoutStartTime?.timeIntervalSinceNow.magnitude ?? 0
            
            // Pass timer values back to device list
            if let deviceListVC = self.navigationController?.viewControllers.first as? DeviceListViewController,
               let deviceName = self.connectedDevice?.name {
                deviceListVC.updateLastSession(
                    deviceName: deviceName,
                    connectionDuration: finalConnectionDuration,
                    workoutDuration: finalWorkoutDuration
                )
            }
            
            self.stopAllTimers()
            self.bleManager.disconnect()
        })
        
        present(alert, animated: true)
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
        }
    }
    
    func didDisconnectFromDevice(_ device: BLEDevice) {
        print("WorkoutControlViewController: Disconnected from device: \(device.name)")
        DispatchQueue.main.async {
            // Calculate final timer values before stopping
            let finalConnectionDuration = self.connectionStartTime?.timeIntervalSinceNow.magnitude ?? 0
            let finalWorkoutDuration = self.workoutStartTime?.timeIntervalSinceNow.magnitude ?? 0
            
            self.stopAllTimers()
            self.updateConnectionStatus()
            self.commandStatusLabel.text = "Device disconnected"
            self.commandStatusLabel.textColor = .systemRed
            
            // Pass timer values back to device list
            if let deviceListVC = self.navigationController?.viewControllers.first as? DeviceListViewController {
                deviceListVC.updateLastSession(
                    deviceName: device.name,
                    connectionDuration: finalConnectionDuration,
                    workoutDuration: finalWorkoutDuration
                )
                print("WorkoutControlViewController: Updated last session data")
            }
            
            // Navigate back to device list
            print("WorkoutControlViewController: Navigating back to device list")
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    func didFailToConnect(_ device: BLEDevice, error: Error?) {
        print("WorkoutControlViewController: Failed to connect to device: \(device.name), error: \(error?.localizedDescription ?? "Unknown")")
        DispatchQueue.main.async {
            // Calculate final timer values before stopping
            let finalConnectionDuration = self.connectionStartTime?.timeIntervalSinceNow.magnitude ?? 0
            let finalWorkoutDuration = self.workoutStartTime?.timeIntervalSinceNow.magnitude ?? 0
            
            self.stopAllTimers()
            self.updateConnectionStatus()
            
            // Pass timer values back to device list
            if let deviceListVC = self.navigationController?.viewControllers.first as? DeviceListViewController {
                deviceListVC.updateLastSession(
                    deviceName: device.name,
                    connectionDuration: finalConnectionDuration,
                    workoutDuration: finalWorkoutDuration
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
        }
    }
} 
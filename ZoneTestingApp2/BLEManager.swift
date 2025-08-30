//
//  BLEManager.swift
//  ZoneTestingApp
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import Foundation
import CoreBluetooth

protocol BLEManagerDelegate: AnyObject {
    func didDiscoverDevice(_ device: BLEDevice)
    func didConnectToDevice(_ device: BLEDevice)
    func didDisconnectFromDevice(_ device: BLEDevice)
    func didFailToConnect(_ device: BLEDevice, error: Error?)
    func didUpdateSerialNumber(_ device: BLEDevice)
}

struct BLEDevice {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    var serialNumber: String?
    
    var id: String {
        return peripheral.identifier.uuidString
    }
}

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var connectionTimer: Timer?
    private var updateTimer: Timer?
    private var pendingDevices: [BLEDevice] = []
    
    weak var delegate: BLEManagerDelegate?
    
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var isScanning = false
    @Published var isConnected = false
    
    // Commands to send
    private let startWorkoutCommand: [UInt8] = [0x40, 0x08]
    private let stopWorkoutCommand: [UInt8] = [0x40, 0x09]
    private let setTimeCommandPrefix: [UInt8] = [0x40, 0x04]
    
    // Common BLE service UUIDs that might be used for fitness devices
    private let commonServiceUUIDs: [CBUUID] = [
        CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), // Nordic UART Service
        CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB"), // Battery Service
        CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB"), // Device Information Service
        CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")  // Common custom service
    ]
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { 
            print("Bluetooth is not powered on")
            return 
        }
        
        // Stop any existing scan first
        if isScanning {
            centralManager.stopScan()
        }
        
        isScanning = true
        // Scan for all devices with allow duplicates to ensure fresh discovery
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        
        // Start update timer to throttle UI updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.processPendingDevices()
        }
        
        print("Started scanning for devices...")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        updateTimer?.invalidate()
        updateTimer = nil
        print("Stopped scanning")
        
        // Process any remaining pending devices
        processPendingDevices()
        
        // Notify on main queue to ensure UI updates
        DispatchQueue.main.async {
            // This ensures any UI observing isScanning gets updated
        }
    }
    
    private func processPendingDevices() {
        guard !pendingDevices.isEmpty else { return }
        
        // Update discovered devices with the latest values from pending devices
        for pendingDevice in pendingDevices {
            if let existingIndex = self.discoveredDevices.firstIndex(where: { $0.id == pendingDevice.id }) {
                // Update existing device with new RSSI value, keep existing serial number
                var updatedDevice = pendingDevice
                updatedDevice.serialNumber = self.discoveredDevices[existingIndex].serialNumber
                self.discoveredDevices[existingIndex] = updatedDevice
            } else {
                // Add new device
                self.discoveredDevices.append(pendingDevice)
            }
        }
        
        // Clear pending devices
        pendingDevices.removeAll()
        
        // Notify delegate on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.didDiscoverDevice(self.discoveredDevices.last!)
        }
    }
    
    func clearDevices() {
        // Stop scanning first
        if isScanning {
            stopScanning()
        }
        
        // Clear the discovered devices array
        discoveredDevices.removeAll()
        
        // Force a brief delay before allowing new scans to ensure iOS clears its cache
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("Device list cleared and ready for fresh scan")
        }
    }
    
    func connect(to device: BLEDevice) {
        stopScanning()
        print("Attempting to connect to \(device.name)...")
        
        // Set a connection timeout
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            print("Connection timeout")
            self.centralManager.cancelPeripheralConnection(device.peripheral)
            self.delegate?.didFailToConnect(device, error: NSError(domain: "BLEManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
        }
        
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        print("Disconnecting from \(peripheral.name ?? "Unknown")...")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func startWorkout() {
        sendCommand(startWorkoutCommand)
    }
    
    func stopWorkout() {
        sendCommand(stopWorkoutCommand)
    }
    
    func setDeviceTime(epochSeconds: UInt64? = nil) {
        let nowSec64: UInt64 = epochSeconds ?? UInt64(Date().timeIntervalSince1970)
        // Adjust to Pacific Time (UTC-7) as requested
        let pacificOffsetSeconds: UInt64 = 7 * 3600
        let adjustedSec64: UInt64 = nowSec64 > pacificOffsetSeconds ? (nowSec64 - pacificOffsetSeconds) : 0
        let truncatedSec: UInt32 = UInt32(truncatingIfNeeded: adjustedSec64)
        // Little-endian (LSB first) order of the lower 32 bits of epoch seconds
        let bytes: [UInt8] = [
            UInt8(truncatedSec & 0xFF),
            UInt8((truncatedSec >> 8) & 0xFF),
            UInt8((truncatedSec >> 16) & 0xFF),
            UInt8((truncatedSec >> 24) & 0xFF)
        ]
        var command = setTimeCommandPrefix
        command.append(contentsOf: bytes)
        sendCommand(command)
    }
    
    func setTimeThenStartWorkout(delaySeconds: TimeInterval = 0.1) {
        setDeviceTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
            self.startWorkout()
        }
    }
    
    private func sendCommand(_ command: [UInt8]) {
        guard let characteristic = rxCharacteristic,
              let peripheral = connectedPeripheral else {
            print("No RX characteristic or peripheral available")
            return
        }
        
        let data = Data(command)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent command: \(command.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
    }
    
    private func invalidateConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on and ready")
        case .poweredOff:
            print("Bluetooth is powered off")
            isScanning = false
            isConnected = false
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth access is unauthorized")
        case .unsupported:
            print("Bluetooth is not supported on this device")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? "Unknown Device"
        
        // Filter for devices with "zone" in the name (case insensitive)
        guard deviceName.lowercased().contains("zone") else { return }
        
        // Extract serial number from manufacturer data
        var serialNumber: String?
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("Manufacturer data size: \(manufacturerData.count) bytes")
            print("Manufacturer data: \(manufacturerData.map { String(format: "%02X", $0) }.joined(separator: " "))")
            
            // Get the last 6 bytes of the manufacturer data
            let dataLength = manufacturerData.count
            if dataLength >= 6 {
                let lastSixBytes = manufacturerData.subdata(in: (dataLength - 6)..<dataLength)
                let bytes = [UInt8](lastSixBytes)
                // Interpret as little-endian UInt48
                var decimalValue: UInt64 = 0
                for (i, byte) in bytes.enumerated() {
                    decimalValue |= UInt64(byte) << (8 * i)
                }
                serialNumber = String(decimalValue)
                print("Extracted serial number: \(serialNumber ?? "nil")")
            }
        } else {
            print("No manufacturer data found")
        }
        
        // Create device with serial number from advertisement data
        let device = BLEDevice(peripheral: peripheral, name: deviceName, rssi: RSSI.intValue, serialNumber: serialNumber)
        
        // Update pending devices instead of immediately updating the UI
        if let existingIndex = pendingDevices.firstIndex(where: { $0.id == device.id }) {
            pendingDevices[existingIndex] = device
        } else {
            pendingDevices.append(device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Successfully connected to \(peripheral.name ?? "Unknown")")
        
        invalidateConnectionTimer()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        
        // Discover services, specifically looking for Device Information Service
        print("Discovering services...")
        let deviceInfoServiceUUID = CBUUID(string: "180A")
        peripheral.discoverServices([deviceInfoServiceUUID])
        
        // Also discover all services to find other characteristics
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            peripheral.discoverServices(nil)
        }
        
        if let device = discoveredDevices.first(where: { $0.peripheral == peripheral }) {
            delegate?.didConnectToDevice(device)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")")
        
        invalidateConnectionTimer()
        
        if let device = discoveredDevices.first(where: { $0.peripheral == peripheral }) {
            delegate?.didFailToConnect(device, error: error)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown")")
        if let error = error {
            print("Disconnection error: \(error.localizedDescription)")
        }
        
        connectedPeripheral = nil
        rxCharacteristic = nil
        isConnected = false
        
        if let device = discoveredDevices.first(where: { $0.peripheral == peripheral }) {
            delegate?.didDisconnectFromDevice(device)
        }
    }
    
    private func updateDeviceSerialNumber(_ peripheral: CBPeripheral, serialNumber: String) {
        if let index = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredDevices[index].serialNumber = serialNumber
            let updatedDevice = discoveredDevices[index]
            print("Updated serial number for \(updatedDevice.name): \(serialNumber)")
            DispatchQueue.main.async {
                self.delegate?.didUpdateSerialNumber(updatedDevice)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { 
            print("No services found")
            return 
        }
        
        print("Discovered \(services.count) service(s)")
        for service in services {
            print("Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("Error discovering characteristics for service \(service.uuid): \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { 
            print("No characteristics found for service \(service.uuid)")
            return 
        }
        
        print("Discovered \(characteristics.count) characteristic(s) for service \(service.uuid)")
        
        for characteristic in characteristics {
            print("Characteristic: \(characteristic.uuid), Properties: \(characteristic.properties)")
            
            // Look for writable characteristics (RX from device perspective)
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                rxCharacteristic = characteristic
                print("Found writable characteristic (RX): \(characteristic.uuid)")
            }
            
            // Check for Serial Number String characteristic (UUID 2A25)
            if characteristic.uuid == CBUUID(string: "2A25") {
                print("Found Serial Number String characteristic, reading value...")
                peripheral.readValue(for: characteristic)
            }
            
            // Enable notifications for readable characteristics
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                print("Enabled notifications for characteristic: \(characteristic.uuid)")
            }
            
            // Read characteristics that support reading (except serial number which we handle above)
            if characteristic.properties.contains(.read) && characteristic.uuid != CBUUID(string: "2A25") {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing to characteristic \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            print("Successfully wrote to characteristic: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error reading characteristic \(characteristic.uuid): \(error!.localizedDescription)")
            return
        }
        
        if let data = characteristic.value {
            // Handle Serial Number String characteristic (UUID 2A25)
            if characteristic.uuid == CBUUID(string: "2A25") {
                if let serialNumber = String(data: data, encoding: .utf8) {
                    print("Read serial number: \(serialNumber)")
                    updateDeviceSerialNumber(peripheral, serialNumber: serialNumber)
                } else {
                    print("Could not decode serial number data")
                }
            } else {
                // Handle other characteristics
                let hexString = data.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                print("Received data from \(characteristic.uuid): \(hexString)")
                
                // You can add specific data parsing logic here based on your device's protocol
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating notification state for \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            print("Notification state updated for \(characteristic.uuid): \(characteristic.isNotifying)")
        }
    }
} 
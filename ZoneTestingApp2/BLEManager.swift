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
    func didUpdateFirmwareVersion(_ device: BLEDevice, version: String)
    func didUpdateBatteryLevel(_ device: BLEDevice, percent: Int)
}

protocol BLEFirmwareUpdateDelegate: AnyObject {
    func firmwareUpdateProgress(bytesSent: Int, totalBytes: Int)
    func firmwareUpdateCompleted()
    func firmwareUpdateFailed(error: String)
}

struct BLEDevice {
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    var serialNumber: String?
    var firmwareVersion: String?
    
    var id: String {
        return peripheral.identifier.uuidString
    }
}

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var notifyCharacteristics: [CBCharacteristic] = []
    private var hasSentPostConnectInit = false
    private var connectionEstablishedAt: Date?
    private var postConnectInitWorkItem: DispatchWorkItem?
    private var connectionTimer: Timer?
    private var updateTimer: Timer?
    private var pendingDevices: [BLEDevice] = []
    
    weak var delegate: BLEManagerDelegate?
    weak var firmwareDelegate: BLEFirmwareUpdateDelegate?
    
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var isScanning = false
    @Published var isConnected = false
    
    // Commands to send
    private let startWorkoutCommand: [UInt8] = [0x40, 0x08]
    private let stopWorkoutCommand: [UInt8] = [0x40, 0x09]
    private let setTimeCommandPrefix: [UInt8] = [0x40, 0x04]
    private let batteryLevelCommand: [UInt8] = [0x40, 0x06]

    // Firmware update command bytes
    private let fwHeaderCommand: [UInt8] = [0x40, 0x12]
    private let fwChunkCommand: [UInt8] = [0x40, 0x13]
    private let fwTailCommand: [UInt8] = [0x40, 0x14]
    private let fwAckHeader: [UInt8] = [0x40, 0x92, 0x00]
    private let fwAckChunk: [UInt8] = [0x40, 0x93, 0x00]
    private let fwAckTail: [UInt8] = [0x40, 0x94, 0x00]

    // Post-connect init command
    private let postConnectInitCommand: [UInt8] = [0x40, 0x21, 0x4B, 0x00, 0x00, 0x00, 0x32]
    private let preferredWriteCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    private func schedulePostConnectInitIfReady() {
        guard !hasSentPostConnectInit else { return }
        guard isConnected, rxCharacteristic != nil else { return }
        let targetDelay: TimeInterval = 1.0
        let elapsed = connectionEstablishedAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = max(0, targetDelay - elapsed)
        postConnectInitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.isConnected, self.rxCharacteristic != nil, !self.hasSentPostConnectInit else { return }
            self.sendCommand(self.postConnectInitCommand)
            self.hasSentPostConnectInit = true
            // After sending init, request battery level shortly after
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.requestBatteryLevel()
            }
        }
        postConnectInitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private struct FirmwareUpdateContext {
        let data: Data
        var offset: Int
        let last32Start: Int
        let headerLength: Int
        var totalBytes: Int { data.count }
        var bytesSentExcludingPending: Int { offset }
    }
    private var firmwareContext: FirmwareUpdateContext?
    
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
    
    func requestBatteryLevel() {
        sendCommand(batteryLevelCommand)
    }

    func sendBlueLedCommand() {
        sendCommand(postConnectInitCommand)
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

    // MARK: - Firmware Update API
    func startFirmwareUpdate(with fileData: Data) {
        guard fileData.count >= 5 + 32 else {
            firmwareDelegate?.firmwareUpdateFailed(error: "Firmware file too small (requires at least 37 bytes)")
            return
        }
        guard let _ = connectedPeripheral, let _ = rxCharacteristic else {
            firmwareDelegate?.firmwareUpdateFailed(error: "No connected device or writable characteristic")
            return
        }
        // Initialize context
        let last32Start = fileData.count - 32
        firmwareContext = FirmwareUpdateContext(data: fileData, offset: 0, last32Start: last32Start, headerLength: 5)
        // Send header (first 5 bytes)
        sendFirmwareHeader()
    }

    private func sendFirmwareHeader() {
        guard var ctx = firmwareContext else { return }
        // Construct 5-byte header:
        // bytes 1..4 of file contain little-endian (fileLength - 5). Add 0x05 → total file length.
        // Encode that value in little-endian, then append 0xAD.
        let total = ctx.data.count
        let b1 = total > 1 ? ctx.data[1] : 0
        let b2 = total > 2 ? ctx.data[2] : 0
        let b3 = total > 3 ? ctx.data[3] : 0
        let b4 = total > 4 ? ctx.data[4] : 0
        let originalLenLE: UInt32 = UInt32(b1) | (UInt32(b2) << 8) | (UInt32(b3) << 16) | (UInt32(b4) << 24)
        let adjustedLen = originalLenLE &+ 0x05
        let headerBytes: [UInt8] = [
            UInt8(adjustedLen & 0xFF),
            UInt8((adjustedLen >> 8) & 0xFF),
            UInt8((adjustedLen >> 16) & 0xFF),
            UInt8((adjustedLen >> 24) & 0xFF),
            0xAD
        ]
        var payload = fwHeaderCommand
        payload.append(contentsOf: headerBytes)
        sendCommand(payload)
        // Do not advance offset; chunk stage should send the entire file except last 32 (re-includes header)
        ctx.offset = 0
        firmwareContext = ctx
        firmwareDelegate?.firmwareUpdateProgress(bytesSent: ctx.headerLength, totalBytes: ctx.totalBytes)
    }

    private func sendNextFirmwareChunk() {
        guard var ctx = firmwareContext else { return }
        // Use fixed 128-byte data chunks for 0x40 0x13 stage as requested
        let maxChunkPayload = 128
        if ctx.offset >= ctx.last32Start {
            // Move to tail stage
            firmwareContext = ctx
            sendFirmwareTail()
            return
        }
        let remainingForChunkStage = ctx.last32Start - ctx.offset
        let thisChunkSize = min(maxChunkPayload, remainingForChunkStage)
        let range = ctx.offset..<(ctx.offset + thisChunkSize)
        let chunkBytes = Array(ctx.data[range])
        var payload = fwChunkCommand
        payload.append(contentsOf: chunkBytes)
        sendCommand(payload)
        ctx.offset += thisChunkSize
        firmwareContext = ctx
        // Progress counts unique bytes sent: header once, plus any new bytes beyond header up to last32Start
        let uniqueSent = min(ctx.last32Start, max(ctx.headerLength, ctx.offset))
        firmwareDelegate?.firmwareUpdateProgress(bytesSent: uniqueSent, totalBytes: ctx.totalBytes)
    }

    private func sendFirmwareTail() {
        guard let ctx = firmwareContext else { return }
        // Last 32 bytes
        let start = max(0, ctx.totalBytes - 32)
        let tailBytes = Array(ctx.data[start..<ctx.totalBytes])
        guard tailBytes.count == 32 else {
            firmwareDelegate?.firmwareUpdateFailed(error: "Tail size is not 32 bytes")
            firmwareContext = nil
            return
        }
        var payload = fwTailCommand
        payload.append(contentsOf: tailBytes)
        sendCommand(payload)
    }
    
    private func sendCommand(_ command: [UInt8]) {
        guard let characteristic = rxCharacteristic,
              let peripheral = connectedPeripheral else {
            print("No RX characteristic or peripheral available")
            return
        }
        
        let data = Data(command)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
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
        
        // Filter by serial number prefix "126" as requested
        guard let sn = serialNumber, sn.hasPrefix("126") else {
            // Skip devices whose serial number doesn't start with 126 (or unavailable)
            return
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
        connectionEstablishedAt = Date()
        
        // Reset post-connect flag
        hasSentPostConnectInit = false

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
        hasSentPostConnectInit = false
        connectionEstablishedAt = nil
        postConnectInitWorkItem?.cancel()
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

    private func updateDeviceFirmwareVersion(_ peripheral: CBPeripheral, version: String) {
        if let index = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredDevices[index].firmwareVersion = version
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
                // Prefer the known Nordic UART TX characteristic UUID if it matches
                if characteristic.uuid == preferredWriteCharacteristicUUID {
                    rxCharacteristic = characteristic
                } else if rxCharacteristic == nil {
                    rxCharacteristic = characteristic
                }
                print("Found writable characteristic (RX): \(characteristic.uuid)")
                // Schedule post-connect init 1s after connection when ready
                schedulePostConnectInitIfReady()
            }
            
            // Check for Serial Number String characteristic (UUID 2A25)
            if characteristic.uuid == CBUUID(string: "2A25") {
                print("Found Serial Number String characteristic, reading value...")
                peripheral.readValue(for: characteristic)
            }

            // Check for Firmware Revision String (UUID 2A26)
            if characteristic.uuid == CBUUID(string: "2A26") {
                print("Found Firmware Revision String characteristic, reading value...")
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
            // Fail firmware update if in progress
            if firmwareContext != nil {
                firmwareDelegate?.firmwareUpdateFailed(error: error.localizedDescription)
                firmwareContext = nil
            }
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
            } else if characteristic.uuid == CBUUID(string: "2A26") {
                // Firmware Revision String
                if let versionStr = String(data: data, encoding: .utf8) {
                    print("Read firmware revision: \(versionStr)")
                    if let device = self.discoveredDevices.first(where: { $0.peripheral == peripheral }) {
                        // Persist on the device record
                        self.updateDeviceFirmwareVersion(peripheral, version: versionStr)
                        DispatchQueue.main.async {
                            self.delegate?.didUpdateFirmwareVersion(device, version: versionStr)
                        }
                    }
                } else {
                    let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("Could not decode firmware revision data, raw: \(hexString)")
                }
            } else {
                // Handle other characteristics
                let hexString = data.map { String(format: "0x%02X", $0) }.joined(separator: " ")
                print("Received data from \(characteristic.uuid): \(hexString)")
                
                // Firmware ACK handling
                let bytes = [UInt8](data)
                if bytes == fwAckHeader {
                    print("Firmware: Received header ACK")
                    sendNextFirmwareChunk()
                } else if bytes == fwAckChunk {
                    print("Firmware: Received chunk ACK")
                    sendNextFirmwareChunk()
                } else if bytes == fwAckTail {
                    print("Firmware: Received tail ACK - update complete")
                    if let total = firmwareContext?.totalBytes {
                        firmwareDelegate?.firmwareUpdateProgress(bytesSent: total, totalBytes: total)
                    }
                    firmwareDelegate?.firmwareUpdateCompleted()
                    firmwareContext = nil
                } else if bytes.count >= 4 && bytes[0] == 0x40 && bytes[1] == 0x86 {
                    // Battery response: last two bytes are battery level in hex
                    let value = (Int(bytes[2]) << 8) | Int(bytes[3])
                    let percent = max(0, min(100, value))
                    if let device = self.discoveredDevices.first(where: { $0.peripheral == peripheral }) {
                        DispatchQueue.main.async {
                            self.delegate?.didUpdateBatteryLevel(device, percent: percent)
                        }
                    }
                }
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
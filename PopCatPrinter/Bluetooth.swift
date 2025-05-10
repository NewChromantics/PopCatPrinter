import SwiftUI
import CoreBluetooth
import Combine


public struct PrintError : LocalizedError
{
	let description: String
	
	public init(_ description: String) {
		self.description = description
	}
	
	public var errorDescription: String? {
		description
	}
}



//	Printer found: "MXW01" - {"id":"Yl2JxVBQJjs7IRbZDVyrWQ=="}

//	https://github.com/rbaron/catprinter/compare/main...jeremy46231:MXW01-catprinter:main
//	https://catprinter.vercel.app/
/*
 Printer Protocol
 MXW01 Thermal Printer Protocol Summary:
 
 1. Connect via Bluetooth LE to service UUID: 0000ae30-0000-1000-8000-00805f9b34fb
 2. Communication happens through three characteristics:
 - Control write: 0000ae01-0000-1000-8000-00805f9b34fb
 - Notification: 0000ae02-0000-1000-8000-00805f9b34fb
 - Data write: 0000ae03-0000-1000-8000-00805f9b34fb
 
 3. Command format: 0x22 0x21 [CMD] 0x00 [LEN_L] [LEN_H] [PAYLOAD...] [CRC8] 0xFF
 4. Print process:
 a. Set intensity (0xA2)
 b. Request status (0xA1)
 c. Send print request (0xA9)
 d. Transfer data in chunks
 e. Flush data (0xAD)
 f. Wait for print complete notification (0xAA)
 
 5. Image encoding:
 - 1-bit monochrome (black/white)
 - 384 pixels wide (48 bytes)
 - Rows are sent sequentially
 - Image is rotated 180° before sending
 */

public class CatPrinterManager : ObservableObject
{
	var bluetoothManager : BluetoothManager!
	@Published var mxw01s = [MXW01Peripheral]()
	static let mxw10DeviceName = "MXW01"
	
	public init()
	{
		self.bluetoothManager = BluetoothManager(onPeripheralFound:OnFoundPeripheral)
	}
	
	func OnFoundPeripheral(_ peripheral:CBPeripheral) -> BluetoothPeripheralHandler?
	{
		if peripheral.name == CatPrinterManager.mxw10DeviceName
		{
			let mxw01 = MXW01Peripheral(peripheral: peripheral)
			mxw01s.append(mxw01)
			return mxw01
		}
		return nil
	}
}


extension CBPeripheral
{
	func GetService(serviceUid:CBUUID) -> CBService?
	{
		let services = self.services ?? []
		let matches = services.filter
		{
			$0.uuid == serviceUid
		}
		return matches.first
	}
}

extension CBService
{
	func GetCharacteristic(characteristicUid:CBUUID) -> CBCharacteristic?
	{
		let chars = self.characteristics ?? []
		let matches = chars.filter
		{
			$0.uuid == characteristicUid
		}
		return matches.first
	}
}


extension UInt16
{
	var littleEndianBytes : [UInt8]
	{
		var sixteen = self.littleEndian
		return withUnsafeBytes(of: &sixteen) 
		{
			Array($0)
		}
	}
}



public protocol BluetoothPeripheralHandler
{
	func OnConnected()
}

extension CBCharacteristic
{
	var name : String
	{
		switch self.uuid
		{
			case MXW01Peripheral.ControlUid:	return "Control"
			case MXW01Peripheral.NotificationUid:	return "Notification"
			case MXW01Peripheral.DataUid:	return "Data"
			default:	return "\(self.uuid)"
		}
	}
}

func GetBatteryIconName(percent:Int?) -> String
{
	guard let percent else
	{
		return "questionmark.app.fill"
	}
	if percent > 75
	{
		return "battery.100percent"
	}
	if percent > 50
	{
		return "battery.75percent"
	}
	if percent > 25
	{
		return "battery.50percent"
	}
	if percent > 0
	{
		return "battery.25percent"
	}
	return "battery.0percent"
}

public class PromiseWrapper<ResolvedValue>
{
	var future : Future<ResolvedValue,any Error>!
	private var resolvingFunctor : ((Result<ResolvedValue,any Error>)->Void)!
	
	//public init(resolvingFunctor:@escaping (Result<ResolvedValue,any Error>)->Void)
	public init()
	{
		let future = Future<ResolvedValue,any Error>()
		{
			promise in
			self.resolvingFunctor = promise
		}
		self.future = future
	}
	
	public func Resolve(_ data:ResolvedValue)
	{
		resolvingFunctor( Result.success(data) )
	}
	
	public func Reject(_ error:Error)
	{
		resolvingFunctor( Result.failure(error) )
	}
	
	public func Wait() async throws -> ResolvedValue
	{
		try await self.future.value
	}
}

struct Response
{
	var payload : Data
	var command : UInt8
}

class MXW01Peripheral : NSObject, BluetoothPeripheralHandler, CBPeripheralDelegate, Identifiable, ObservableObject
{
	enum PrinterStatus
	{
		case Idle,PaperMissing,NotOkay
	}
	
	private var peripheral : CBPeripheral
	var id : UUID	{	peripheral.identifier	}
	var services : [CBService]	{	peripheral.services ?? []	}
	var name : String	{	peripheral.name ?? "\(peripheral.identifier)"	}
	var state : CBPeripheralState	{	peripheral.state	}
	//@Published var state : CBPeripheralState = .disconnected
	@Published var lastError : Error? = nil
	@Published var lastStatus : PrinterStatus? = nil
	@Published var batteryLevelPercent : Int? = nil
	@Published var tempratureCentigrade : Int? = nil
	var error : String?	{	lastError.map{ "\($0.localizedDescription)"	}	}
	var batteryLevelIconName : String	{	GetBatteryIconName(percent: batteryLevelPercent)	}

	var printerStatusIconName : String	
	{
		switch lastStatus
		{
			case nil:	return "questionmark.app.fill"
			case .PaperMissing:	return "newspaper"
			case .NotOkay:	return "exclamationmark.triangle.fill"
			case .Idle:	return "checkmark.seal"
		}
	}

	//	gr: store these characteristics
	static let ControlUid =		CBUUID(string: "0000ae01-0000-1000-8000-00805f9b34fb")
	static let NotificationUid =	CBUUID(string: "0000ae02-0000-1000-8000-00805f9b34fb")
	static let DataUid = 			CBUUID(string: "0000ae03-0000-1000-8000-00805f9b34fb")
	let mxw10PrinterServiceUid = CBUUID(string: "0000ae30-0000-1000-8000-00805f9b34fb")
	let command_GetStatus : UInt8 = 0xA1
	let command_GetBattery : UInt8 = 0xAB
	let command_SetDarkness : UInt8 = 0xA2
	let command_StartPrint : UInt8 = 0xA9
	let command_FlushPrint : UInt8 = 0xAD
	let command_PrintFinished : UInt8 = 0xAA
	let imageWidth = 384

	var control : CBCharacteristic? = nil
	var notification : CBCharacteristic? = nil
	var data : CBCharacteristic? = nil
	
	var pendingNotification : PromiseWrapper<Response>?
		
	
	init(peripheral: CBPeripheral) 
	{
		self.peripheral = peripheral
		super.init()
		
		//	setup handling
		self.peripheral.delegate = self
	}
	
	var debugColour : Color
	{
		let IsConnected = state == .connected
		let IsConnecting = state == .connecting
		if self.lastError != nil
		{
			return .red
		}
		
		if IsConnecting
		{
			return .yellow
		}
		if IsConnected
		{
			return .green
		}
		
		return .clear		
	}
	
	func OnStateChanged()
	{
		DispatchQueue.main.async
		{
			@MainActor in
			//	not working
			self.objectWillChange.send()
			//self.state = self.theState
			//self.state = .connected
		}
	}
	
	func OnConnected() 
	{
		print("Mxw01 connected!")
		OnStateChanged()

		//	start fetching services
		peripheral.discoverServices(nil)
	}
	
	func OnError(_ error:Error)
	{
		DispatchQueue.main.async
		{
			@MainActor in
			self.lastError = error
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) 
	{
		if let error 
		{
			print("didDiscoverServices error \(error.localizedDescription)")
			self.lastError = error
			return
		}
		
		let services = peripheral.services ?? []
		let name = peripheral.name ?? "noname"
		print("did discover services x\(services.count) for \(name) (\(peripheral.state))")
		OnStateChanged()

		//	start finding characteristics
		services.forEach
		{
			peripheral.discoverCharacteristics(nil, for: $0)
		}
		
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) 
	{
		if let error 
		{
			print("didDiscoverCharacteristicsFor error \(error.localizedDescription)")
			self.lastError = error
			return
		}
		
		let characteristics = service.characteristics ?? []
		let name = peripheral.name ?? "noname"
		print("did discover characteristics x\(characteristics.count) for \(name) (\(peripheral.state))")
		OnStateChanged()
		
		if service.uuid == mxw10PrinterServiceUid
		{
			self.control = service.GetCharacteristic(characteristicUid: MXW01Peripheral.ControlUid)
			self.notification = service.GetCharacteristic(characteristicUid: MXW01Peripheral.NotificationUid)
			self.data = service.GetCharacteristic(characteristicUid: MXW01Peripheral.DataUid)
			
			
			Task
			{
				do
				{
					try await PrintSomething()
				}
				catch
				{
					OnError(error)
				}
			}
		}
		
		
	}
	
	//	catch any errors from notification update subscriptions
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) 
	{
		if let error 
		{
			print("didUpdateNotificationStateFor \(characteristic.name) error \(error.localizedDescription)")
			OnError(error)
			return
		}
		print("Characteristic Notification for \(characteristic.name) now \(characteristic.isNotifying)")
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) 
	{
		do
		{
			if let error
			{
				print("didUpdateValueFor \(characteristic.name) error \(error.localizedDescription)")
				throw error
			}
			
			guard let value = characteristic.value else 
			{
				throw PrintError("Missing characteristic \(characteristic.name) value")
				return
			}
			
			if characteristic.uuid == MXW01Peripheral.NotificationUid
			{
				try OnNotification(value)
				return
			}
			
			throw PrintError("Dont know how to hanle \(characteristic.name) value-change \(value)")
		}
		catch
		{
			self.lastError = error
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) 
	{
		if let error 
		{
			print("didWriteValueFor \(characteristic.uuid) error \(error.localizedDescription)")
			OnError(error)
			return
		}
		
		print("Characteristic \(characteristic.uuid) wrote value")
	}
	
	func OnNotification(_ packet:Data) throws
	{
		//	https://github.com/jeremy46231/MXW01-catprinter/blob/main/PROTOCOL.md
		//	parse 
		print("Got notification \(packet)")
		let header = packet[0...1]
		if header[0] != 0x22
		{
			throw PrintError("Malformed header")
		}
		let command = packet[2]
		let unknown = packet[3]
		let lengthLittleEndian = packet.subdata(in: 4..<6)
		let length16 = Int(lengthLittleEndian[0]) | (Int(lengthLittleEndian[1]) << 8)
		let payload = Data(packet[6...packet.count-2])
		//let payload = packet.subdata(in:6..<packet.count-1)
		//	no crc!Da
		let footer = packet[packet.count-1]

		if length16 != payload.count
		{
			throw PrintError("Packet length \(length16) but payload is \(payload.count)")
		}

		if footer != 0xff
		{
			//throw PrintError("Malformed footer")
			print("Warning; Malformed footer \(footer)")
		}
		
		let response = Response(payload: payload,command: command)
		
		if let pendingNotification
		{
			pendingNotification.Resolve(response)
		}

		//	some generic response handling
		if command == command_GetStatus
		{
			_ = try OnStatus(payload)
			return
		}
		
		if command == command_GetBattery
		{
			try OnBatteryLevel(payload)
			return
		}
	}
	
	func OnStatus(_ payload:Data) throws -> PrinterStatus
	{
		let payloadDebug = payload.map{ Int($0) }
		print("New status x\(payload.count) \(payloadDebug)")
		//	init	[[0, 0, 0, 100, 19, 0, 0, 0, 68, 6]]
		//	open  	[[0, 0, 0, 100, 19, 0, 1, 1, 182, 9]]
		//	closed	[[0, 0, 0, 100, 19, 0, 0, 0, 135, 0]]
		//	open  	[[0, 0, 0, 100, 19, 0, 1, 1, 6, 11]]
		//	close 	[[0, 0, 0, 100, 19, 0, 0, 0, 153, 0]]
		let a = payload[0]
		let b = payload[1]
		let c = payload[2]
		let batteryLevel = payload[3]
		let temprature = payload[4]	//	degrees centigrade
		let f = payload[5]			//	possibly big endian of temp
		
		let status = payload[6]		//	0 idle, 1 printing according to docs
		let overallStatus = payload[7]	//	0 ok, non-zero has error
		
		//	
		let voltageLo = payload[8]
		let voltageHi = payload[9]

		//	from docs:
		//	if Flag!=0): Error Code (1/9=No Paper, 4=Overheated, 8=Low Battery). Requires length check
		//	but when tray open, we dont get this, but we do have 1 for status codes
		let error = payload.count > 10 ? payload[10] : nil
		
		let printerStatus : PrinterStatus = {
			if overallStatus == 0
			{
				return .Idle
			}
			else if overallStatus == 1
			{
				return .PaperMissing
			}
			else
			{
				OnError( PrintError("Unknown overall-status \(overallStatus) (status \(status)") )
				return .NotOkay
			}
		}()
		
		DispatchQueue.main.async
		{
			@MainActor in
			self.lastStatus = printerStatus
			self.tempratureCentigrade = Int(temprature)
			self.batteryLevelPercent = Int(batteryLevel)
		}
		
		return printerStatus
	}
	
	func OnBatteryLevel(_ payload:Data) throws
	{
		if payload.count != 1
		{
			throw PrintError("Battery level expected only 1 byte, got \(payload.count) [\(String(describing: payload.first))]")
		}
		
		DispatchQueue.main.async
		{
			@MainActor in
			self.batteryLevelPercent = Int(payload[0])
		}
	}
	
	func MakePacket(_ command:UInt8,payload:[UInt8]) -> Data
	{
		func calcCrc() -> UInt8
		{
			//	todo!
			return 0x0
		}
		
		let crc : UInt8 = calcCrc()
		let length16 = UInt16(payload.count)
		let lengthBytes = length16.littleEndianBytes
		
		let packetParts = 
		[
			[0x22,0x21,command,0x0],
			lengthBytes,
			payload,
			[crc,0xff]
		]
		let data = packetParts.flatMap{$0}
		return Data( Array(data) )
	}
	
	
	//	if expectedResponseCommand nil, then we expect the one we sent
	func SendPacketAndWaitForResponse(_ command:UInt8,payload:[UInt8],expectedResponseCommand:UInt8?=nil) async throws -> Data
	{
		let packet = MakePacket(command, payload: payload)

		if pendingNotification != nil
		{
			throw PrintError("Already waiting for a notification")
		}
		
		//	setup promise to be resolved
		pendingNotification = PromiseWrapper<Response>()
		peripheral.writeValue( packet, for:control!, type: .withoutResponse )

		let response = try await pendingNotification!.Wait()
		pendingNotification = nil
		let expected = (expectedResponseCommand ?? command)
		if response.command != expected
		{
			throw PrintError("Notification for wrong command \(response.command) expected \(expected) (send \(command))")
		}
		print("Notification for command \(response.command) recieved")
		
		return response.payload
	}

	func PrintSomething() async throws
	{
		func CharToBool(_ char:String.Element) -> Bool
		{
			return char != " "
		}
		let pattern = [
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"    XXXX    XXXX    XXXX    XXXX    ",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
			"XXXX    XXXX    XXXX    XXXX    XXXX",
		]
		let patternBools = pattern.map{ $0.map(CharToBool) }
		try await PrintImage(imageRowBits: patternBools)
	}
	
	func PrintImage(imageRowBits:[[Bool]]) async throws
	{
		guard let control, let data, let notification else
		{
			throw PrintError("Missing control/data/notification characteristics")
		}
		
		//	get notifications
		//peripheral.setNotifyValue(true, for: control)
		peripheral.setNotifyValue(true, for: notification)
		//peripheral.setNotifyValue(true, for: data)
		
		try await WaitForStatus()
		try await WaitForBatteryLevel()
	
		SetPrinterDarkness(128)

		try await WaitForIdleStatus()
		
		func PackLineBits(lineBits:[Bool]) -> [UInt8]
		{
			//	init buffer
			var rowBytes : [UInt8] = (0..<imageWidth/8).map{ _ in 0 }
			for i in 0..<lineBits.count
			{
				let Byte = i / 8
				let Bit = i % 8
				let Value = lineBits[i] ? 1 : 0
				rowBytes[Byte] |= (UInt8)(Value << Bit)
			}
			return rowBytes
		}
		let linePackedBytes = imageRowBits.map{ PackLineBits(lineBits: $0) }
		try await PrintPackedRows( linePackedBytes )
	}
	
	func WaitForBatteryLevel() async throws
	{
		print("Querying Battery...")
		let payload = try await SendPacketAndWaitForResponse( command_GetBattery, payload: [0x0] )
		try OnBatteryLevel(payload)
	}
	
	func WaitForIdleStatus() async throws
	{
		//	todo: timeout
		while true
		{
			let newStatus = try await WaitForStatus()
			if newStatus == .Idle
			{
				return
			}
		}
	}
	
	func WaitForStatus() async throws -> PrinterStatus
	{
		print("Querying status...")
		let payload = try await SendPacketAndWaitForResponse(command_GetStatus, payload: [0x0])
		
		let status = try OnStatus(payload)
		return status
	}
	
	func SetPrinterDarkness(_ darknessLevel:UInt8) 
	{
		let setDarknessPacket = MakePacket(command_SetDarkness,payload: [darknessLevel])
		print("Setting darkness to \(darknessLevel)...")
		peripheral.writeValue(setDarknessPacket, for: control!, type: .withoutResponse)
	}
	
	func PrintPackedRows(_ linePackedBytes:[[UInt8]]) async throws
	{
		//	image height=line count
		let lineCount = UInt16(linePackedBytes.count)
		let lineCountBytes = lineCount.littleEndianBytes
		let mode : UInt8 = 0x0
		let payload = [ lineCountBytes, [0x30, mode] ].flatMap{$0}
		
		let response = try await SendPacketAndWaitForResponse( command_StartPrint, payload: payload )
		let printError = response[0]
		if printError != 0
		{
			throw PrintError("Print request error; \(printError)")
		}
		
		//	send data
		for packedLineBytes in linePackedBytes
		{
			//	1bit data
			//	8 bits/pixels per row
			//	row is 384 pixels wide
			let rowByteCount = imageWidth/8
			//let rowData = [UInt8](repeating: line, count: rowByteCount)
			let rowData = packedLineBytes
			if rowData.count != rowByteCount
			{
				throw PrintError("Row expected to have \(rowByteCount) bytes, but provided \(rowData.count)")
			}
			let delayMs = 50
			
			peripheral.writeValue( Data(rowData), for: self.data!, type: .withoutResponse)
			
			await Task.sleep(milliseconds: delayMs)
		}

		//	send flush when finished
		let flushResponse = try await SendPacketAndWaitForResponse( command_FlushPrint, payload:[0x0], expectedResponseCommand:command_PrintFinished )
		let flushResponseDebug = flushResponse.map{ Int($0) }
		print("Flush response \(flushResponseDebug)")
		//	Wait for the AA notification on AE02, indicating the printer has finished the physical
	}
}
	



struct BluetoothDevice : Identifiable, Hashable, Comparable
{
	static func < (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool 
	{
		return lhs.name < rhs.name
	}
	
	static func ==(lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool
	{
		return lhs.id == rhs.id
	}
	
	func hash(into hasher: inout Hasher) 
	{
		hasher.combine(	id.hashValue)
	}
	
	var id : UUID	{	deviceUid	}
	var deviceUid : UUID
	var name : String
	var state : CBPeripheralState
	var services : [CBService]
	
	var debugColour : Color
	{
		let IsConnected = state == .connected
		let IsConnecting = state == .connecting

		if IsConnecting
		{
			return .yellow
		}
		if IsConnected
		{
			return .green
		}

		return .clear		
	}
}


extension CBManagerState : @retroactive CustomStringConvertible 
{
	public var description: String 
	{
		switch self
		{
			case CBManagerState.unknown:	return "unknown"
			case CBManagerState.resetting:	return "resetting"
			case CBManagerState.unsupported:	return "unsupported"
			case CBManagerState.unauthorized:	return "unauthorized"
			case CBManagerState.poweredOff:	return "poweredOff"
			case CBManagerState.poweredOn:	return "poweredOn"
			default:
				return String(describing: self)
		}
	}
}


extension CBPeripheralState : @retroactive CustomStringConvertible 
{
	public var description: String 
	{
		switch self
		{
			case .connected:	return "connected"
			case .connecting:	return "connecting"
			case .disconnected:	return "disconnected"
			case .disconnecting:	return "disconnecting"
			default:
				return String(describing: self)
		}
	}
}

class BluetoothManager : NSObject, CBCentralManagerDelegate, ObservableObject
{
	var centralManager : CBCentralManager!
	var devices : [BluetoothDevice]	{	Array(deviceStates).sorted()	}
	@Published var lastState : CBManagerState = .unknown
	@Published var isScanning : Bool = false
	@Published var deviceStates = Set<BluetoothDevice>()
	var showNoNameDevices = false
	
	//	return a handler if you want this device to be connected
	var onPeripheralFoundCallback : (CBPeripheral)->BluetoothPeripheralHandler?
	
	//	need to keep a strong reference to peripherals we're connecting to
	//	gr: is now a callback interface
	var connectingPeripherals = [UUID:BluetoothPeripheralHandler]()
	
	init(onPeripheralFound:@escaping(CBPeripheral)->BluetoothPeripheralHandler?=BluetoothManager.DefaultHandler)
	{
		self.onPeripheralFoundCallback = onPeripheralFound
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: nil)
	}
	
	static func DefaultHandler(_:CBPeripheral) -> BluetoothPeripheralHandler?
	{
		return nil
	}
	
	
	func updateDeviceState(_ peripheral:CBPeripheral)
	{
		/*
		if !self.showNoNameDevices && peripheral.name == nil
		{
			return
		}*/
		
		let name = peripheral.name ?? "\(peripheral.identifier)"
		var services = peripheral.services ?? []
		let device = BluetoothDevice(deviceUid: peripheral.identifier, name: name, state: peripheral.state, services: services)
		
		DispatchQueue.main.async
		{
			@MainActor in
			self.deviceStates.update(with: device)
		}
	}
	
	func centralManager(_ central: CBCentralManager, 
								didDiscover peripheral: CBPeripheral, 
								advertisementData: [String : Any], 
								rssi RSSI: NSNumber)
	{
		let name = peripheral.name ?? "\(peripheral.identifier)"
		
		//	see if we want to make a handler for this device
		if connectingPeripherals[peripheral.identifier] == nil
		{
			if let newHandler = self.onPeripheralFoundCallback(peripheral)
			{
				//	we got a new handler back, which means parent wants to connect to this device
				connectingPeripherals[peripheral.identifier] = newHandler
				central.connect(peripheral)
			}
		}
	
		//print("Updating \(name) (\(peripheral.state))")
		updateDeviceState(peripheral)
	}
	

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) 
	{
		updateDeviceState(peripheral)

		guard let handler = connectingPeripherals[peripheral.identifier] else
		{
			print("Connected to peripheral without handler; \(peripheral.name) (\(peripheral.state))")
			return
		}
			
		print("Connected to peripheral \(peripheral.name) (\(peripheral.state))")
		handler.OnConnected()
	}	
	
	func centralManagerDidUpdateState(_ central: CBCentralManager) 
	{
		lastState = central.state
		isScanning = central.isScanning
		
		if central.state == .poweredOn
		{
			central.scanForPeripherals(withServices:nil)
			//central.scanForPeripherals(withServices: [mxw10PrinterServiceUid])
		}
	}
}


//	because the peripheral is a class, it needs it's own view 
//	with @StateObject in order to see changes
struct PrinterView : View 
{
	@StateObject var printer : MXW01Peripheral
	
	func OnClickedPrint()
	{
		Task
		{
			try await printer.PrintSomething()
		}
	}
	
	var body: some View
	{
		VStack(alignment: .leading,spacing: 10)
		{
			let debugColour = printer.debugColour
			let servicesDebug = printer.services.count > 0 ? "(\(printer.services.count) services)" : ""
			let batteryDebug = printer.batteryLevelPercent.map{ "\($0)%" } ?? "?"
			let statusDebug = printer.lastStatus.map{ "\($0)" } ?? "?"
			let tempDebug = printer.tempratureCentigrade.map{ "\($0)oC" } ?? "?"
			let tempIcon = printer.tempratureCentigrade != nil ? "thermometer.medium" : "thermometer.medium.slash"
			
			Label("\(printer.name) \(servicesDebug) \(printer.state)",systemImage: "printer.fill")
				.background(debugColour)
			Label("\(batteryDebug)",systemImage: printer.batteryLevelIconName )
			Label(tempDebug,systemImage: tempIcon )
			Label("Status: \(statusDebug)", systemImage: printer.printerStatusIconName )
			if let error = printer.error
			{
				Label(error,systemImage: "exclamationmark.triangle.fill")
			}
			
			Button(action:OnClickedPrint)
			{
				Text("Print something")
			}
		}
	}
}

struct CatPrinterManagerView : View 
{
	@StateObject var printers = CatPrinterManager()
	
	var body: some View 
	{
		let bluetoothManager = printers.bluetoothManager!
		VStack
		{
			Text("Printers: \(printers.mxw01s.count)")
			List
			{
				ForEach( printers.mxw01s )
				{
					(device:MXW01Peripheral) in
					PrinterView(printer: device)
				}
			}
			
			Text("Devices: \(bluetoothManager.devices.count)")
			Text("Manager State: \(bluetoothManager.lastState)")
			Text("Is Scanning: \(bluetoothManager.isScanning)")
			List
			{
				ForEach( bluetoothManager.devices )
				{
					device in
					let debugColour = device.debugColour
					let servicesDebug = device.services.count > 0 ? "(\(device.services.count) services)" : ""
					Text("Device Name: \(device.name) \(servicesDebug) \(device.state)")
						.background(debugColour)
					
				}
			}
		}	
	}
}

struct BluetoothManagerView : View 
{
	@StateObject var bluetoothManager = BluetoothManager()
	
	var body: some View 
	{
		VStack
		{
			Text("Bluetooth devices: \(bluetoothManager.devices.count)")
			Text("Manager State: \(bluetoothManager.lastState)")
			Text("Is Scanning: \(bluetoothManager.isScanning)")
			List
			{
				ForEach( bluetoothManager.devices )
				{
					device in
					let debugColour = device.debugColour
					let servicesDebug = device.services.count > 0 ? "(\(device.services.count) services)" : ""
					Text("Device Name: \(device.name) \(servicesDebug) \(device.state)")
						.background(debugColour)
					
				}
			}
		}	
	}
}

#Preview 
{
	BluetoothManagerView()
		.frame(minWidth: 300,minHeight: 100)
}

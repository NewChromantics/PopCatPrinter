import SwiftUI
import CoreBluetooth
import Combine


private func checksum(_ data: [UInt8], startIndex: Int, amount: Int) -> UInt8 {
	var b2: UInt8 = 0
	for value in data[startIndex..<(startIndex + amount)] {
		b2 = checksumTable[Int((b2 ^ value) & 0xff)]
	}
	return b2
}

private var checksumTable: [UInt8] {
	[
		0x00, 0x07, 0x0e, 0x09, 0x1c, 0x1b, 0x12, 0x15, 0x38, 0x3f, 0x36, 0x31, 
		0x24, 0x23, 0x2a, 0x2d, 0x70, 0x77, 0x7e, 0x79, 0x6c, 0x6b, 0x62, 0x65,
		0x48, 0x4f, 0x46, 0x41, 0x54, 0x53, 0x5a, 0x5d, 0xe0, 0xe7, 0xee, 0xe9,
		0xfc, 0xfb, 0xf2, 0xf5, 0xd8, 0xdf, 0xd6, 0xd1, 0xc4, 0xc3, 0xca, 0xcd,
		0x90, 0x97, 0x9e, 0x99, 0x8c, 0x8b, 0x82, 0x85, 0xa8, 0xaf, 0xa6, 0xa1,
		0xb4, 0xb3, 0xba, 0xbd, 0xc7, 0xc0, 0xc9, 0xce, 0xdb, 0xdc, 0xd5, 0xd2,
		0xff, 0xf8, 0xf1, 0xf6, 0xe3, 0xe4, 0xed, 0xea, 0xb7, 0xb0, 0xb9, 0xbe,
		0xab, 0xac, 0xa5, 0xa2, 0x8f, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9d, 0x9a,
		0x27, 0x20, 0x29, 0x2e, 0x3b, 0x3c, 0x35, 0x32, 0x1f, 0x18, 0x11, 0x16,
		0x03, 0x04, 0x0d, 0x0a, 0x57, 0x50, 0x59, 0x5e, 0x4b, 0x4c, 0x45, 0x42,
		0x6f, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7d, 0x7a, 0x89, 0x8e, 0x87, 0x80,
		0x95, 0x92, 0x9b, 0x9c, 0xb1, 0xb6, 0xbf, 0xb8, 0xad, 0xaa, 0xa3, 0xa4,
		0xf9, 0xfe, 0xf7, 0xf0, 0xe5, 0xe2, 0xeb, 0xec, 0xc1, 0xc6, 0xcf, 0xc8,
		0xdd, 0xda, 0xd3, 0xd4, 0x69, 0x6e, 0x67, 0x60, 0x75, 0x72, 0x7b, 0x7c,
		0x51, 0x56, 0x5f, 0x58, 0x4d, 0x4a, 0x43, 0x44, 0x19, 0x1e, 0x17, 0x10,
		0x05, 0x02, 0x0b, 0x0c, 0x21, 0x26, 0x2f, 0x28, 0x3d, 0x3a, 0x33, 0x34,
		0x4e, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5c, 0x5b, 0x76, 0x71, 0x78, 0x7f,
		0x6a, 0x6d, 0x64, 0x63, 0x3e, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2c, 0x2b,
		0x06, 0x01, 0x08, 0x0f, 0x1a, 0x1d, 0x14, 0x13, 0xae, 0xa9, 0xa0, 0xa7,
		0xb2, 0xb5, 0xbc, 0xbb, 0x96, 0x91, 0x98, 0x9f, 0x8a, 0x8d, 0x84, 0x83,
		0xde, 0xd9, 0xd0, 0xd7, 0xc2, 0xc5, 0xcc, 0xcb, 0xe6, 0xe1, 0xe8, 0xef,
		0xfa, 0xfd, 0xf4, 0xf3
	]
}

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
	var commandName : String { MXW01Peripheral.Command.GetName(self.command)	}
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
	@Published var printerVersion : String? = nil
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
	
	enum Command : UInt8
	{
		//	https://github.com/dropalltables/catprinter/blob/3d9d0d0835d99b856f7c58814ca193431ddbaf98/PROTOCOL.md?plain=1#L4
		case GetStatus = 0xA1
		case GetBattery = 0xAB
		case SetDarkness = 0xA2
		case StartPrint = 0xA9
		case FlushPrint = 0xAD
		case PrintFinished = 0xAA
		case GetPrintType = 0xB0
		case GetVersion = 0xB1
		case GetQueryCount = 0xA7
		case CancelPrint = 0xAC
		case PrintError = 0xAE

		static func GetName(_ value:UInt8) -> String
		{
			Command(rawValue: value).map{ "\($0)" } ?? "\(value)"
		}
					
	}
	let imageWidth = 384
	
	var control : CBCharacteristic? = nil
	var notification : CBCharacteristic? = nil
	var data : CBCharacteristic? = nil
	
	var pendingNotification = [UInt8:PromiseWrapper<Response>]()
	static let defaultPrintRowDelayMs = 40
	
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
					try await InitialisePrinter()
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
		
		let packetBytesDebug = packet.map{ Int($0) }
		print("Got notification \(packetBytesDebug)")
		
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

		let payloadBytesDebug = payload.map{ Int($0) }
		print("Got notification \(Command.GetName(command)) payload: \(payloadBytesDebug)")
		
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
		
		if let pendingNotification = pendingNotification[command]
		{
			pendingNotification.Resolve(response)
		}

		//	some generic response handling
		if command == Command.GetStatus.rawValue
		{
			_ = try OnStatus(payload)
			return
		}
		
		if command == Command.GetBattery.rawValue
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
		
		//	printing
		//new status x10 [1, 0, 0, 92, 35, 0, 0, 0, 175, 0]
		//	finished printing
		//New status x10 [0, 0, 0, 92, 40, 0, 0, 0, 163, 0]
		
		//	post-error payload?
		//	too hot? ran out of paper too
		//	[2, 0, 0, 86, 51, 0, 0, 0, 160, 0]
		
		//	0 - idle. 1-printing, 2-after lots of AE errors
		let printStatusMaybe = payload[0]
		
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
	
	func MakePacket(_ command:Command,payload:[UInt8],overrideTailByte:UInt8?=nil) -> Data
	{
		func calcCrc() -> UInt8
		{
			return checksum(payload,startIndex: 0,amount: payload.count)
		}
		
		let crc : UInt8 = calcCrc()
		let length16 = UInt16(payload.count)
		let lengthBytes = length16.littleEndianBytes
		let tailByte = overrideTailByte ?? 0xff
		
		let packetParts = 
		[
			[0x22,0x21,command.rawValue,0x0],
			lengthBytes,
			payload,
			[crc,tailByte]
		]
		let data = packetParts.flatMap{$0}
		return Data( Array(data) )
	}
	
	
	//	if expectedResponseCommand nil, then we expect the one we sent
	func SendPacketAndWaitForResponse(_ command:Command,payload:[UInt8],expectedResponseCommand:Command?=nil,overrideTailByte:UInt8?=nil) async throws -> Data
	{
		let packet = MakePacket(command, payload: payload, overrideTailByte:overrideTailByte )
		let responseCode = (expectedResponseCommand ?? command)
		
		if pendingNotification[responseCode.rawValue] != nil
		{
			throw PrintError("Already waiting for a notification for \(responseCode)")
		}
		
		//	setup promise to be resolved
		let pendingPromise = PromiseWrapper<Response>()
		pendingNotification[responseCode.rawValue] = pendingPromise
		peripheral.writeValue( packet, for:control!, type: .withoutResponse )

		let response = try await pendingPromise.Wait()
		pendingNotification.removeValue(forKey: command.rawValue)
		
		if response.command != responseCode.rawValue
		{
			throw PrintError("Notification for wrong command \(response.commandName) expected \(responseCode) (sent \(command))")
		}
		print("Notification for command \(response.commandName) recieved")
		
		return response.payload
	}

	func InitialisePrinter() async throws
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
		try await WaitForVersion()
		try await WaitForPrintType()
		try await WaitForQueryCount()
	}
	
	func PrintChequerBoard() async throws
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
		try await PrintImage(imageRowBits: patternBools,darkness:255,printRowDelayMs:MXW01Peripheral.defaultPrintRowDelayMs, onSentRow: {_ in})
	}
	
	func PrintImage(imageRowBits:[[Bool]],darkness:UInt8,printRowDelayMs:Int,onSentRow:(Int)->Void) async throws
	{
		try await WaitForIdleStatus()
		
		SetPrinterDarkness(darkness)
		
		func PackLineBits(_ lineBits:[Bool]) -> [UInt8]
		{
			//	init buffer
			let pixelsPerByte = PrintMode.OneBit.pixelsPerByte
			var rowBytes : [UInt8] = (0..<imageWidth/pixelsPerByte).map{ _ in 0 }
			for i in 0..<min(lineBits.count,imageWidth)
			{
				let Byte = i / pixelsPerByte
				let Bit = i % pixelsPerByte
				let Black = UInt8(0)
				let White = UInt8(1)
				let Value = lineBits[i] ? Black : White 
				rowBytes[Byte] |= (UInt8)(Value << Bit)
			}
			return rowBytes
		}
		let linePackedBytes = imageRowBits.map{ PackLineBits($0) }
		try await PrintPackedRows( linePackedBytes, pixelFormat: .OneBit, printRowDelayMs: printRowDelayMs, onSentRow: onSentRow )
	}
	
	//	4 bit print
	func PrintImage(imageRowNibbles:[[UInt8]],darkness:UInt8,printRowDelayMs:Int,onSentRow:(Int)->Void) async throws
	{
		try await WaitForIdleStatus()
		
		SetPrinterDarkness(darkness)
		
		func PackLine(_ lineNibbles:[UInt8]) -> [UInt8]
		{
			//	init buffer
			let pixelsPerByte = PrintMode.FourBit.pixelsPerByte
			let bitsPerPixel = PrintMode.FourBit.bitsPerPixel
			var rowBytes : [UInt8] = (0..<imageWidth/pixelsPerByte).map{ _ in 0 }
			for i in 0..<min(lineNibbles.count,imageWidth)
			{
				let Byte = i / pixelsPerByte
				let Bit = (i % pixelsPerByte) * bitsPerPixel
				let Value = lineNibbles[i]
				let invertedValue = (~Value) & 0x0f
				//let invertedValue = (0x0f - Value) & 0x0f
				rowBytes[Byte] |= (UInt8)(invertedValue << Bit)
			}
			return rowBytes
		}
		let linePackedBytes = imageRowNibbles.map{ PackLine($0) }
		try await PrintPackedRows( linePackedBytes, pixelFormat: .FourBit, printRowDelayMs:printRowDelayMs, onSentRow: onSentRow )
	}
	
	
	func WaitForBatteryLevel() async throws
	{
		print("Querying Battery...")
		let payload = try await SendPacketAndWaitForResponse( Command.GetBattery, payload: [0x0] )
		try OnBatteryLevel(payload)
	}
	
	func WaitForVersion() async throws
	{
		print("Querying Version...")
		let payload = try await SendPacketAndWaitForResponse( Command.GetVersion, payload: [0x0] )
		let versionString = String(decoding: payload, as: UTF8.self)
		DispatchQueue.main.async
		{
			@MainActor in
			self.printerVersion = versionString
		}
	}
	
	func WaitForPrintType() async throws
	{
		print("Querying Print Type...")
		let payload = try await SendPacketAndWaitForResponse( Command.GetPrintType, payload: [0x0] )
		
	}
	
	func WaitForQueryCount() async throws
	{
		print("Querying QueryCount...")
		let payload = try await SendPacketAndWaitForResponse( Command.GetQueryCount, payload: [0x0] )
		
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
		let payload = try await SendPacketAndWaitForResponse( Command.GetStatus, payload: [0x0])
		
		let status = try OnStatus(payload)
		return status
	}
	
	func SetPrinterDarkness(_ darknessLevel:UInt8) 
	{
		let setDarknessPacket = MakePacket( Command.SetDarkness,payload: [darknessLevel])
		print("Setting darkness to \(darknessLevel)...")
		peripheral.writeValue(setDarknessPacket, for: control!, type: .withoutResponse)
	}
	
	enum PrintMode : UInt8 
	{
		//	https://github.com/MaikelChan/CatPrinterBLE/blob/main/CatPrinterBLE/CatPrinter.cs#L41
		case OneBit = 0x0
		//Unknown01 = 0x1, // Similar to monochrome but doesn't eject as much paper after finishing printing?
		case FourBit = 0x2	//	0x2 from sniffing
		
		var bitsPerPixel : Int
		{
			switch self
			{
				case .OneBit:	return 1
				case .FourBit:	return 4
			}
		}
		var pixelsPerByte : Int
		{
			return 8 / bitsPerPixel
		}
	}
	
	func PrintPackedRows(_ linePackedBytes:[[UInt8]],pixelFormat:PrintMode,printRowDelayMs:Int,onSentRow:(Int)->Void) async throws
	{
		//	sniffed HD print
		//	2221 A9    00 	0400 			F001 		3002 0000  
		//	     PRint 00	payloadlen 4 	61441/496	
		
		
		
		//	image height=line count
		let lineCount = UInt16(linePackedBytes.count)
		let lineCountBytes = lineCount.littleEndianBytes
		let mode : UInt8 = pixelFormat.rawValue
		let payload = [ lineCountBytes, [0x30, mode] ].flatMap{$0}
		
		let response = try await SendPacketAndWaitForResponse( Command.StartPrint, payload: payload, overrideTailByte: 0x0 )
		let printError = response[0]
		if printError != 0
		{
			throw PrintError("Print request error; \(printError)")
		}
		print("Print accepted; \(response.map{Int($0)})")
		
		//	successfully sends 8384 bytes
		let allBytes = Data(linePackedBytes.flatMap{$0})
		
		//	sniffing bluetooth sent 182 byte chunks
		let maxTransmissionUnit = 182

		//	send in chunks
		for i in stride(from: 0, to: allBytes.count, by: maxTransmissionUnit)
		{
			let lastByte = min(allBytes.count,i+maxTransmissionUnit)
			let chunk = allBytes.subdata(in: i..<lastByte)
			//print("Sending \(chunk.map{Int($0)})")
			peripheral.writeValue( chunk, for: self.data!, type: .withoutResponse)
			
			let percent = Double(i) / Double(allBytes.count)
			let rowIndex = percent * Double(linePackedBytes.count)
			onSentRow(Int(rowIndex))
			
			await Task.sleep(milliseconds: printRowDelayMs)
		}
		/*
			//	send data
			for rowIndex in 0..<linePackedBytes.count
			{
				let packedLineBytes = linePackedBytes[rowIndex]
				//	verify data
				//	1bit data = 8 pixels per byte
				//	4bit = 2 pixels per byte
				//	row is 384 pixels wide
				let rowByteCount = imageWidth / pixelFormat.pixelsPerByte
				
				//let rowData = [UInt8](repeating: line, count: rowByteCount)
				let rowData = packedLineBytes
				if rowData.count != rowByteCount
				{
					throw PrintError("Row expected to have \(rowByteCount) bytes, but provided \(rowData.count)")
				}
				
				//	sniffing bluetooth sent 182 byte chunks
				//	this works! but printed white
				let shortData = Data(rowData).subdata(in: 0..<182)
				print("Sending \(shortData.map{Int($0)})")
				peripheral.writeValue( shortData, for: self.data!, type: .withoutResponse)
				
				onSentRow(rowIndex)
				
				await Task.sleep(milliseconds: printRowDelayMs)
			}
		*/

		//	send flush when finished
		let flushResponse = try await SendPacketAndWaitForResponse( Command.FlushPrint, payload:[0x0], expectedResponseCommand:Command.PrintFinished )
		let flushResponseDebug = flushResponse.map{ Int($0) }
		print("Flush response \(flushResponseDebug)")
		//	Wait for the AA notification on AE02, indicating the printer has finished the physical
		
		//	first send of 182 bytes got
		//	[252, 108, 193] and printed white
		
		let error = flushResponse[0]
		let value1 = flushResponse[1]
		let value2 = flushResponse[2]
		
		if error != 0
		{
			throw PrintError("Print error \(error) [\(value1),\(value2)]")
		}
		print("Print success; [\(value1),\(value2)]")
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

func imageToPixels<PixelFormat>(_ image: NSImage,convertPixel:(_ r:UInt8,_ g:UInt8,_ b:UInt8,_ a:UInt8)->PixelFormat) -> [[PixelFormat]]
{
	var rows = [[PixelFormat]]()
	
	let pixelData = (image.cgImage(forProposedRect: nil, context: nil, hints: nil)!).dataProvider!.data
	let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
	
	for y in 0..<Int(image.size.height) 
	{
		var row = [PixelFormat]()
		for x in 0..<Int(image.size.width) 
		{
			let pos = CGPoint(x: x, y: y)
			
			let pixelInfo: Int = ((Int(image.size.width) * Int(pos.y) * 4) + Int(pos.x) * 4)
			
			let r = data[pixelInfo]
			let g = data[pixelInfo + 1]
			let b = data[pixelInfo + 2]
			let a = data[pixelInfo + 3]
			
			let pixel = convertPixel(r,g,b,a)
			row.append(pixel)
		}
		rows.append(row)
	}
	return rows
}

// Get pixels from an NSImage
func imageToPixelsOneBit(_ image: NSImage,brightnessThreshold:UInt8) -> [[Bool]]
{
	let output = imageToPixels(image)
	{
		r,g,b,a in
		let pixel = r > brightnessThreshold
		return pixel
	}
	return output
}

func imageToPixelsFourBit(_ image: NSImage) -> [[UInt8]]
{
	let output = imageToPixels(image)
	{
		r,g,b,a in
		//let brightness = (Double(r)+Double(g)+Double(b)) / (255.0*3.0)
		let brightness = (Double(r)+Double(g)) / (255.0*2.0)
		let Max4 = Double(0x0f)
		let grey4 = Int(brightness * Max4)
		return UInt8(grey4)
	}
	return output
}

/*
func pixelsToImage(pixels: [[Bool]]) -> NSImage? 
{
	let height = pixelBits.count
	let width = pixelBits[0].count
	
	let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
	let bitsPerComponent = 8
	let bitsPerPixel = 32
	
	struct Pixel 
	{
		var a: UInt8
		var r: UInt8
		var g: UInt8
		var b: UInt8
		
		static let white = Pixel(a:255,r:255,g:255,b:255)
		static let black = Pixel(a:255,r:0,g:0,b:0)
	}
	
	func RowBitsToPixels(bits:[Bool]) -> [Pixel]
	{
		return bits.map{ $0 ? Pixel.white : Pixel.black }
	}
	let pixels = pixelBits.flatMap{ RowBitsToPixels(bits:$0) }
		
	var data = pixels
	guard let providerRef = CGDataProvider(data: NSData(bytes: &data,
														length: data.count * MemoryLayout<Pixel>.size)
	)
	else { return nil }
	
	guard let cgim = CGImage(
		width: width,
		height: height,
		bitsPerComponent: bitsPerComponent,
		bitsPerPixel: bitsPerPixel,
		bytesPerRow: width * MemoryLayout<Pixel>.size,
		space: rgbColorSpace,
		bitmapInfo: bitmapInfo,
		provider: providerRef,
		decode: nil,
		shouldInterpolate: true,
		intent: .defaultIntent
	)
	else { return nil }
	
	return NSImage(cgImage: cgim, size: CGSize(width: width, height: height))
}
*/

struct Pixel32
{
	var a: UInt8
	var r: UInt8
	var g: UInt8
	var b: UInt8
	
	static var bitsPerComponent : Int	{	8	}
	static var bitsPerPixel : Int	{	32	}
	static let white = Pixel32(a:255,r:255,g:255,b:255)
	static let black = Pixel32(a:255,r:0,g:0,b:0)
}

func pixelsToImage(pixels:[[Bool]]) -> NSImage?
{
	func BitToPixel(bit:Bool) -> Pixel32
	{
		return bit ? Pixel32.white : Pixel32.black
	}
	return pixelsToImage( pixels:pixels, convert:BitToPixel )
}


func pixelsToImage(pixels:[[UInt8]]) -> NSImage?
{
	func NibbleToPixel(nibble:UInt8) -> Pixel32
	{
		let Max4 = Double(0x0f)
		let nibblef = Double(nibble) / Max4
		let byte = UInt8(nibblef * 255.0)
		return Pixel32(a:255,r:byte,g:byte,b:byte)
	}
	return pixelsToImage( pixels:pixels, convert:NibbleToPixel )
}

func pixelsToImage<PixelFormat>(pixels:[[PixelFormat]],convert:(PixelFormat)->Pixel32) -> NSImage? 
{
	let height = pixels.count
	let width = pixels[0].count
	
	let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
	let bitsPerComponent = Pixel32.bitsPerComponent
	let bitsPerPixel = Pixel32.bitsPerPixel
	
	
	let pixels = pixels.flatMap{ $0.map{ convert($0) } }
	
	var data = pixels
	guard let providerRef = CGDataProvider(data: NSData(bytes: &data,
														length: data.count * MemoryLayout<Pixel32>.size)
	)
	else { return nil }
	
	guard let cgim = CGImage(
		width: width,
		height: height,
		bitsPerComponent: bitsPerComponent,
		bitsPerPixel: bitsPerPixel,
		bytesPerRow: width * MemoryLayout<Pixel32>.size,
		space: rgbColorSpace,
		bitmapInfo: bitmapInfo,
		provider: providerRef,
		decode: nil,
		shouldInterpolate: true,
		intent: .defaultIntent
	)
	else { return nil }
	
	return NSImage(cgImage: cgim, size: CGSize(width: width, height: height))
}

//	because the peripheral is a class, it needs it's own view 
//	with @StateObject in order to see changes
struct PrinterView : View 
{
	@StateObject var printer : MXW01Peripheral

	var sourceImage = NSImage(named:"HoltsHitAndRun")!
	@State var error : Error? = nil
	var printProgressPercent : Float? {	printProgress.map{ Float($0.0) / Float($0.1-1) } }
	@State var printProgress : (Int,Int)? = nil	//	0..1

	@State var brightnessThresholdFloat : Float = 0.5
	var brightnessThreshold : UInt8	{	UInt8( brightnessThresholdFloat * 255.0 )	}
	@State var oneBitPixels : [[Bool]]? = nil
	@State var oneBitImage : NSImage? = nil
	@State var fourBitPixels : [[UInt8]]? = nil
	@State var fourBitImage : NSImage? = nil
	
	@State var printerDarknessFloat : Float = 0.5
	var printerDarkness : UInt8	{	UInt8( printerDarknessFloat * 255.0 )	}
	
	@State var printRowDelayMsFloat : Float = Float(MXW01Peripheral.defaultPrintRowDelayMs)
	var printRowDelayMs : Int	{	Int( printRowDelayMsFloat )	}
	
	func UpdateThresholdedImage()
	{
		oneBitPixels = imageToPixelsOneBit( sourceImage, brightnessThreshold: brightnessThreshold )
		oneBitImage = pixelsToImage( pixels: oneBitPixels! )
		fourBitPixels = imageToPixelsFourBit( sourceImage )
		fourBitImage = pixelsToImage( pixels: fourBitPixels! )
	}
	
	func OnPrintProgress(_ row:Int,_ rowCount:Int)
	{
		printProgress = (row,rowCount)
	}
	
	func OnClickedPrintOneBit()
	{
		Task
		{
			error = nil
			do
			{
				UpdateThresholdedImage()
				OnPrintProgress(0,oneBitPixels!.count)
				try await printer.PrintImage(imageRowBits: oneBitPixels!,darkness: printerDarkness, printRowDelayMs: self.printRowDelayMs, onSentRow: { row in OnPrintProgress(row,oneBitPixels!.count) } )
			}
			catch
			{
				self.error = error
			}
		}
	}
	
	func OnClickedPrintFourBit()
	{
		error = nil
		Task
		{
			do
			{
				UpdateThresholdedImage()
				try await printer.PrintImage(imageRowNibbles: fourBitPixels!,darkness: printerDarkness, printRowDelayMs: self.printRowDelayMs, onSentRow: { row in OnPrintProgress(row,fourBitPixels!.count) } )
			}
			catch
			{
				self.error = error
			}
		}
	}
	
	@ViewBuilder func StatusView() -> some View
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
			if let version = printer.printerVersion
			{
				Label("Version \(version)",systemImage: "info.square.fill")
			}
		}
	}
	
	@ViewBuilder func ImageAndPrintView() -> some View
	{
		VStack(alignment: .leading,spacing: 10)
		{
			Slider(value: $brightnessThresholdFloat, in: 0...1)
			{
				Text("Brightness threshold \(brightnessThreshold)")
			}
			.onChange(of: self.brightnessThresholdFloat )
			{
				UpdateThresholdedImage()
			}
			.onAppear
			{
				UpdateThresholdedImage()
			}
			
			Slider(value: $printerDarknessFloat, in: 0...1)
			{
				Text("Printer Darkness \(printerDarkness)")
			}
			
			Slider(value: $printRowDelayMsFloat, in: 0...100)
			{
				Text("Printer Row Delay Milliseconds \(printRowDelayMs)")
			}
			
			HStack
			{
				VStack
				{
					Image( nsImage: oneBitImage ?? sourceImage )
						.resizable()
						.scaledToFit()
					
					Button(action:OnClickedPrintOneBit)
					{
						Text("Print One Bit")
					}
				}
				
				VStack
				{
					Image( nsImage: fourBitImage ?? sourceImage )
						.resizable()
						.scaledToFit()
					
					Button(action:OnClickedPrintFourBit)
					{
						Text("Print Four Bit")
					}
				}
			}
			
			HStack
			{
				ProgressView(value: self.printProgressPercent)
				let progressDebug = printProgress.map{ "\($0+1)/\($1)" } ?? " "
				Text("Progress \(progressDebug)")
			}
		}
	}
	
	@ViewBuilder func ErrorView() -> some View
	{
		if let error 
		{
			Text(error.localizedDescription)
				.padding(5)
				.frame(maxWidth:.infinity)
				.foregroundStyle(.white)
				.background(.red)
				.onTapGesture {
					self.error = nil
				}
		}
	}
	
	var body: some View
	{
		ErrorView()
		HStack(alignment: .top)
		{
			StatusView()
			ImageAndPrintView()
		}
		.padding(20)
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
			VStack
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
			if printers.mxw01s.count == 0
			{
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

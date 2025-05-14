import CoreBluetooth


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


//	todo: make a generic Printer protocol (but with an observable state)
//		and don't expose the low level MXW01 out of the lib
public class MXW01Peripheral : NSObject, BluetoothPeripheralHandler, CBPeripheralDelegate, Identifiable, Printer
{
	private var peripheral : CBPeripheral
	public var id : UUID	{	peripheral.identifier	}
	var services : [CBService]	{	peripheral.services ?? []	}
	public var name : String	{	peripheral.name ?? "\(peripheral.identifier)"	}
	var state : CBPeripheralState	{	peripheral.state	}
	
	//	need this to be a hard variable
	@Published public var status: PrinterStatus?
	var calculatedstatus: PrinterStatus?
	{
		if hardwareStatus == .Idle && isPrinting
		{
			return .Printing
		}
		return hardwareStatus
	}
	private var hardwareStatus: PrinterStatus?
	var isPrinting = false	//	essentially a lock
	
	@Published public var version: String?
	@Published public var error : Error? = nil
	@Published public var batteryLevelPercent : Int? = nil
	@Published public var tempratureCentigrade : Int? = nil
	
	
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
	static let defaultPrintRowDelayMs = 30	//	20 too fast for 4bpp
	
	init(peripheral: CBPeripheral) 
	{
		self.peripheral = peripheral
		super.init()
		
		//	setup handling
		self.peripheral.delegate = self
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
	
	public func OnConnected() 
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
			self.error = error
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) 
	{
		if let error 
		{
			print("didDiscoverServices error \(error.localizedDescription)")
			self.error = error
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
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) 
	{
		if let error 
		{
			print("didDiscoverCharacteristicsFor error \(error.localizedDescription)")
			self.error = error
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
	public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) 
	{
		if let error 
		{
			print("didUpdateNotificationStateFor \(characteristic.name) error \(error.localizedDescription)")
			OnError(error)
			return
		}
		print("Characteristic Notification for \(characteristic.name) now \(characteristic.isNotifying)")
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) 
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
			self.error = error
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) 
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
		//	overallstatus 8 when battery < 50%
		//	9 when turned off?
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
		
		self.hardwareStatus = printerStatus
		OnStatusChanged()
		
		DispatchQueue.main.async
		{
			@MainActor in
			self.tempratureCentigrade = Int(temprature)
			self.batteryLevelPercent = Int(batteryLevel)
		}
		
		return printerStatus
	}
	
	func OnStatusChanged()
	{
		DispatchQueue.main.async
		{
			@MainActor in
			self.status = self.calculatedstatus
		}
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
	
	func PrintChequerBoard(printFormat:PrintPixelFormat) async throws
	{
		func CharToGreyscalePixel(_ char:String.Element) -> UInt8
		{
			return char == " " ? 0x00 : 0xff
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
		let patternBools = pattern.map{ $0.map(CharToGreyscalePixel) }
		try await PrintImage(pixels: patternBools,printFormat:printFormat,darkness:1.0,printRowDelayMs:MXW01Peripheral.defaultPrintRowDelayMs, onProgress: {_ in})
	}
	
	static func PixelToOneBitInverted(_ luma:UInt8) -> UInt8
	{
		let white = luma > 128
		return white ? 0x1 : 0x0
	}

	static func PixelToFourBitInverted(_ luma:UInt8) -> UInt8
	{
		let luma4 = PixelToFourBit(luma)
		let inverted = (~luma4) & 0x0f
		return inverted
	}
	
	static func PixelToFourBit(_ luma:UInt8) -> UInt8
	{
		return luma >> 4
	}
	
	public func PrintImage(pixels:[[UInt8]],printFormat:PrintPixelFormat,darkness:Double,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
	{
		if status == .Printing
		{
			throw PrintError("Already printing")
		}
		try await WaitForIdleStatus()
		
		isPrinting = true
		OnStateChanged()
		defer
		{
			isPrinting = false
			OnStateChanged()
		}
		
		SetPrinterDarkness(darkness)
		
		func PackLineOneBit(_ pixels:[UInt8]) -> [UInt8]
		{
			//	init buffer
			let pixelsPerByte = PrintPixelFormat.OneBit.pixelsPerByte
			var rowBytes : [UInt8] = (0..<imageWidth/pixelsPerByte).map{ _ in 0 }
			for i in 0..<min(pixels.count,imageWidth)
			{
				let byte = i / pixelsPerByte
				let bit = i % pixelsPerByte
				let value = MXW01Peripheral.PixelToOneBitInverted(pixels[i])
				rowBytes[byte] |= value << bit
			}
			return rowBytes
		}
		
		func PackLineFourBit(_ pixels:[UInt8]) -> [UInt8]
		{
			//	init buffer
			let pixelsPerByte = PrintPixelFormat.FourBit.pixelsPerByte
			let bitsPerPixel = PrintPixelFormat.FourBit.bitsPerPixel
			var rowBytes : [UInt8] = (0..<imageWidth/pixelsPerByte).map{ _ in 0 }
			for i in 0..<min(pixels.count,imageWidth)
			{
				let byte = i / pixelsPerByte
				let bit = (i % pixelsPerByte) * bitsPerPixel
				let value = MXW01Peripheral.PixelToFourBitInverted(pixels[i])
				rowBytes[byte] |= value << bit
			}
			return rowBytes
		}

		let linePackedBytes = {
			switch printFormat
			{
				case .OneBit:	return pixels.map{ PackLineOneBit($0) }
				case .FourBit:	return pixels.map{ PackLineFourBit($0) }
			}
		}()
		try await PrintPackedRows( linePackedBytes, pixelFormat: printFormat, printRowDelayMs: printRowDelayMs, onProgress: onProgress )
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
			self.version = versionString
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
	
	func SetPrinterDarkness(_ darknessLevel:Double) 
	{
		let darkness8 = UInt8( darknessLevel * 255.0 )
		let setDarknessPacket = MakePacket( Command.SetDarkness,payload: [darkness8])
		print("Setting darkness to \(darkness8)...")
		peripheral.writeValue(setDarknessPacket, for: control!, type: .withoutResponse)
	}
	
	
	
	func PrintPackedRows(_ linePackedBytes:[[UInt8]],pixelFormat:PrintPixelFormat,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
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
			
			let percent = (Double(i) / Double(allBytes.count)) * 100.0
			
			onProgress(Int(percent))
			
			await Task.sleep(milliseconds: printRowDelayMs)
		}
		
		//	just to clean up progress
		//	gr: should be 99?
		onProgress(100)
		
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



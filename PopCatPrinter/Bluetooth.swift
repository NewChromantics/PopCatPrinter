import SwiftUI
import CoreBluetooth



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
	static let mxw10PrinterServiceUid = CBUUID(string: "0000ae30-0000-1000-8000-00805f9b34fb")
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


public protocol BluetoothPeripheralHandler
{
	func OnConnected()
}

class MXW01Peripheral : NSObject, BluetoothPeripheralHandler, CBPeripheralDelegate, Identifiable, ObservableObject
{
	private var peripheral : CBPeripheral
	var id : UUID	{	peripheral.identifier	}
	var services : [CBService]	{	peripheral.services ?? []	}
	var name : String	{	peripheral.name ?? "\(peripheral.identifier)"	}
	var state : CBPeripheralState	{	peripheral.state	}
	//@Published var state : CBPeripheralState = .disconnected
	
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
	
	func OnConnected() 
	{
		print("Mxw01 connected!")
		OnStateChanged()

		//	start fetching services
		peripheral.discoverServices(nil)
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) 
	{
		let services = peripheral.services ?? []
		let name = peripheral.name ?? "noname"
		print("did discover services x\(services.count) for \(name) (\(peripheral.state))")
		OnStateChanged()
	}
	
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
	
		print("Updating \(name) (\(peripheral.state))")
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
	
	var body: some View
	{
		let debugColour = printer.debugColour
		let servicesDebug = printer.services.count > 0 ? "(\(printer.services.count) services)" : ""
		Text("Device Name: \(printer.name) \(servicesDebug) \(printer.state)")
			.background(debugColour)
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

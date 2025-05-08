import SwiftUI
import CoreBluetooth


//	Printer found: "MXW01" - {"id":"Yl2JxVBQJjs7IRbZDVyrWQ=="}

//	https://github.com/rbaron/catprinter/compare/main...jeremy46231:MXW01-catprinter:main
//	https://catprinter.vercel.app/
let mxw10PrinterServiceUid = CBUUID(string: "0000ae30-0000-1000-8000-00805f9b34fb")
let mxw10DeviceName = "MXW01"

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
	//var hashValue: Int {	id.hashValue	}
	var id : UUID	{	deviceUid	}
	var deviceUid : UUID
	var name : String
	var state : CBPeripheralState
	var printerServices : [CBService]
	
	var debugColour : Color
	{
		let IsPrinter = !printerServices.isEmpty
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

class BluetoothManager : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject
{
	var centralManager : CBCentralManager!
	var devices : [BluetoothDevice]	{	Array(deviceStates).sorted()	}
	@Published var lastState : CBManagerState = .unknown
	@Published var isScanning : Bool = false
	@Published var deviceStates = Set<BluetoothDevice>()
	var showNoNameDevices = false
	
	//	need to keep a strong reference to peripherals we're connecting to
	var connectingPeripherals = [CBPeripheral]()
	
	override init()
	{
		super.init()
		centralManager = CBCentralManager(delegate: self, queue: nil)
	}
	
	func updateDeviceState(_ peripheral:CBPeripheral)
	{
		let name = peripheral.name ?? "\(peripheral.identifier)"
		
		if peripheral.services == nil
		{
			//peripheral.discoverServices(nil)
		}
		
		var printerServices = peripheral.services ?? []
		/*
		printerServices = printerServices.filter
		{
			$0.uuid == mxw10PrinterServiceUid
		}
		*/
		let device = BluetoothDevice(deviceUid: peripheral.identifier, name: name, state: peripheral.state, printerServices: printerServices)
		
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
		if !showNoNameDevices && peripheral.name == nil
		{
			return
		}
		
		
		let name = peripheral.name ?? "\(peripheral.identifier)"
		peripheral.delegate = self
		
		if peripheral.name == mxw10DeviceName
		{
			if peripheral.state == .disconnected
			{
				connectingPeripherals.append(peripheral)
				central.connect(peripheral)
			}
		}
		
		print("Updating \(name) (\(peripheral.state))")
		updateDeviceState(peripheral)
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) 
	{
		let services = peripheral.services ?? []
		let name = peripheral.name ?? "noname"
		print("did discover services x\(services.count) for \(name) (\(peripheral.state))")
		updateDeviceState(peripheral)
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) 
	{
		print("Connected to peripheral \(peripheral.name) (\(peripheral.state))")
		peripheral.discoverServices([mxw10PrinterServiceUid])
		updateDeviceState(peripheral)
		//self.peripheral?.discoverServices(nil) //can provide array of specific services
		//self.peripheral?.delegate = self
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
			VStack
			{
				ForEach( bluetoothManager.devices )
				{
					device in
					let debugColour = device.debugColour
					let printersDebug = device.printerServices.count > 0 ? "(\(device.printerServices.count) printer)" : ""
					Text("Device Name: \(device.name) \(printersDebug) \(device.state)")
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

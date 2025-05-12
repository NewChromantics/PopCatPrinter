import SwiftUI



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

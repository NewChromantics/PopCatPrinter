/*
 
	CoreBluetooth extensions
 
*/
import CoreBluetooth



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




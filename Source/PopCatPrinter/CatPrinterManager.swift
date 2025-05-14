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



//	https://github.com/rbaron/catprinter/compare/main...jeremy46231:MXW01-catprinter:main
//	https://catprinter.vercel.app/
public class CatPrinterManager : ObservableObject
{
	var bluetoothManager : BluetoothManager!
	@Published public var mxw01s = [MXW01Peripheral]()
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




struct Response
{
	var payload : Data
	var command : UInt8
	var commandName : String { MXW01Peripheral.Command.GetName(self.command)	}
}



func imageToPixels<PixelFormat>(_ image: UIImage,rotate90:Bool,convertPixel:(_ r:UInt8,_ g:UInt8,_ b:UInt8,_ a:UInt8)->PixelFormat) throws -> [[PixelFormat]]
{
	var rows = [[PixelFormat]]()

	guard let imageCg = image.cgImage else
	{
		throw PrintError("Failed to get cg image from image")
	}
	let pixelData = imageCg.dataProvider!.data
	
	let width = imageCg.width
	let height = imageCg.height
	let pixelFormat = imageCg.pixelFormatInfo
	let bitsPerPixel = imageCg.bitsPerPixel
	let bytesPerPixel = bitsPerPixel / 8
	let bytesPerPixel2 = imageCg.bytesPerRow / width
	let bitsPerComponent = imageCg.bitsPerComponent
	let rowStride = imageCg.bytesPerRow / bytesPerPixel	//	some images are padded!
	let channels = bytesPerPixel
	let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
	
	let outputHeight = rotate90 ? width : height
	let outputWidth = rotate90 ? height : width 
	
	for y in 0..<outputHeight
	{
		var row = [PixelFormat]()
		row.reserveCapacity(outputWidth)
		
		for x in 0..<outputWidth
		{
			let inputx = rotate90 ? y : x
			let inputy = rotate90 ? x : y
			
			let pixelIndex = (rowStride * inputy ) + inputx
			let byteIndex = pixelIndex * bytesPerPixel
			let redIndex = 0
			let greenIndex = min( 1, channels-1 )
			let blueIndex = min( 2, channels-1 )
			let alphaIndex = min( 3, channels-1 )
			
			let r = data[byteIndex+redIndex]
			let g = data[byteIndex+greenIndex]
			let b = data[byteIndex+blueIndex]
			let a = data[byteIndex+alphaIndex]
			
			let pixel = convertPixel(r,g,b,a)
			row.append(pixel)
		}
		rows.append(row)
	}
	return rows
}


public let defaultFourBitHistogram = UnitCurve.linear

public func imageToPixelsLuma(_ image: UIImage,rotate90:Bool=false,fourBitHistogram:UnitCurve=defaultFourBitHistogram) throws -> [[UInt8]]
{
	func getCorrectedLuma(luma:Double) -> UInt8
	{
		let curvedValue = fourBitHistogram.value(at: luma)
		if curvedValue >= 1.0
		{
			return 0xff
		}
		if curvedValue <= 0.0
		{
			return 0x0
		}
		//let clampedCurvedValue = min( 1.0, max( 0.0, curvedValue ) )
		//	as we're clamping the float to 1.0 - we have to be careful not to exceed 255
		let curvedLuma = UInt8( curvedValue * Double(0xff) )
		return curvedLuma
	}
		
	let output = try imageToPixels(image,rotate90:rotate90)
	{
		r,g,b,a in
		//let brightness = (Double(r)+Double(g)+Double(b)) / (255.0*3.0)
		let luma = (Double(r)+Double(g)) / (255.0*2.0)
		let curvedLuma = getCorrectedLuma(luma: luma)
		return curvedLuma
	}
	return output
}



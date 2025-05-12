import SwiftUI







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

func pixelsToImage(pixels:[[Bool]]) -> UIImage?
{
	func BitToPixel(bit:Bool) -> Pixel32
	{
		return bit ? Pixel32.white : Pixel32.black
	}
	return pixelsToImage( pixels:pixels, convert:BitToPixel )
}


func pixelsToImage(pixels:[[UInt8]]) -> UIImage?
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

func pixelsToImage<PixelFormat>(pixels:[[PixelFormat]],convert:(PixelFormat)->Pixel32) -> UIImage? 
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
	
#if canImport(UIKit)//ios
	return UIImage(cgImage: cgim)
#else
	return UIImage(cgImage: cgim, size: CGSize(width: width, height: height))
#endif
}


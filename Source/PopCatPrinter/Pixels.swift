import SwiftUI
import Accelerate






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

public func pixelsToImage(pixels:[[Bool]],rotateRight:Bool) throws -> UIImage
{
	func BitToPixel(bit:Bool) -> Pixel32
	{
		return bit ? Pixel32.white : Pixel32.black
	}
	return try pixelsToImage( pixels:pixels, rotateRight: rotateRight, convert:BitToPixel )
}


public func pixelsToImage(pixels:[[UInt8]],rotateRight:Bool) throws -> UIImage
{
	func NibbleToPixel(nibble:UInt8) -> Pixel32
	{
		let Max4 = Double(0x0f)
		let nibblef = Double(nibble) / Max4
		let byte = UInt8(nibblef * 255.0)
		return Pixel32(a:255,r:byte,g:byte,b:byte)
	}
	return try pixelsToImage( pixels:pixels, rotateRight:rotateRight, convert:NibbleToPixel )
}

func pixelsToImage<PixelFormat>(pixels:[[PixelFormat]],rotateRight:Bool,convert:(PixelFormat)->Pixel32) throws -> UIImage 
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
	else 
	{
		throw PrintError("Failed to allocate CGImage data")
	}
	
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
	else 
	{
		throw PrintError("Failed to create CGImage data")
	}
	
	var output = cgim
	
	if rotateRight
	{
		guard let rotated = cgim.pixelsRotated(degrees: -90 ) else
		{
			throw PrintError("failed to rotate cg image")
		}
		output = rotated
	}
	
#if canImport(UIKit)//ios
	return UIImage(cgImage: output)
#else
	//	todo: rotate 
	return UIImage(cgImage: output, size: CGSize(width: output.width, height: output.height) )
#endif
}

public func degreesToRadians(_ value: Float) -> Float
{
	return value * Float.pi / 180
}
public let numberOfComponentsPerARBGPixel = 4
public let numberOfComponentsPerRGBAPixel = 4
public let numberOfComponentsPerGrayPixel = 3
public let minPixelComponentValue = UInt8(0)

public extension CGContext
{
	// MARK: - ARGB bitmap context
	public class func ARGBBitmapContext(width: Int, height: Int, withAlpha: Bool) -> CGContext?
	{
		let alphaInfo = withAlpha ? CGImageAlphaInfo.premultipliedFirst : CGImageAlphaInfo.noneSkipFirst
		let bmContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * numberOfComponentsPerARBGPixel, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alphaInfo.rawValue)
		return bmContext
	}
	
	// MARK: - RGBA bitmap context
	public class func RGBABitmapContext(width: Int, height: Int, withAlpha: Bool) -> CGContext?
	{
		let alphaInfo = withAlpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
		let bmContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * numberOfComponentsPerRGBAPixel, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alphaInfo.rawValue)
		return bmContext
	}
	
	// MARK: - Gray bitmap context
	public class func GrayBitmapContext(width: Int, height: Int) -> CGContext?
	{
		let bmContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * numberOfComponentsPerGrayPixel, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
		return bmContext
	}
}

extension CGImage
{
	public func pixelsRotated(degrees: Float) -> CGImage?
	{
		return self.pixelsRotated(radians: degreesToRadians(degrees))
	}
	
	public func pixelsRotated(radians: Float) -> CGImage?
	{
		guard let selfContext = CGContext.ARGBBitmapContext(width: self.width, height: self.height, withAlpha: true) else
		{
			return nil
		}
		selfContext.setFillColor(CGColor.init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
		selfContext.fill([CGRect(x:0,y:0,width:selfContext.width,height:selfContext.height)])
		selfContext.draw(self, in: CGRect(x:0, y:0, width:self.width, height:self.height))
		guard let selfContextData = selfContext.data else
		{
			return nil
		}
		
		guard let rotContext = CGContext.ARGBBitmapContext(width: self.height, height: self.width, withAlpha: true) else
		{
			return nil
		}
		rotContext.setFillColor(CGColor.init(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0))
		rotContext.fill([CGRect(x:0,y:0,width:rotContext.width,height:rotContext.height)])
		guard let rotContextData = rotContext.data else
		{
			return nil
		}
		
		var src = vImage_Buffer(data: selfContextData, height: vImagePixelCount(selfContext.height), width: vImagePixelCount(selfContext.width), rowBytes: selfContext.bytesPerRow)
		var dst = vImage_Buffer(data: rotContextData, height: vImagePixelCount(rotContext.height), width: vImagePixelCount(rotContext.width), rowBytes: rotContext.bytesPerRow)
		let bgColor: [UInt8] = [0, 0, 255, 255]
		vImageRotate_ARGB8888(&src, &dst, nil, radians, bgColor, vImage_Flags(kvImageBackgroundColorFill))
		
		guard let rotImage = rotContext.makeImage() else
		{
			return nil
		}
		return rotImage
	}
}

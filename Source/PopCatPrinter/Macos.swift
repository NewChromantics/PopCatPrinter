import SwiftUI





#if canImport(UIKit)//ios
#else
public typealias UIColor = NSColor
public typealias UIImage = NSImage

//	accessor missing in macos
extension UIImage
{
	var cgImage : CGImage?
	{
		return self.cgImage(forProposedRect: nil, context: nil, hints: nil)
	}
}

//	use same Image(uiImage:) constructor on macos & ios
extension Image
{
	public init(uiImage:UIImage)
	{
		self.init(nsImage:uiImage)
	}
}

#endif


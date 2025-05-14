import SwiftUI


public enum PrintPixelFormat : UInt8 
{
	//	These are the values for the MXW01
	//	move this to explicilty be in the MXW01 code
	case OneBit = 0x0
	case FourBit = 0x2
	
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


public enum PrinterStatus
{
	case Disconnected,Idle,PaperMissing,NotOkay,Printing
}

public protocol Printer : ObservableObject, Identifiable
{
	//	implement these with @Published
	var name : String { get }
	var error : Error? {get}
	var status : PrinterStatus? {get}
	var batteryLevelPercent : Int? {get}
	var tempratureCentigrade : Int? {get}
	var version : String? {get}
	
	//	when sending pixels, send a full 8bit component
	//	- printing one-bit will threshold white/black at 128
	//	- printing four bit will half the value provided 
	func PrintImage(pixels:[[UInt8]],printFormat:PrintPixelFormat,darkness:Double,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
}


public func GetBatteryIconName(percent:Int?) -> String
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


public extension Printer
{
	var errorString : String? { self.error.map{ $0.localizedDescription } }

	var batteryLevelIconName : String	{	GetBatteryIconName(percent: batteryLevelPercent)	}
	
	var printerStatusIconName : String	
	{
		switch self.status
		{
			case nil:	return "questionmark.app.fill"
			case .Disconnected:	return "powerplug"
			case .PaperMissing:	return "newspaper"
			case .NotOkay:	return "exclamationmark.triangle.fill"
			case .Idle:	return "checkmark.seal"
			case .Printing: return "printer.filled.and.paper"
		}
	}
}

//	todo: use for unit test
public class FakePrinter : Printer
{
	public var name: String	{	"Fake Printer"	}
	
	@Published public var error : Error? = nil
	@Published public var status: PrinterStatus?
	@Published public var batteryLevelPercent: Int?
	@Published public var tempratureCentigrade: Int?
	@Published public var version: String?

	public init()
	{
		Task
		{
			try await DelayedInit()
		}
	}
	
	func DelayedInit() async throws
	{
		try await Task.sleep(for:.seconds(1))
		status = .PaperMissing
		batteryLevelPercent = 51
		tempratureCentigrade = 30
		version = "Fake Printer"
		
		try await Task.sleep(for:.seconds(5))
		self.error = PrintError("Fake print init error")
	}
	
	public func PrintImage(pixels: [[UInt8]],printFormat:PrintPixelFormat,darkness:Double,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
	{
		throw PrintError("Test printer doesnt support PrintImage") 
	}

}

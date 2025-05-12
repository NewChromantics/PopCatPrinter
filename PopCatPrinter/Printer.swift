import SwiftUI

public enum PrinterStatus
{
	case Disconnected,Idle,PaperMissing,NotOkay
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
	
	func PrintOneBitImage(pixels:[[Bool]],darkness:Float,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
	func PrintFourBitImage(pixels:[[UInt8]],darkness:Float,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
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
	
	public func PrintOneBitImage(pixels: [[Bool]],darkness:Float,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
	{
		throw PrintError("Test printer doesnt support PrintOneBitImage") 
	}
	
	public func PrintFourBitImage(pixels: [[UInt8]],darkness:Float,printRowDelayMs:Int,onProgress:(Int)->Void) async throws
	{
		throw PrintError("Test printer doesnt support PrintFourBitImage") 
	}
	

}

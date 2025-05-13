import SwiftUI




//	because the peripheral is a class, it needs it's own view 
//	with @StateObject in order to see changes
public struct PrinterStatusView<PrinterType> : View where PrinterType:Printer 
{
	@StateObject var printer : PrinterType
	
	public init(printer: PrinterType)
	{
		self._printer = StateObject(wrappedValue: printer)
	}
	

	
	public var body: some View
	{
		VStack(alignment: .leading)
		{
			//let servicesDebug = printer.services.count > 0 ? "(\(printer.services.count) services)" : ""
			let batteryDebug = printer.batteryLevelPercent.map{ "\($0)%" } ?? "?"
			let statusDebug = printer.status.map{ "\($0)" } ?? "?"
			let tempDebug = printer.tempratureCentigrade.map{ "\($0)oC" } ?? "?"
			let tempIcon = printer.tempratureCentigrade != nil ? "thermometer.medium" : "thermometer.medium.slash"
			let printerStatusDebug = printer.status.map{ "\($0)" } ?? "??"
			
			Label("\(printer.name) \(printerStatusDebug)",systemImage: "printer.fill")
			Label("\(batteryDebug)",systemImage: printer.batteryLevelIconName )
			Label(tempDebug,systemImage: tempIcon )
			Label("Status: \(statusDebug)", systemImage: printer.printerStatusIconName )
			let version = printer.version ?? "?"
			Label("Version \(version)",systemImage: "info.square.fill")
			
			let hasError = printer.errorString != nil
			let error = printer.errorString ?? ""
			Label(error,systemImage: "exclamationmark.triangle.fill")
				.foregroundStyle( hasError ? .white : .clear )
				.background( hasError ? .red : .clear)
			
		}
	}
}



//	because the peripheral is a class, it needs it's own view 
//	with @StateObject in order to see changes
public struct PrinterView<PrinterType> : View where PrinterType:Printer 
{
	@StateObject var printer : PrinterType
	
	var sourceImage : UIImage
	@State var error : Error? = nil
	var printProgressPercentFloat : Float? {	printProgressPercent.map{ Float($0) / 100.0 } }
	@State var printProgressPercent : Int? = nil
	
	@State var brightnessThresholdFloat : Float = 0.5
	var brightnessThreshold : UInt8	{	UInt8( brightnessThresholdFloat * 255.0 )	}
	@State var oneBitPixels : [[Bool]]? = nil
	@State var oneBitImage : UIImage? = nil
	@State var fourBitPixels : [[UInt8]]? = nil
	@State var fourBitImage : UIImage? = nil
	
	@State var printerDarknessFloat : Double = 0.5
	var printerDarknessPercent : Int { Int(printerDarknessFloat*100.0) }
	
	@State var printRowDelayMsFloat : Float = Float(MXW01Peripheral.defaultPrintRowDelayMs)
	var printRowDelayMs : Int	{	Int( printRowDelayMsFloat )	}
	
	
	public init(printer: PrinterType, sourceImage: UIImage)
	{
		self._printer = StateObject(wrappedValue: printer)
		self.sourceImage = sourceImage
	}

	func UpdateThresholdedImageNoThrow()
	{
		do
		{
			try UpdateThresholdedImage()
		}
		catch
		{
			print(error.localizedDescription)
		}
	}
	
	func UpdateThresholdedImage() throws
	{
		oneBitPixels = try imageToPixelsOneBit( sourceImage, brightnessThreshold: brightnessThreshold )
		oneBitImage = pixelsToImage( pixels: oneBitPixels! )
		fourBitPixels = try imageToPixelsFourBit( sourceImage )
		fourBitImage = pixelsToImage( pixels: fourBitPixels! )
	}
	
	func OnPrintProgress(percent:Int)
	{
		printProgressPercent = percent
	}
	
	func OnClickedPrintOneBit()
	{
		Task
		{
			error = nil
			do
			{
				try UpdateThresholdedImage()
				OnPrintProgress(percent: 0)
				try await printer.PrintOneBitImage(pixels: oneBitPixels!,darkness: self.printerDarknessFloat,printRowDelayMs: self.printRowDelayMs, onProgress: {self.OnPrintProgress(percent:$0)} )
			}
			catch
			{
				self.error = error
			}
		}
	}
	
	func OnClickedPrintFourBit()
	{
		error = nil
		Task
		{
			do
			{
				try UpdateThresholdedImage()
				try await printer.PrintFourBitImage(pixels: fourBitPixels!,darkness: self.printerDarknessFloat,printRowDelayMs: self.printRowDelayMs, onProgress: {self.OnPrintProgress(percent:$0)} )
			}
			catch
			{
				self.error = error
			}
		}
	}
	
	
	@ViewBuilder func ImageAndPrintView() -> some View
	{
		VStack(alignment: .leading,spacing: 10)
		{
#if os(tvOS)
#else
			Slider(value: $brightnessThresholdFloat, in: 0...1)
			{
				Text("Brightness threshold \(brightnessThreshold)")
			}
			.onChange(of: self.brightnessThresholdFloat )
			{
				UpdateThresholdedImageNoThrow()
			}
			.onAppear
			{
				UpdateThresholdedImageNoThrow()
			}
			
			Slider(value: $printerDarknessFloat, in: 0...1)
			{
				Text("Printer Darkness \(printerDarknessPercent)%")
			}
			
			Slider(value: $printRowDelayMsFloat, in: 0...100)
			{
				Text("Printer Row Delay Milliseconds \(printRowDelayMs)")
			}
			#endif
			
			HStack
			{
				VStack
				{
					Image( uiImage: oneBitImage ?? sourceImage )
						.resizable()
						.scaledToFit()
					
					Button(action:OnClickedPrintOneBit)
					{
						Text("Print One Bit")
					}
				}
				
				VStack
				{
					Image( uiImage: fourBitImage ?? sourceImage )
						.resizable()
						.scaledToFit()
					
					Button(action:OnClickedPrintFourBit)
					{
						Text("Print Four Bit")
					}
				}
			}
			
			HStack
			{
				ProgressView(value: self.printProgressPercentFloat)
				let progressDebug = printProgressPercent.map{ "\($0)%" } ?? " "
				Text("Progress \(progressDebug)")
			}
		}
	}
	
	@ViewBuilder func ErrorView() -> some View
	{
		if let error 
		{
			Text(error.localizedDescription)
				.padding(5)
				.frame(maxWidth:.infinity)
				.foregroundStyle(.white)
				.background(.red)
//#if os(tvOS)
//#else
				.onTapGesture {
					self.error = nil
				}
//#endif
		}
	}
	
	public var body: some View
	{
		ErrorView()
		HStack(alignment: .top)
		{
			PrinterStatusView(printer: printer)
			ImageAndPrintView()
		}
		.padding(20)
	}
}



public struct CatPrinterManagerView : View 
{
	@StateObject var printers = CatPrinterManager()
	var printImage = UIImage(named:"HoltsHitAndRun")!
	
	public var body: some View 
	{
		let bluetoothManager = printers.bluetoothManager!
		VStack
		{
			Text("Printers: \(printers.mxw01s.count)")
			VStack
			{
				ForEach( printers.mxw01s )
				{
					(device:MXW01Peripheral) in
					PrinterView(printer: device, sourceImage: printImage)
				}
			}
			
			Text("Devices: \(bluetoothManager.devices.count)")
			Text("Manager State: \(bluetoothManager.lastState)")
			Text("Is Scanning: \(bluetoothManager.isScanning)")
			if printers.mxw01s.count == 0
			{
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
}


#Preview
{
	//CatPrinterManagerView()
	var fakePrinter = FakePrinter()
	//PrinterView(printer: fakePrinter, sourceImage: UIImage(named:"HoltsHitAndRun")! )
	PrinterStatusView(printer: fakePrinter)
}

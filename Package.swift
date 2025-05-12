// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.


import PackageDescription



let package = Package(
	name: "PopCatPrinter",
	
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
		.tvOS(.v16)
	],
	

	products: [
		.library(
			name: "PopCatPrinter",
			targets: [
				"PopCatPrinter"
			]),
	],
	targets: [

		.target(
			name: "PopCatPrinter"
			)
		
	]
)

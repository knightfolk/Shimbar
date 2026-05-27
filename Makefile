# Makefile for Shimbar macOS Menu Bar App

.PHONY: generate build run clean

generate:
	xcodegen generate

build:
	xcodebuild -scheme Shimbar -project Shimbar.xcodeproj -configuration Debug

run:
	open "/Users/kevink/Library/Developer/Xcode/DerivedData/Shimbar-akucyxaumvcqexaitrgxaaambulq/Build/Products/Debug/Shimbar.app"

clean:
	rm -rf Shimbar.xcodeproj
	xcodebuild -scheme Shimbar -project Shimbar.xcodeproj -configuration Debug clean

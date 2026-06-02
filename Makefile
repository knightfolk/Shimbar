# Makefile for Shimbar macOS Menu Bar App

.PHONY: generate build test run clean

generate:
	xcodegen generate

build:
	xcodebuild -scheme Shimbar -project Shimbar.xcodeproj -configuration Debug -derivedDataPath .build

test:
	xcodebuild test -scheme Shimbar -project Shimbar.xcodeproj -configuration Debug -derivedDataPath .build -only-testing:ShimbarTests

run:
	open ".build/Build/Products/Debug/Shimbar.app"

clean:
	rm -rf Shimbar.xcodeproj .build

# LumiSense iOS Launch Image Notes

## Purpose

This folder stores launch image assets used by the iOS Runner target.

LumiSense is currently Android-first, but these files are kept valid so iOS builds remain maintainable.

## Update Workflow

1. Open the iOS workspace at [lumisense/ios/Runner.xcworkspace](lumisense/ios/Runner.xcworkspace)
2. In Xcode, navigate to Runner > Assets.xcassets > LaunchImage
3. Replace launch images with exported assets using correct dimensions and scale variants
4. Keep the asset catalog metadata consistent so all required slots remain populated

## Asset Hygiene Rules

1. Do not remove scale variants without replacing them
2. Keep file naming stable unless the asset catalog mapping is updated
3. Verify launch screen appearance on at least one iPhone simulator before merging iOS visual updates

## Repository Context

For current project setup and implementation context, use:

1. [lumisense/README.md](lumisense/README.md)
2. [lumisense/SETUP.md](lumisense/SETUP.md)
3. [lumisense/ARCHITECTURE.md](lumisense/ARCHITECTURE.md)
# Deploy to TestFlight

Archive the SpeedRead app (iOS + watchOS) and upload to TestFlight.

## Prerequisites
- App Store Connect API key at `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`
- `ExportOptions.plist` in project root
- Valid code signing certificates in Keychain

## Steps

1. **Run tests first** to make sure nothing is broken:
```bash
cd "$PROJECT_DIR" && xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:SpeedReadTests -quiet 2>&1 | tail -20
```
If tests fail, STOP and report the failures. Do not proceed.

2. **Clean previous build artifacts:**
```bash
cd "$PROJECT_DIR" && rm -rf build/
```

3. **Archive** (includes watchOS companion automatically):
```bash
cd "$PROJECT_DIR" && xcodebuild archive \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -configuration Release \
  -archivePath build/SpeedRead.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8" \
  -authenticationKeyID XXXXXXXXXX \
  -authenticationKeyIssuerID "<ASC_ISSUER_ID>" \
  2>&1 | tail -20
```
Verify archive succeeded before continuing.

4. **Export + Upload to TestFlight:**
```bash
cd "$PROJECT_DIR" && xcodebuild -exportArchive \
  -archivePath build/SpeedRead.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8" \
  -authenticationKeyID XXXXXXXXXX \
  -authenticationKeyIssuerID "<ASC_ISSUER_ID>" \
  2>&1 | tail -30
```

5. **Report result** to the user:
   - If successful: "Build uploaded to TestFlight. It should appear in App Store Connect within 10-15 minutes."
   - If failed: Show the error output and suggest fixes.

## Variables
- `PROJECT_DIR` = `/Users/<operator>/Xcode Projects/SpeedRead`

## Important
- The `manageAppVersionAndBuildNumber` key in ExportOptions.plist means Apple auto-increments the build number. No manual version bumping needed.
- The archive includes the watchOS companion app automatically since it's a dependency of the SpeedRead scheme.
- Do NOT commit the `.p8` key file or `~/.appstoreconnect/` contents.
- If archive fails with signing errors, suggest the user open Xcode and verify signing settings under the SpeedRead target.

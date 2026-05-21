# Deploy to TestFlight

Archive SpeedRead (iOS + watchOS) and upload to TestFlight.

## Prerequisites
- App Store Connect API key at `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`
- ASC App ID: `6771221242`
- Bundle: `com.legitimateapps.SpeedRead`
- Team: `3LTL47SJ8C` (Legitimate Limited Liability Company)
- `ExportOptions.plist` in project root (method = `app-store`, destination = `upload`)
- `Config/SpeedRead-Info.plist` (partial Info.plist merged with auto-generated keys)

## Steps

1. **Run tests** (skip the known-flaky timing test):
```bash
cd "$PROJECT_DIR" && xcodebuild test -project SpeedRead.xcodeproj -scheme SpeedRead \
  -destination "platform=iOS Simulator,id=$(xcrun simctl list devices booted | grep 'iPhone 17' | head -1 | grep -oE '[0-9A-F-]{36}')" \
  -only-testing:SpeedReadTests \
  -skip-testing:SpeedReadTests/RSVPIntegrationTests/engineReachesEndOfText \
  -quiet 2>&1 | tail -5
```
If any non-skipped test fails, STOP. The `engineReachesEndOfText` test is a 500ms-sleep timing flake unrelated to release readiness.

2. **Bump versions if needed.** App Store Connect rejects new builds against an already-released `MARKETING_VERSION`. Before archiving, check:
```bash
python3 - <<'PYEOF'
import jwt, time, json, urllib.request
KEY="<ASC_KEY_ID>"; ISS="<ASC_ISSUER_ID>"; APP="6771221242"
with open("/Users/<operator>/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8") as f: pk = f.read()
now = int(time.time())
t = jwt.encode({"iss": ISS, "iat": now, "exp": now+1200, "aud": "appstoreconnect-v1"},
               pk, algorithm="ES256", headers={"kid": KEY, "typ": "JWT"})
req = urllib.request.Request(
    f"https://api.appstoreconnect.apple.com/v1/apps/{APP}/appStoreVersions?fields[appStoreVersions]=versionString,appStoreState&limit=5",
    headers={"Authorization": f"Bearer {t}"})
for v in json.loads(urllib.request.urlopen(req).read()).get("data", []):
    print(v["attributes"])
PYEOF
```
If the current `MARKETING_VERSION` is in state `READY_FOR_SALE` (or anything but `PREPARE_FOR_SUBMISSION`/`REJECTED`):
- bump `MARKETING_VERSION` in `SpeedRead.xcodeproj/project.pbxproj` (`sed -i '' 's/MARKETING_VERSION = X.Y;/MARKETING_VERSION = X.Y+1;/g'`)
- create the new App Store version via the ASC API:
```bash
python3 - <<'PYEOF'
import jwt, time, json, urllib.request, sys
KEY="<ASC_KEY_ID>"; ISS="<ASC_ISSUER_ID>"; APP="6771221242"
NEW_VERSION = "X.Y+1"  # replace with the new MARKETING_VERSION
with open("/Users/<operator>/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8") as f: pk = f.read()
now = int(time.time())
t = jwt.encode({"iss": ISS, "iat": now, "exp": now+1200, "aud": "appstoreconnect-v1"},
               pk, algorithm="ES256", headers={"kid": KEY, "typ": "JWT"})
payload = {"data": {"type": "appStoreVersions",
    "attributes": {"platform": "IOS", "versionString": NEW_VERSION, "releaseType": "MANUAL"},
    "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}}
req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/appStoreVersions",
    data=json.dumps(payload).encode(),
    headers={"Authorization": f"Bearer {t}", "Content-Type": "application/json"}, method="POST")
print(json.loads(urllib.request.urlopen(req).read())["data"]["id"])
PYEOF
```

Always bump `CURRENT_PROJECT_VERSION` too (build numbers are monotonic per app, not per version):
```bash
cd "$PROJECT_DIR" && CUR=$(grep -m1 "CURRENT_PROJECT_VERSION = " SpeedRead.xcodeproj/project.pbxproj | grep -oE "[0-9]+") \
  && NEXT=$((CUR+1)) && sed -i '' "s/CURRENT_PROJECT_VERSION = $CUR;/CURRENT_PROJECT_VERSION = $NEXT;/g" SpeedRead.xcodeproj/project.pbxproj
```

3. **Clean & archive** with explicit iOS destination:
```bash
cd "$PROJECT_DIR" && rm -rf build/ && xcodebuild archive \
  -project SpeedRead.xcodeproj \
  -scheme SpeedRead \
  -configuration Release \
  -archivePath build/SpeedRead.xcarchive \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8" \
  -authenticationKeyID <ASC_KEY_ID> \
  -authenticationKeyIssuerID "<ASC_ISSUER_ID>" \
  2>&1 | tail -5
```

4. **Inject `ApplicationProperties` into the archive Info.plist.** Xcode 26 + this project's multi-platform `SUPPORTED_PLATFORMS` config (iOS + macOS + visionOS) skips writing this key, which causes every iOS distribution method to reject the archive. Without this step, all uploads fail with `Validation failed n/a`:
```bash
cd "$PROJECT_DIR/build/SpeedRead.xcarchive" && APP=Products/Applications/SpeedRead.app \
  && SHORT=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist") \
  && BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist") \
  && BID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist") \
  && SIGNER=$(codesign -dvv "$APP" 2>&1 | grep "^Authority=" | head -1 | sed 's/Authority=//') \
  && plutil -insert ApplicationProperties -xml \
    "<dict><key>ApplicationPath</key><string>Applications/SpeedRead.app</string><key>Architectures</key><array><string>arm64</string></array><key>CFBundleIdentifier</key><string>$BID</string><key>CFBundleShortVersionString</key><string>$SHORT</string><key>CFBundleVersion</key><string>$BUILD</string><key>SigningIdentity</key><string>$SIGNER</string><key>Team</key><string>3LTL47SJ8C</string></dict>" Info.plist
```

5. **Remove duplicate watch-app from archive.** The scheme produces both an embedded watch app (inside `SpeedRead.app/Watch/`) AND a top-level standalone watch app in `Products/Applications/`. The standalone one ends up at the root of the .ipa Payload and causes silent App Store Connect 409 validation errors. Delete it before export:
```bash
rm -rf "$PROJECT_DIR/build/SpeedRead.xcarchive/Products/Applications/SpeedReadWatch Watch App.app"
```

6. **Export locally** (no upload — gives a clean `.ipa` that altool can ship):
```bash
cat > "$PROJECT_DIR/build/ExportOptions-local.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>app-store</string>
    <key>destination</key><string>export</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>3LTL47SJ8C</string>
    <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
cd "$PROJECT_DIR" && xcodebuild -exportArchive \
  -archivePath build/SpeedRead.xcarchive \
  -exportOptionsPlist build/ExportOptions-local.plist \
  -exportPath build/export-local \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8" \
  -authenticationKeyID <ASC_KEY_ID> \
  -authenticationKeyIssuerID "<ASC_ISSUER_ID>" \
  2>&1 | tail -3
```

7. **Upload via altool** (more useful error messages than `xcodebuild -exportArchive destination=upload`):
```bash
xcrun altool --upload-app \
  -f "$PROJECT_DIR/build/export-local/SpeedRead.ipa" \
  -t ios \
  --apiKey <ASC_KEY_ID> \
  --apiIssuer "<ASC_ISSUER_ID>" 2>&1 | tail -10
```
Look for `UPLOAD SUCCEEDED with no errors`. The build appears in App Store Connect's TestFlight tab within 5–15 minutes.

## Known gotchas (in order of likelihood)

- **Validation failed (409) "n/a"** — opaque from Apple. Almost always one of:
  1. Top-level duplicate watch-app in the .ipa (step 5)
  2. Missing `ApplicationProperties` in the xcarchive Info.plist (step 4)
  3. `MARKETING_VERSION` already in `READY_FOR_SALE` and no new App Store version created (step 2)
- **`method "app-store-connect"` rejected** — the plist parser wants `app-store`. The "Command line name app-store is deprecated, use app-store-connect" warning is misleading; `app-store-connect` actually fails to load.
- **`xcodebuild -exportArchive ... destination=upload` returns 409 with no diagnostic** — always prefer the two-step local-export + `altool` upload (steps 6–7); altool surfaces real error messages.
- Do NOT commit the `.p8` key file or `~/.appstoreconnect/` contents.

## Variables
- `PROJECT_DIR` = `<PROJECT_DIR>` (the SpeedRead xcodeproj root)

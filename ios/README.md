# ZZUPocket iOS (iOS 17+)

Native SwiftUI client, separate from the Android app. Current scope: CAS login (including SMS MFA), undergraduate semester schedule, campus card balance, and electricity lookup by full room ID. Graduate schedule, library, focus timer, transaction history, room picker and widgets are **not** implemented. No account data is embedded in the build.

## Build

On macOS with Xcode 16.4 and XcodeGen:

```sh
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/ZZUPocket.xcodeproj -scheme ZZUPocket -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /tmp/ZZUPocketBuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p /tmp/ZZUPocketPayload/Payload
cp -R /tmp/ZZUPocketBuild/Build/Products/Release-iphoneos/ZZUPocket.app /tmp/ZZUPocketPayload/Payload/
(cd /tmp/ZZUPocketPayload && zip -r ZZUPocket-iOS-unsigned.ipa Payload)
```

Or run **Actions > iOS unsigned IPA > Run workflow** and download the `ZZUPocket-iOS-unsigned` artifact. No signing certificate, Apple account, GitHub secret or provisioning profile is needed to **build**. The workflow does not publish a Release; artifacts are available from the workflow run. GitHub Actions must be enabled in the repository.

The IPA is **unsigned**: standard iOS installation will reject it. TrollStore installation only works on device/iOS versions actually supported by TrollStore; an iOS 17 deployment target does **not** imply that TrollStore supports every iOS 17.x version. Verify your specific device and version before installing. This build has not been tested on a physical iPhone.

Authentication tokens live in Keychain and are removed on logout. The password is not stored. Room ID is stored in UserDefaults. School API contracts may change; verify login and data requests on device. This is an unofficial client.

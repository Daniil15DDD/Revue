# iOS: one-time Xcode setup for the Share button

The Flutter app runs on iOS without extra setup. You only need these steps for the
**"Revue" icon in the iOS share sheet** (Share → Revue from YouTube, Safari or Photos).
iOS share extensions are separate Xcode targets, and they can't be added from Flutter.

The extension's files are already written in `ios/ShareExtension/`.

1. `open ios/Runner.xcworkspace`
2. **File → New → Target → Share Extension.** Name it `ShareExtension`, uncheck
   "Activate scheme", and set its deployment target to **iOS 16.0**.
3. Xcode creates its own `ShareExtension` folder. Delete the files Xcode generated
   (ShareViewController.swift, MainInterface.storyboard, Info.plist) and add the three
   files from `ios/ShareExtension/` to the target instead.
   In the target's Build Settings, set **Info.plist File** = `ShareExtension/Info.plist`
   and **Code Signing Entitlements** = `ShareExtension/ShareExtension.entitlements`.
4. On the **Runner** target, set **Code Signing Entitlements** = `Runner/Runner.entitlements`.
5. On **both** targets, go to Signing & Capabilities → **+ App Groups** → `group.app.revue.revue`.
   If you use your own ID, change it in both `.entitlements` files and in `AppGroupId` in both `Info.plist` files.
6. Set the extension's bundle ID to `app.revue.revue.ShareExtension`.
7. Run `flutter build ios` once, which generates `ios/Podfile`. Then edit `ios/Podfile`:
   set `platform :ios, '16.0'`, change `use_frameworks!` to `use_frameworks! :linkage => :static`,
   and add a nested target inside `target 'Runner' do … end`:
   ```ruby
   target 'ShareExtension' do
     inherit! :search_paths
   end
   ```
   Then run `cd ios && pod install`.
8. In Runner → Build Phases, drag **Embed Foundation Extensions** above **Thin Binary**.
9. `flutter run` on your iPhone. Open YouTube → Share → More → enable **Revue**.

The extension saves the shared item to the App Group and opens Revue.
Revue then fetches the title and thumbnail.

The memory entitlements in `Runner.entitlements` let the on-device LLM use more RAM.
A free Apple developer account can't sign them. If signing fails, delete those two keys.
The 0.5B model still runs without them.

USB tethering from an Android phone to a Mac, controlled from the menu bar. Tetherline runs the unmodified [muta](https://github.com/jost-s/macos-usb-tether-android) engine (MIT) as a background service: no kernel extensions, no drivers.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon or Intel, an Android phone with USB tethering and a USB data cable. The interface is in English and Polish.

## Install

1. Download **Tetherline-….dmg** below, open it and drag **Tetherline** to **Applications**. The app works only from Applications.
2. Open Tetherline. The app is not signed with an Apple Developer ID or notarized, so macOS blocks the first launch: click **Done**, open **System Settings → Privacy & Security**, scroll to *"Tetherline" was blocked…* and click **Open Anyway**. Alternatively, run once in Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Tetherline.app
   ```
3. Click the menu bar icon and choose **Enable tethering**. macOS asks for an administrator password once, to install the background service. If Tetherline reports that the background item needs approval, allow it in **System Settings → General → Login Items**.
4. Connect the phone with USB and turn on **USB tethering** on Android.

After that, **Enable tethering**, **Turn off** and **Quit** need no password. The service starts at boot only if it was left on. The password is asked again only after an update that changes the background service.

## What gets installed

- `/Library/Application Support/Tetherline`: a copy of the muta engine and a small helper, both owned by root. The helper accepts only start and stop, and only from your account.
- `/Library/LaunchDaemons/pl.tetherline.muta.plist` and `pl.tetherline.control.plist`: the engine and its helper.
- `/Library/Logs/Tetherline`: logs.

**Settings → Uninstall…** removes all of it, then move the app to the Trash.

## Verify the download

```sh
shasum -a 256 -c Tetherline-*.dmg.sha256
```

Tested on Apple Silicon. The Intel build is compiled from the same source but has not been tested on an Intel Mac.

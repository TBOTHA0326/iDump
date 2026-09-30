# iDump

Native **macOS** (SwiftUI) and **Windows** (WPF) apps for getting photos, screenshots and videos off your iPhone over USB, so you can free up space without paying for iCloud.

- Browse everything on the phone, filtered by **All / Photos / Screenshots / Videos**
- Thumbnails, file sizes, video durations, Live Photo badges
- Filter by size (1 MB → 1 GB+) and sort largest-first to find what's eating your storage
- Preview photos and play videos in the inspector
- **Copy** or **Move** selected items to any folder or external drive. Move only deletes an item from the iPhone after its copy is written and its size matches the original.

## Build & run (macOS)

Requires macOS 14+ and Xcode (or the Swift toolchain).

```sh
./scripts/build.sh      # produces build/iDump.app
open build/iDump.app
```

For development: `swift run`.

## Build & run (Windows)

The Windows app lives in [`windows/`](windows/). It uses .NET 10 and WPF, with the [MediaDevices](https://github.com/Bassman2/MediaDevices) library for Windows Portable Devices access and [WPF-UI](https://github.com/lepoco/wpfui) for the Windows 11 look.

```powershell
windows\build.ps1        # on Windows → windows\dist\iDump.exe
```
```sh
windows/build.sh         # cross-build the same .exe from macOS/Linux
```

The `.exe` is self-contained, so the PC doesn't need .NET installed. Windows needs the Apple Devices app (from the Microsoft Store) or iTunes installed, so it has the iPhone USB driver.

On the iPhone, set **Settings › Photos › Transfer to Mac or PC** to **Keep Originals**. Otherwise iOS converts files to JPG/H.264 during the copy, the sizes won't match, and iDump won't delete anything.

## Using it

1. Plug the iPhone in with a cable, unlock it, and tap **Trust** when asked.
2. Pick a category, set a size filter, and select items (⌘/Ctrl-click, ⇧-click for a range, ⌘A/Ctrl+A for everything).
3. Click **Move to Drive…**, choose a folder on your hard drive, and go.

Exports are sorted into `Photos/`, `Screenshots/` and `Videos/` subfolders, with the original capture date set on each file.

## Notes

- **iCloud Photos must be off** on the iPhone for deletion to work. With it on, iOS blocks deletes from a computer, and iDump shows a banner.
- Screenshots are detected as PNGs, or images at an exact iPhone screen resolution. The phone doesn't label them over USB.
- A Live Photo's still and movie are treated as one item and always copied/deleted together.
- Files deleted over USB may not go to the iPhone's *Recently Deleted* album.

`scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

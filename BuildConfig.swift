import Foundation
import Darwin

// Resolve only during build; runtime uses this path in the signed bundle.
guard CommandLine.arguments.count == 3, CommandLine.arguments[1].hasPrefix("/") else { exit(64) }
let path = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
var st = stat()
guard lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_mode & 0o022 == 0,
      st.st_uid == getuid() || st.st_uid == 0, access(path, X_OK) == 0 else { exit(65) }
let info: [String: Any] = ["CFBundleIdentifier": "page.juns.AndroidUnlockHelper",
    "CFBundleName": "AndroidUnlockHelper", "CFBundleExecutable": "android-unlock",
    "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSUIElement": true,
    "AndroidUnlockADBPath": path]
do {
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch { exit(74) }

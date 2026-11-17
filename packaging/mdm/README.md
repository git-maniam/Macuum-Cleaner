# Full Disk Access profile for managed Macs

`MacuumCleaner-FullDiskAccess.mobileconfig` is a Privacy Preferences Policy Control (PPPC) profile that pre-approves
**Full Disk Access** (`SystemPolicyAllFiles`) for Macuum Cleaner (`com.macuum.cleaner`, Developer ID team `XU8XWLY8Q9`).

macOS only honors this when the profile is delivered by **MDM** (Jamf, Kandji, Mosyle, Intune, …) to a supervised or
enrolled Mac. Double-clicking it on an unmanaged Mac will not grant access: users there enable the permission in
System Settings → Privacy & Security → Full Disk Access (the app guides them on first launch).

The code requirement is bound to the signed app. It must be regenerated if the signing identity changes:
`codesign -d -r- "/Applications/Macuum Cleaner.app"`.

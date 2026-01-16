# Sensitive Content Warning

iOS Feature: Settings → Privacy & Security → Sensitive Content Warning

What it does
- Enables Apple’s on-device models to help detect sensitive content.
- Third-party apps using the SensitiveContentAnalysis framework benefit when this system feature is enabled.

NudeFndr behavior
- The app surfaces whether the system feature appears available and guides users to enable it if needed.
- No data leaves the device. There is no network activity.

How we check availability (transparency code)
- If SCSensitivityAnalyzer() returns nil, we treat the analyzer as unavailable (OS unsupported or feature disabled/restricted).

How to enable
- Open Settings
- Go to Privacy & Security
- Tap Sensitive Content Warning
- Turn it On

Troubleshooting
- If the feature still appears unavailable, ensure you are on iOS 17+ and that no device restrictions or profiles disable it.
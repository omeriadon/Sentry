<img width="500" height="500" alt="Sentry-iOS-Dark-1024x1024@1x" src="https://github.com/user-attachments/assets/75a7d43e-36c2-4e33-a084-fe44cb3457ca" />

<br>
<br>

Demo:
https://github.com/user-attachments/assets/a74916db-7d82-4a71-a995-e3bcd303d62e

<br>

# Sentry

Website: https://sss.destinyorg.com.au

Running this app on macOS or iPad is preferred.

## Build and run (no coding required)

Single SDK for iOS, iPadOS, and macOS (designed for iPad).

### Requirements
- A Mac
- Xcode
- An Apple ID (free) to sign the app on devices

### 1) Install Xcode
- Open the Mac App Store, search “Xcode”, install
- After install, open Xcode once so it finishes setup
- In Xcode: Settings > Accounts > Sign In… and add your Apple ID

### 2) Get the app files
- Go to the repository page
- Click the green “Code” button > “Download ZIP”
- Double‑click the ZIP to unzip. You’ll get a folder named “Sentry”

### 3) Open the project in Xcode
- In Xcode: File > Open…
- Select the unzipped “Sentry” folder and click Open
- Wait for Xcode to finish indexing

### 4) Set up app signing (one time)
- In the left Project Navigator, click the blue “Sentry” project
- Select the “Sentry” app target
- Go to “Signing & Capabilities”
- Check “Automatically manage signing”
- Set “Team” to your Apple ID (Personal Team)
- If Xcode shows a bundle identifier error, append a unique suffix to the Bundle Identifier (example: add “.local” to the end)

### 5) Run on macOS (preferred)
- At the top toolbar, open the destination menu
- Choose “My Mac (Designed for iPad)” or “My Mac” if shown
- Click the Run button (▶). The app will build and launch on your Mac

### 6) Run on iPad or iPhone (optional)
- Connect your device with a USB cable and unlock it
- On the device, tap “Trust This Computer” if prompted
- In Xcode, choose your device from the destination menu
- Click Run (▶)
- First run only: on the device, go to Settings > General > VPN & Device Management, trust the developer profile if prompted, then launch the app again

### 7) Run in the Simulator (optional)
- In the destination menu, pick an iPad (recommended) or iPhone simulator
- Click Run (▶)

## Troubleshooting
- Signing error “No signing certificate/Team”: set Team to your Apple ID under Signing & Capabilities and keep “Automatically manage signing” enabled
- Bundle identifier already in use: make the Bundle Identifier unique by adding a suffix (e.g., “com.example.sentry.local”)
- Missing developer tools: open Xcode once and accept any prompts; allow additional components to install
- No Mac destination visible: update Xcode to the latest version; reopen the project
- Device run blocked: on the device, trust the developer in Settings > General > VPN & Device Management

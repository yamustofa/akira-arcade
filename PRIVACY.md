# Akira Arcade privacy

Akira Arcade has no accounts, no analytics and no servers of its own. Nothing about you or your games is sent to Akira.

## The phone controller

- The iPad runs a small web server on your local Wi-Fi (port 8765). Phones that scan its QR code load the pad from the iPad and send button presses back to it. This traffic stays on your network.
- A random link token, kept on the iPad, stops other devices on the same Wi-Fi from joining. **New Link** on the Phone Controller screen replaces it.
- The Wi-Fi name and password you type for the "Join Wi-Fi" QR code stay on the iPad: the name in the app's settings, the password in the Keychain. They are only shown as a QR code on your screen.
- iPadOS asks for **Local Network** permission the first time; without it, phones can't connect.

## Features that come from Delta

Akira Arcade keeps Delta's other features. They only talk to outside services when you use them:

- **Sync** stores your saves in your own Dropbox or Google Drive account.
- **RetroAchievements** sends your progress to retroachievements.org after you sign in there.
- **Game artwork** may be downloaded from the internet when you look up artwork.
- **Online multiplayer** (Nintendo DS Wi-Fi) connects to the servers you choose.

Those services have their own privacy policies.

## Contact

Questions or problems: [open an issue](https://github.com/yamustofa/akira-arcade/issues).

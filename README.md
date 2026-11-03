# Akira Arcade

> A fork of [Delta](https://github.com/rileytestut/Delta) by Riley Testut, made for **Akira**: a retro-computer dock for the iPad.

Akira Arcade adds one thing to Delta: **phones on the same Wi-Fi become game controllers for the iPad**. Scan a QR code on the iPad and the phone's browser turns into a gamepad, with no app to install. It is a community project, built for fun. All credit for the emulator itself goes to Delta and its cores.

- **Status:** the phone controller works for NES, SNES, Game Boy / Color / Advance, DS, Mega Drive and N64 (thumb stick and C buttons included), with up to 4 phones.
- **License:** AGPLv3, like Delta. If you share a build, share its source too.
- **Games:** Akira Arcade ships no games. Load your own. For a quick, legal test, try MIT-licensed homebrew such as [Lunar Limit](https://github.com/retrobrews/nes-games).

## Play with phones

1. Start a game on the iPad, open the pause menu and tap **Phone Controller**.
2. Phone not on the iPad's Wi-Fi yet? Type the Wi-Fi password once on the iPad and the phone scans the **Join Wi-Fi** QR code. The password stays in the iPad's Keychain.
3. Each phone scans **Open the pad**. Its browser shows a pad styled after the console being played, and it changes when the iPad switches to a game on another console.
4. Hold the phone sideways. For full screen on iPhone, add the page to the Home Screen and open it from there (or aA → Hide Toolbar); Android goes full screen on the first touch.

Up to 4 phones can play. The link keeps working, so a phone that saved it to its Home Screen can rejoin later; **New Link** on the iPad replaces it and disconnects everyone. Phones and iPad talk only over the local network: no accounts, no internet, nothing leaves the room.

How it works: [`Delta/Phone Controller/`](Delta/Phone%20Controller/) (the server on the iPad and the pad page) and `PhoneGameController` in the DeltaCore fork. Manual test steps: [`docs/akira/phone-controller-test.md`](docs/akira/phone-controller-test.md).

## Build it with a free Apple ID

1. Install Xcode and sign in to your Apple ID in Xcode → Settings → Accounts.
2. Install Git LFS: `brew install git-lfs && git lfs install`. The cores keep their controller skins in LFS, and without it their folders stay empty.
3. Clone with submodules: `git clone --recursive https://github.com/yamustofa/akira-arcade.git`
4. Copy `Akira.local.xcconfig.example` to `Akira.local.xcconfig` and set `DEVELOPMENT_TEAM` to your Team ID. Change `AKIRA_BUNDLE_ID` there too if `com.yamustofa.akiraarcade` is taken on your account.
5. Run `Scripts/akira-sign-submodules.sh`. Some cores pin Delta's own team, and this points them at yours, locally only.
6. Open `Delta.xcworkspace`, pick your iPad as the destination (not "Any iOS Device"), and press Run.
7. On the iPad, trust the developer: Settings → General → VPN & Device Management.

Apps installed with a free Apple ID expire after 7 days; press Run again to renew. Your games and saves stay.

Don't pick a team in Xcode's Signing & Capabilities tab: it writes the team into the project file, which shows up as a git change. If it happens, discard that change.

---

# Delta (upstream README)

> Delta is an all-in-one classic video game emulator for non-jailbroken iOS devices. 

[![Swift Version](https://img.shields.io/badge/swift-5.0-orange.svg)](https://swift.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

Delta is an iOS application that allows you to emulate and play video games for several classic video game systems, including Game Boy Advance, Nintendo 64, and Nintendo DS. Delta is the spiritual successor to [GBA4iOS](http://www.gba4iosapp.com) — a Game Boy Advance emulator for iOS devices [Paul Thorsen](https://twitter.com/pau1thor) and I made while in high school together — rebuilt from the ground up with modern iOS features and support for more systems.

<p align="center">
  <img src="https://user-images.githubusercontent.com/705880/115471008-203aa480-a1ec-11eb-8aba-237a46799543.png" width=75%><br/>
  <em>Mario and Pokémon are properties of Nintendo Co., Ltd. and are not associated with Delta or AltStore LLC.</em>
</p>

## Supported Systems
- Nintendo Entertainment System (NES)
- Super Nintendo Entertainment System (SNES)
- Nintendo 64 (N64)
- Game Boy / Game Boy Color (GBC)
- Game Boy Advance (GBA)
- Nintendo DS (DS)
- Sega Genesis / Mega Drive (GEN) **(in beta)**

## Features
- Accurate, full speed emulation thanks to mature underlying emulator cores.
    - NES: [Nestopia](https://github.com/0ldsk00l/nestopia)
    - SNES: [Snes9x](https://github.com/snes9xgit/snes9x)
    - N64: [mupen64plus](https://github.com/mupen64plus/mupen64plus-core)
    - GBC: [Gambatte](https://github.com/sinamas/gambatte)
    - GBA: [visualboyadvance-m](https://github.com/visualboyadvance-m/visualboyadvance-m)
    - DS: [melonDS](https://github.com/Arisotura/melonDS)
    - GEN: [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX)
- Beautiful, native UI.
    - Browse and play your favorite games with a UI designed from the ground up for iOS.
    - Automatically displays appropriate box art for imported games.
    - Change a game’s artwork to anything you want, or select from the built-in game artwork database.
- Controller Support
    - Supports PS4, PS5, Xbox One S, Xbox Series X, and MFi game controllers.
    - Supports bluetooth (and wired) keyboards, as well as the Apple Smart Keyboard.
    - Completely customize button mappings on a per-system, per-controller basis.
    - Map buttons to special “Quick Save”, “Quick Load,” and “Fast Forward” actions.
- Custom Controller Skins
    - Beautiful built-in controller skins for all systems.
    - Import controller skins made by others, or even make your own to share with the world!
- Save States
    - Save and load save states for any game from the pause menu.
    - Lock save states to prevent them from being accidentally overwritten.
    - Automatically makes backup save states to ensure you never lose your progress.
    - Support for “Quick Saves,” save states that can be quickly saved/loaded with a single button press (requires external controller).
- Fast Forwarding
    - Speed through slower parts of games by running the game much faster than normal.
    - Easily enable or disable from the pause menu, or optionally with a mapped button on an external controller.
- Delta Sync
    - Sync your games, game saves, save states, cheats, controller skins, and controller mappings between devices.
    - View version histories of everything you sync and optionally restore them to earlier versions.
    - Supports both Google Drive and Dropbox.
- Hold Button
    - Choose buttons for Delta to hold down on your behalf, freeing up your thumbs to press other buttons instead.
    - Perfect for games that typically require one button be held down constantly (ex: run button in Mario games, or the A button in Mario Kart).
- 3D/Haptic Touch
    - Use 3D or Haptic Touch to “peek” at games, save states, and cheat codes.
    - App icon shortcuts allow quick access to your most recently played games, or optionally customize the shortcuts to always include certain games.
- Cheat Codes
    - NES
        - Game Genie
    - SNES: 
        - Game Genie
        - Pro Action Replay
    - N64
        - GameShark
    - GBC
        - Game Genie
        - GameShark
    - GBA
        - Action Replay
        - Code Breaker
        - GameShark
    - DS
        - Action Replay
- Gyroscope support  **(WarioWare: Twisted! only)**
- Microphone support **(DS only)**

## Installation

<p align="center">
  <img src="https://user-images.githubusercontent.com/705880/114452847-c1db4980-9b8d-11eb-8f8f-de7998562222.png" width=100px height=100px>
</p>

Delta was originally developed under the impression Apple would allow it into the App Store. Unfortunately Apple later changed their minds, leaving me no choice but to find a new way to distribute Delta. Long story short, this led me to create [AltStore](https://github.com/rileytestut/AltStore), which now serves as the official way to install Delta onto your device.

To install Delta with AltStore:
1. Download AltServer for Mac or PC from https://altstore.io
2. Connect your iOS device to your computer via lightning cable (or USB-C for iPads).
3. [Follow these instructions](https://altstore.io/faq/) to install AltStore onto your device with AltServer.
2. Open AltStore on your device, then navigate to the "Browse" tab.
3. Find Delta, then press the `FREE` button to start installing the app.

Once you've installed Delta with AltStore, **you'll need to refresh it at least once every 7 days to prevent it from expiring** and requiring a re-installation. AltStore will periodically attempt to refresh your apps in the background when on the same WiFi as AltServer, but you can also manually refresh apps by pressing "Refresh All" in AltStore. AltStore will also let you know whenever a new update is released, allowing you to update Delta directly within AltStore.

Alternatively, you are welcome to download the compiled `.ipa`'s from [Releases](https://github.com/rileytestut/Delta/releases) and sideload them using whatever sideloading method you prefer, but you will not receive automatic updates and will have to manually update Delta by re-sideloading each new version.

## Project Overview

Delta was designed from the beginning to be modular, and for that reason each "Delta Core" has its own GitHub repo and is added as a submodule to the main Delta project. Additionally, Delta uses two of my own private frameworks I use to share common functionality between my apps: Roxas and Harmony.

[**Delta**](https://github.com/rileytestut/Delta)  
Delta is just a regular, sandboxed iOS application. The Delta app repo (aka this one) contains all the code specific to the Delta app itself, such as storyboards, app-specific view controllers, database logic, etc.

[**DeltaCore**](https://github.com/rileytestut/DeltaCore)  
DeltaCore serves as the “middle-man” between the high-level app code and the specific emulation cores. By working with this framework, you have access to all the core Delta features, such as emulation, controller skins, save states, cheat codes, etc. Other potential emulator apps will use this framework extensively.

[**Roxas**](https://github.com/rileytestut/Roxas)    
Roxas is my own framework used across my projects, developed to simplify a variety of common tasks used in iOS development.

[**Harmony**](https://github.com/rileytestut/Harmony)   
Harmony is my personal syncing framework designed to sync Core Data databases. Harmony listens for changes to an app's persistent store, then syncs any changes with a remote file service (such as Google Drive or Dropbox).

**Delta Cores**  
Each system in Delta is implemented as its own "Delta Core", which serves as a standard emulation API Delta can understand regardless of the underlying core. For the most part, you don't interact directly with specific Delta Cores, but rather indirectly through `DeltaCore`.
- [NESDeltaCore](https://github.com/rileytestut/NESDeltaCore)
- [SNESDeltaCore](https://github.com/rileytestut/SNESDeltaCore)
- [N64DeltaCore](https://github.com/rileytestut/N64DeltaCore)
- [GBCDeltaCore](https://github.com/rileytestut/GBCDeltaCore)
- [GBADeltaCore](https://github.com/rileytestut/GBADeltaCore)
- [MelonDSDeltaCore](https://github.com/rileytestut/MelonDSDeltaCore)
- [GPGXDeltaCore](https://github.com/rileytestut/GPGXDeltaCore)

## Minimum Project Requirements
- Xcode 15
- Swift 5.9
- iOS 14.0

## Compilation Instructions

> Delta uses Git LFS to manage large files, so first make sure you have [installed Git LFS](https://git-lfs.github.com).

1. Clone this repository by running the following command in Terminal*  
```bash
$ git clone https://github.com/rileytestut/Delta.git
```  

2. Update Git submodules
```bash
$ cd Delta
$ git submodule update --init --recursive
```  

3. Open `Systems/Systems.xcworkspace` and select the "Systems" project in the project navigator (a.k.a. the left sidebar).
4. Select "Systems" under `Targets`, then click the `Signing & Capabilities` tab.
5. Change `Team` from "Yvette Testut" to your own account.
6. Close `Systems/Systems.xcworkspace`, then open `Delta.xcworkspace`.
6. Repeat steps 4 & 5 with the "Delta" target.
7. Change Delta's `Bundle Identifier` to something unique, such as by appending your GitHub username (ex: `com.rileytestut.Delta.MyGitHubUsername`).
8. Build + run app! 🎉

## Licensing
The Delta codebase is distributed under the **AGPLv3 license**.

## Contact Us

* Email: delta@altstore.io
* Mastodon: [@mattaltgear@mstdn.social](https://mstdn.social/mattaltgear)
* Threads: [@mattaltgear](https://www.threads.com/@mattaltgear)
* Bluesky: [@mattaltgear.bsky.social](https://bsky.app/profile/mattaltgear.bsky.social)

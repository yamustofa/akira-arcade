# Phone controller: manual test

The pad page has an automated test (`node Scripts/test-phone-controller-page.js`, see the file for setup).
Everything below needs a real iPad and phones, so a person runs it. Write the date, the build and the result
next to each step when you do.

## Setup

- iPad with the Debug build installed from Xcode, and at least two phones (one iPhone, one Android if you have one).
- A game you own for each console you test, or MIT-licensed homebrew such as Lunar Limit (NES).

## Join

1. Start a game, open the pause menu, tap **Phone Controller**. Allow Local Network if iPadOS asks.
2. Phone on another network: type the Wi-Fi name and password on the iPad, scan **Join Wi-Fi** with the phone camera. The phone joins the Wi-Fi.
3. Scan **Open the pad**. The page shows "P1 · Connected" in the console's colours; the iPad lists "Phone 1 · Player 1".
4. A second phone joins as P2. With 4 phones joined, a fifth sees "All 4 places are taken".
5. Tap **New Link** on the iPad: every phone shows "This link has expired". Scanning the new code works.

## Play

6. NES: D-pad and A/B move and jump with no noticeable lag; holding a direction for 10 s keeps moving.
7. SNES or GBA: L and R are easy to hit without looking, and holding R while steering works (a kart game).
8. Mega Drive: the A/B/C buttons do what the game's A/B/C do.
9. N64: the thumb stick moves smoothly (small tilt walks, full tilt runs), the C buttons move the camera, Z works while the stick is held.
10. Switch to a game on another console: the phone's pad changes within a second, and nothing stays pressed.
11. Menu button (☰) on the phone opens Delta's pause menu.

## Recovery

12. Lock the phone while holding a button or the stick: the game releases it within about a second.
13. Turn the iPad's Wi-Fi off and on: the phone reconnects by itself.
14. iPhone: add the page to the Home Screen, open it from the icon. It runs full screen and rejoins without scanning.

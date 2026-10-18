# 5Stones

A Pente-style strategy game for **Mac**, **Windows** and **iPhone**, built with [Flutter](https://flutter.dev) from one codebase.

## Features

- Two players on one device, or play the computer at **Easy**, **Medium** or **Hard**.
- Choose whether you or the computer goes first.
- Capture counters, last-move marker, winning-line highlight and undo.
- Optional tournament rule.
- Works with mouse (with a hover preview) and touch.

## Rules (classic Pente)

- Players take turns placing stones on the intersections of a 19×19 board. White moves first, in the center.
- Moving into a spot where your stones would look captured is safe. Only the player who closes the trap captures.
- **Capture:** surround exactly two of your opponent's stones in a line (`X O O X`) and they are removed.
- **Win** by getting five (or more) of your stones in a row, or by capturing five pairs.
- **Tournament rule (optional):** White's second stone must be at least three points from the center.

## Running it

1. [Install Flutter](https://docs.flutter.dev/get-started/install) (stable channel).
2. From this folder:

   ```sh
   flutter pub get
   flutter run -d macos     # or: -d windows, or an iPhone/simulator
   ```

`flutter test` runs the tests.

## Code layout

- `lib/game/pente.dart`: the rules (board, captures, wins, undo).
- `lib/game/ai.dart`: the computer player (look-ahead search with a scoring function).
- `lib/game/game_controller.dart`: runs a game and the computer's turns.
- `lib/widgets/board_view.dart`: draws the board and handles taps and clicks.
- `lib/screens/`: the home and game screens.

## Downloads

Every push to `main` builds the apps and publishes them to the **[Latest build](https://github.com/nusbaumm01/5stones/releases/tag/latest)** release:

- **Mac:** download `5Stones-macos.zip`, unzip it and move `5Stones.app` to Applications. The app isn't signed yet, so the first time you open it macOS says it "could not verify" 5Stones. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the 5Stones message, and confirm. You only need to do this once. (Or run `xattr -dr com.apple.quarantine /Applications/5Stones.app` in Terminal.)
- **Windows:** download `5Stones-windows.zip`, unzip the whole folder and run `five_stones.exe`. If SmartScreen warns you, click **More info**, then **Run anyway**.
- **iPhone:** the build is checked on every push. Installing it on a real iPhone requires signing with an Apple Developer account.


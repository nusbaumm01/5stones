# 5Stones

A Pente-style strategy game for **Mac**, **Windows** and **iPhone**, built with [Flutter](https://flutter.dev) from one codebase.

## Features

- Two players on one device, or play the computer at **Easy**, **Medium** or **Hard**.
- **Play online** against a friend on another device: create a game, send the 6-character code, and they join. Mac, Windows, iPhone and iPad can all play each other. Needs a one-time Firebase setup: see [docs/ONLINE_SETUP.md](docs/ONLINE_SETUP.md).
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
- `lib/screens/`: the home, game and online screens.
- `lib/online/`: online play over Firebase (sign-in, game codes, sending and receiving moves).
- `firebase/database.rules.json`: the server rules that keep online games fair.

## Downloads

Every push to `main` builds the apps and publishes them to the **[Latest build](https://github.com/nusbaumm01/5stones/releases/tag/latest)** release:

- **Mac:** download `5Stones.dmg`, open it and drag **5Stones** onto the **Applications** folder. The app isn't signed yet, so the first time you open it macOS says it "could not verify" 5Stones. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the 5Stones message, and confirm. You only need to do this once. (Or run `xattr -dr com.apple.quarantine /Applications/5Stones.app` in Terminal.) A plain `5Stones-macos.zip` is also available.
- **Windows:** download `5Stones-windows.zip`, unzip the whole folder and run `five_stones.exe`. If SmartScreen warns you, click **More info**, then **Run anyway**.
- **iPhone and iPad:** every push to `main` uploads a build to TestFlight (once the Apple secrets below are set). Install the **TestFlight** app on your device and open 5Stones from there.

### TestFlight setup (one time)

Add these repository secrets under **Settings → Secrets and variables → Actions**:

- `APPLE_TEAM_ID`: your 10-character Team ID (developer.apple.com → Account → Membership details).
- `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID`: from an App Store Connect API key with the **Admin** role (App Store Connect → Users and Access → Integrations → App Store Connect API).
- `APP_STORE_CONNECT_KEY`: the full text of that key's downloaded `.p8` file.

The app record must exist in App Store Connect with bundle ID `com.nusbaumm01.fiveStones`.


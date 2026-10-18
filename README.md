# 5Stones

A Pente-style strategy game for **Mac**, **Windows** and **iPhone**, built with [Flutter](https://flutter.dev) from one codebase.

Play two players on one device, or against the computer.

## Rules (classic Pente)

- Players take turns placing stones on the intersections of a 19×19 board. White moves first, in the center.
- **Capture:** surround exactly two of your opponent's stones in a line (`X O O X`) and they are removed.
- **Win** by getting five (or more) of your stones in a row, or by capturing five pairs.

## Running it

1. [Install Flutter](https://docs.flutter.dev/get-started/install) (stable channel).
2. From this folder:

   ```sh
   flutter pub get
   flutter run -d macos     # or: -d windows, or an iPhone/simulator
   ```

`flutter test` runs the tests.

## Downloads

Every push to `main` builds the Mac and Windows apps on GitHub Actions. Open the latest **CI** run under the repo's **Actions** tab and download them from its **Artifacts** section.

The iPhone build is checked on every push. Installing it on a real iPhone requires signing with an Apple Developer account.

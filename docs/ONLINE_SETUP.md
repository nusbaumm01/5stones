# Online play setup (one time, about 10 minutes)

Online games send moves through a free Firebase project. Until it is set up,
the **Play online** button says online play isn't switched on yet. Everything
here is on the free **Spark** plan; no credit card is needed.

## 1. Create the Firebase project

1. Go to <https://console.firebase.google.com> and sign in with a Google account.
2. Click **Create a project** (or **Add project**). Name it `5Stones`.
3. Turn **Google Analytics** off (not needed), then click **Create project**.

## 2. Turn on anonymous sign-in

Players don't make accounts. Each device gets an anonymous player ID so the
server can tell the two players apart and stop cheating.

1. In the left menu, open **Build → Authentication** and click **Get started**.
2. On the **Sign-in method** tab, click **Anonymous**, switch it on, and click **Save**.

## 3. Create the database

1. In the left menu, open **Build → Realtime Database** and click **Create Database**.
2. Pick the location closest to you and click **Next**.
3. Choose **Start in locked mode** and click **Enable**.
4. Open the **Rules** tab. Delete what is there, paste in the whole contents of
   [`firebase/database.rules.json`](../firebase/database.rules.json), and click **Publish**.
5. Go back to the **Data** tab and copy the database address at the top. It looks like
   `https://fivestones-1234-default-rtdb.firebaseio.com` (or ends in `firebasedatabase.app`).

## 4. Find the API key

1. Click the gear icon next to **Project Overview**, then **Project settings**.
2. On the **General** tab, copy the **Web API Key**.
   If it says there is no key yet, scroll down to **Your apps**, click the web icon `</>`,
   name the app `5Stones`, click **Register app**, and copy the `apiKey` value it shows.

This key only identifies the project. It isn't a password; the database rules are
what keep games safe. It is kept as a GitHub secret anyway so it stays out of the code.

## 5. Add two GitHub secrets

In the GitHub repository, open **Settings → Secrets and variables → Actions** and click
**New repository secret** for each:

| Name | Value |
| --- | --- |
| `FIREBASE_DATABASE_URL` | The database address from step 3 |
| `FIREBASE_API_KEY` | The Web API Key from step 4 |

The next build on `main` (Mac, Windows, and TestFlight) has online play switched on.
To rebuild without a code change, open **Actions → CI → Run workflow** on `main`.

## How it works

- **Create game** stores a new game under a 6-character code, like `K7P3QX`.
  Codes skip look-alike characters (0/O, 1/I).
- **Join** with that code. A game takes exactly two players; others are turned away.
- Each move is checked by the database rules: it must be your turn, in order, and on the board.
- After a game, both players tap **Play again** for a rematch with colors swapped.
- Leaving the game screen tells the other player you left.

The free plan allows 100 players connected at once and 1 GB of stored games, which is far
more than this needs.

## Testing locally

The tests in `test/online_emulator_test.dart` run against the Firebase emulator, including
the database rules:

```sh
npx firebase-tools emulators:exec --only auth,database --project demo-5stones \
  "flutter test test/online_emulator_test.dart"
```

To try the app against the emulator, start it with
`npx firebase-tools emulators:start --only auth,database --project demo-5stones`
and run the app with `--dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1`.

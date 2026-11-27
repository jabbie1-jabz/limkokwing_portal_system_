# Limkokwing Campus Portal (Flutter)

This is the native Flutter Android app. Its screens are written in Dart and
communicate with the Flask server through JSON API endpoints. The Flask server
and SQLite database must be running for sign-in and service requests to work.

## Run on a USB-connected Android phone

1. Open the `mobile_app` folder in Android Studio and let Gradle sync.
2. Start the Flask server from the repository root on port `5000`.
3. Enable USB debugging on the Android phone and connect it to the computer.
4. In Android Studio's Terminal, run:

   ```text
   adb reverse tcp:5000 tcp:5000
   ```

5. Select the phone and run the Flutter app.

The default server address is `http://127.0.0.1:5000/`. To use another server,
pass `--dart-define=PORTAL_URL=https://your-server/` when running Flutter.
Debug builds allow HTTP for local USB testing; release builds require HTTPS.

Student accounts must be verified by an administrator before students can
sign in. Administrators can sign in without campus ID or campus code.

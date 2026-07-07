# fishtrack

A new Flutter project.

## Mapbox access token

The Mapbox SDK reads its public access token from the
`MAPBOX_ACCESS_TOKEN` Dart environment value. Do not commit a token to source.
Provide a public token (starting with `pk.`) when running or building:

```powershell
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_public_token
flutter build apk --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_public_token
```

Mapbox is not rendered yet, so omitting the token keeps the existing
OpenStreetMap maps fully functional.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

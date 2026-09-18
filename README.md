# SelfPhotos

SelfPhotos is a native, independent iOS and iPadOS client for [Immich](https://immich.app/). It connects directly to the Immich server you choose, giving you a familiar Apple-platform experience for browsing, organizing, and backing up your photo library.

> [!IMPORTANT]
> SelfPhotos is a community project and is not affiliated with or endorsed by the Immich team. You need access to a running Immich server to use the app.

## Features

- Browse photos and videos in a responsive timeline
- View albums, memories, people, places, favorites, archived items, and trash
- Search your library and filter results
- Inspect and edit supported photo metadata
- Create albums and add photos to them
- Back up selected device albums, including Live Photos
- Monitor sync and backup status, then free up verified device copies
- Find duplicate photos reported by your Immich server
- Sign in with email and password or your server's OAuth/OIDC provider
- Share photos and videos to Immich from the iOS share sheet
- Display selected albums and memories in Home Screen widgets
- Use a dedicated experience in Apple Assistive Access
- Continue browsing cached content during temporary connection failures

## Requirements

- Xcode 26 or newer
- iOS or iPadOS 26 or newer
- An Immich server that is reachable from your device
- An Apple Developer team for signing and device installation

Using HTTPS with a valid certificate is strongly recommended, especially when the server is accessible outside your local network.

## Getting Started

1. Clone this repository:

   ```sh
   git clone https://github.com/rendiwijiatmoko/iOS-SelfPhotos.git
   cd iOS-SelfPhotos
   ```

2. Open `ImmichApp.xcodeproj` in Xcode.
3. Select the **SelfPhotos** scheme.
4. In **Signing & Capabilities**, select your development team for the app and all extensions.
5. If you use your own bundle identifiers, update the App Group identifier in every target and in the related source configuration.
6. Choose an iPhone or iPad running iOS 26 or later, then build and run.
7. Enter your Immich server URL and sign in.

No third-party package installation is required.

## Single Sign-On

SelfPhotos supports Immich's OAuth/OIDC mobile flow when OAuth is enabled on the server. The sign-in button appears automatically when the server reports that OAuth is available.

For identity providers that require an HTTPS redirect, enable Immich's **Mobile Redirect URI Override** and configure:

```text
https://YOUR-IMMICH-DOMAIN/api/oauth/mobile-redirect
```

Add that exact URL to the identity provider's list of allowed redirect URLs. Immich completes the mobile flow through `app.immich:///oauth-callback`.

## Running Tests

Run the test suite from Xcode with **Product → Test**, or from the command line with an available iOS Simulator:

```sh
xcodebuild test \
  -project ImmichApp.xcodeproj \
  -scheme SelfPhotos \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Replace the simulator name with one installed on your Mac. The tests cover networking contracts, authentication, backup behavior, storage, migrations, timelines, albums, and media playback lifecycles.

## Project Structure

```text
ImmichApp/                   Main SwiftUI application
  App/                       App lifecycle and navigation
  Core/                      Networking, storage, caching, and shared services
  Features/                  Feature-focused views, models, and repositories
  Models/                    Domain and API data models
ImmichWidgets/               Home Screen widgets
SelfPhotosShareExtension/    iOS share-sheet extension
SelfPhotosUploadAction/      Photos upload action extension
SharedUpload/                Upload code shared by the extensions
Tests/                       Unit and contract tests
```

## Privacy

SelfPhotos communicates directly with the server URL you configure; the app does not route your library through a developer-operated intermediary server. Authentication tokens are stored in the iOS Keychain, while local indexes and caches stay in the app's sandbox and shared App Group container.

Your Immich server and its administrator have their own data-handling responsibilities. Review that server's privacy, security, retention, and backup practices before connecting. You can revoke photo-library access at any time in iOS Settings.

## Contributing

Issues, bug reports, and pull requests are welcome. Before opening a pull request:

1. Keep changes focused and consistent with the existing SwiftUI architecture.
2. Add or update tests for behavior changes.
3. Run the **SelfPhotos** test suite.
4. Describe the user-visible impact and any Immich API assumptions in the pull request.

When reporting a bug, include the SelfPhotos version, iOS version, Immich server version, reproduction steps, and relevant logs with secrets removed.

## Acknowledgements

SelfPhotos exists thanks to the open-source [Immich](https://github.com/immich-app/immich) project and its community.

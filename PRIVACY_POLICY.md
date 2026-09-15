---
project_id: selfphotos
---

# Privacy Policy — SelfPhotos

**Effective Date: August 24, 2026**

This Privacy Policy explains how SelfPhotos ("SelfPhotos," "the App," "we," or "our") handles information. SelfPhotos is an independent iOS client that connects to an Immich server selected and configured by the user.

The SelfPhotos developer does not operate an intermediary server for the App. Information exchanged with your Immich server is sent directly between your Apple device and the server address you configure. The developer does not receive your photo library, face data, credentials, or Immich account data in developer-controlled systems through the App.

## Important Distinction: Your Immich Server

SelfPhotos communicates directly with the Immich server address you configure. That server may be operated by you, another individual, an organization, or a hosting provider. The server administrator determines how server-side information is processed, secured, logged, stored, retained, deleted, and shared.

This policy covers the App's handling of information on your Apple device and its direct communication with your configured server. It does not govern the independent practices of your Immich server, its administrator, its hosting provider, or the network infrastructure used to reach it. Review those parties' privacy and security practices before connecting.

## Information the App Processes

To provide its features, SelfPhotos may process the following information:

- **Connection and authentication data** — your Immich server address and the access token or API key issued by that server. If you sign in with an email address and password, those credentials are sent directly to the configured server to create a session. If you use single sign-on, the App opens the identity provider configured by your Immich server in a system browser and sends the resulting authorization callback to Immich to create a session. The App stores the resulting Immich access token, not your password or the identity provider's password.
- **Account information** — account ID, display name, email address, profile image reference, and other profile fields returned by your server.
- **Server library data** — photos, videos, thumbnails, albums, People records, memories, shared links, favorites, archive and trash status, descriptions, dates, locations, filenames, EXIF details, and other media or library metadata provided by or submitted to your server.
- **Device photo library data** — photos, videos, Live Photos, album membership, identifiers, filenames, creation and modification dates, dimensions, favorites, and checksums needed to display local media, detect duplicates, upload selected items, save server media, or free device storage.
- **Face-related information** — media that may contain human faces and People information returned by the configured server, as explained in the Face Data and People Features section below.
- **Local sync and backup data** — cached asset metadata, server-to-device matches, upload queue state, checksums, sync cursors, failure records, and backup preferences.
- **App preferences** — appearance, grid size, selected device albums, cache limit, backup settings, cellular-data choices, widget selections, onboarding state, and similar settings.

The App does not access your device's current geographic location. Location information shown or edited in the App comes from media metadata or from a point you choose on the map.

## Face Data and People Features

For purposes of this policy, **face data** means information related to a human face, including an image containing a face and face-related information derived from a photograph.

### Face Data the App Processes

Photos and videos that you select for upload or include in an enabled backup may contain human faces. If facial recognition is enabled on your configured Immich server, that server may analyze uploaded media, group visually similar faces, and create People records.

SelfPhotos may retrieve, display, and locally cache the following face-related information generated or stored by your configured Immich server:

- a server-generated person identifier;
- a user-assigned person name;
- an optional birth date;
- hidden or visible status;
- a face thumbnail; and
- associations between a People record and photos or videos in the server library.

SelfPhotos does not itself perform facial recognition or facial analysis. The App does not access Face ID enrollment data, TrueDepth face data, face meshes, facial landmarks, facial coordinates, face embeddings, or biometric authentication templates. It does not attempt to determine the real-world identity of an unnamed person.

### How Face Data Is Used

SelfPhotos processes face-related information only to provide photo-library functionality requested by the user, including:

- uploading and backing up photos and videos to the configured server;
- displaying People records and face thumbnails returned by that server;
- browsing, searching, or filtering server media by person; and
- allowing the user to rename or hide People records on the configured server.

Face data is not used by SelfPhotos or its developer for authentication, advertising, marketing, cross-app tracking, analytics, data brokerage, model training, or unrelated profiling.

### Face Data Transfer and Sharing

Media selected for upload, including media that may contain faces, is transferred directly from your device to the Immich server address you configure. People records and face thumbnails are retrieved directly from that configured server.

The SelfPhotos developer does not operate an intermediary server and does not receive face data through the App. SelfPhotos does not sell face data or provide it to advertisers, analytics providers, data brokers, information resellers, or other developer-selected third parties.

Your configured Immich server may be operated or hosted by another individual, organization, or hosting provider. If you connect to such a server, its operator or hosting provider may process and store face data under its own privacy and retention practices. SelfPhotos does not select, appoint, or control that operator and cannot guarantee its practices. You should connect only to a server whose operator you trust.

### Face Data Storage

On your device, SelfPhotos may store People records, person identifiers, user-assigned names, face thumbnails, and associations with media inside the App's sandboxed Application Support and cache directories. Temporary media files may also be created while an upload is prepared.

Face data uploaded to or generated by an Immich server is stored on that configured server or its hosting infrastructure. SelfPhotos does not select or control the server's physical storage location.

### Face Data Retention and Deletion

Account-specific People records and local library snapshots may remain on your device until you sign out, uninstall the App, or the information is otherwise removed by iOS. Cached face thumbnails may be removed earlier when the cache limit is reached or when you use the App's cache controls.

Signing out removes the saved session, account-specific People records, related local snapshots, and cached images from SelfPhotos. Clearing only the image cache may remove face thumbnails but does not necessarily remove all account-specific People records; use **Sign Out** to remove the complete account-specific local session and snapshots.

Temporary upload files are removed when they are no longer needed by the upload workflow.

Face data stored on the configured Immich server is retained according to that server's settings and retention policy. SelfPhotos does not impose a fixed server-side retention period. Server-side face data may remain until you or the server administrator deletes the associated media or People data using controls provided by that server.

Signing out of or uninstalling SelfPhotos does not delete data already stored on your Immich server. To request deletion of server-side face data, use the configured server's controls or contact its administrator. The SelfPhotos developer cannot delete information from a server that the developer does not operate or access.

### Your Choices Regarding Face Data

Before SelfPhotos accesses your device photo library, iOS requests your permission through Apple's system interface. Uploads occur only when you select media for upload or enable backup for selected device albums.

You can:

- limit or revoke SelfPhotos access to your Photos library in iOS Settings;
- disable backup in the App to stop future automatic uploads;
- clear cached images using the App's cache controls;
- sign out to remove account-specific local records and cached data; and
- use your Immich server's controls, or contact its administrator, to manage or delete server-side media and face-related information.

Facial recognition and server-side face processing are controlled by the configured Immich server and its administrator, not by SelfPhotos. If you do not want uploaded media analyzed for faces, disable facial recognition on the server where available or contact its administrator before uploading media.

Photos may contain the faces of people other than the account holder. You are responsible for ensuring that you have the necessary rights or authority to upload and process that media on your configured server.

## Photo Library Access

Photo Library access is requested through Apple's system permission dialog. If granted, it is used to:

- show photos and videos from device albums you select;
- compare local items with assets already stored on your Immich server;
- upload selected photos, videos, and Live Photos to that server;
- save downloaded server media to your Photos library; and
- when you explicitly use **Free Up Space** and confirm the system prompt, move eligible device copies to Recently Deleted after verifying that a server copy exists.

You can limit or revoke Photos access at any time in iOS Settings. Features that depend on the photo library may stop working, but you can continue browsing server content where available.

## How Information Is Used

Information is processed only to provide App functionality, including authentication, library browsing, search, backup, duplicate detection, album and asset management, People features, media playback and download, memories, widgets, local notifications, offline caching, and sync status.

We do not use your information for advertising, marketing, unrelated profiling, model training, or cross-app tracking. The App does not contain third-party advertising, analytics, or tracking SDKs.

## Network Transfers and Security

The App sends its API requests, media, and metadata to the Immich server address you configure, except for Apple services described below. If you use single sign-on, the system browser also connects to the identity provider configured by that server; the provider may process your sign-in according to its own privacy policy. Authentication tokens and API keys are stored in the iOS Keychain. Local databases, preferences, temporary upload files, thumbnails, and previews are stored inside the App's sandboxed containers.

The security of data in transit depends on the URL and network you choose. We strongly recommend connecting through a trusted **HTTPS** endpoint with a valid certificate. If you configure a plain HTTP address, traffic is not protected by TLS and may be visible to or modified by other parties on the network.

The App cannot guarantee the security, availability, or behavior of your configured server. You or the server administrator are responsible for its access controls, software updates, backups, TLS configuration, and exposure to the internet.

## Local Storage and Caching

SelfPhotos keeps a local SwiftData index and image caches to make large libraries responsive and usable during temporary connection failures. These may include asset identifiers and metadata, sync and backup records, checksums, thumbnails, previews, profile images, face thumbnails, People records, album covers, and limited library snapshots.

You can clear supported caches and local sync data from the App's settings. Signing out removes the saved session, account-specific local database records, cached images, snapshots, and widget data from the App. Photos on your device and media stored on your server are not deleted simply by clearing the App's cache or signing out.

Temporary multipart files may be created on the device while media is prepared for background upload. They are used only for that upload workflow and are cleaned up when no longer needed.

## Widgets and App Group

To power Album and Memories widgets, the main App writes a limited snapshot to a private App Group shared only with its bundled widget extension. The snapshot may contain album names, asset counts, memory labels, deep-link identifiers, and selected thumbnail images.

The widget extension does not receive or store your Immich password, access token, or API key. Widget content can appear on the Home Screen or in system previews, so choose widget albums with the visibility of those surfaces in mind.

## Background Processing and Notifications

When backup is enabled, iOS may allow the App to scan selected photo-library items, prepare uploads, and communicate with your server while the App is not in the foreground. Background execution timing is controlled by iOS.

SelfPhotos may request permission to send local notifications about backup progress or completion. These notifications are created on your device and are not delivered through a push-notification server operated by us. You can disable them in iOS Settings.

## Apple Services

SelfPhotos uses Apple platform services such as PhotoKit, Keychain, BackgroundTasks, WidgetKit, and local notifications. When you view or edit a media location, MapKit may retrieve map content from Apple. Apple's handling of information is governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).

SelfPhotos does not send People records, face thumbnails, or server-generated face data to Apple for facial recognition or analysis.

## Data Sharing and Sale

The SelfPhotos developer does not receive or sell your personal information through the App. We do not share your information with advertisers, analytics providers, data brokers, or information resellers.

Information is transferred to the Immich server you choose as required to perform your requested actions. It may be processed by that server's operator or hosting provider under their own terms. Information may also be processed by Apple platform services as described above.

## Data Retention, Deletion, and Withdrawal of Access

Local information may remain on your device until it is cleared through the App, you sign out, you uninstall the App, or it is removed by iOS. To remove credentials and account-specific cached data before uninstalling, use **Sign Out** in the App.

You may stop or limit future processing by revoking Photos permission in iOS Settings, disabling backup, clearing supported caches, or signing out. Revoking Photos permission does not delete media already uploaded to your server.

Data already uploaded to your Immich server remains there until it is deleted according to that server's controls and retention policy. Deleting or uninstalling SelfPhotos does not delete server-side media or your server account. Likewise, deleting server content does not automatically delete an original that remains in your device's Photos library.

SelfPhotos does not create, host, or administer Immich accounts. To delete an Immich account or other server-side information, use the configured server's account controls or contact its administrator.

The **Free Up Space** feature moves confirmed device items to Apple's Recently Deleted album. Recovery and permanent deletion then follow the Photos app and iOS behavior.

## Children's Privacy

SelfPhotos is not directed to children under 13. The App developer does not receive account, media, or face data through developer-controlled systems. A library connected to the App may nevertheless contain media depicting children or information relating to them.

Use by a child should be supervised by a parent or guardian and must follow applicable law and the policies of the configured Immich server. The person uploading media is responsible for having the necessary authority to process that media.

## Changes to This Policy

We may update this Privacy Policy when App functionality or privacy practices change. Revisions will be published on this page with an updated effective date.

## Contact Us

If you have questions or concerns about this Privacy Policy, contact:

**Email:** worsening9119@gmail.com  
**Website:** [https://0xmwehehe.xyz](https://0xmwehehe.xyz)

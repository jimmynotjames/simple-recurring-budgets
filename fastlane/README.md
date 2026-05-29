fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios verify_auth

```sh
[bundle exec] fastlane ios verify_auth
```

Verify App Store Connect API auth (read-only, builds nothing)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit a release to the App Store (metadata/screenshots skipped for now)

### ios push_metadata

```sh
[bundle exec] fastlane ios push_metadata
```

Upload localized App Store metadata only (no binary, no screenshots)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture localized screenshots in the Simulator (requires a snapshot UI test)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

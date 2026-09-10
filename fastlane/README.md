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

### ios prepare_signing

```sh
[bundle exec] fastlane ios prepare_signing
```

Prepare App Store signing without uploading a build

### ios distribute

```sh
[bundle exec] fastlane ios distribute
```

Build and distribute to Firebase App Distribution

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

----


## Android

### android distribute

```sh
[bundle exec] fastlane android distribute
```

Build and distribute to Firebase App Distribution

### android beta

```sh
[bundle exec] fastlane android beta
```

Build and upload to Google Play internal testing

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

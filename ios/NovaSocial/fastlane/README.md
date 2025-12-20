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

### ios setup

```sh
[bundle exec] fastlane ios setup
```

Setup development environment

### ios sync_dev_certs

```sh
[bundle exec] fastlane ios sync_dev_certs
```

Sync development certificates

### ios sync_appstore_certs

```sh
[bundle exec] fastlane ios sync_appstore_certs
```

Sync App Store certificates

### ios add_device

```sh
[bundle exec] fastlane ios add_device
```

Register new devices and refresh profiles

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app for testing

### ios build_release

```sh
[bundle exec] fastlane ios build_release
```

Build for App Store / TestFlight

### ios testflight_upload

```sh
[bundle exec] fastlane ios testflight_upload
```

Upload to TestFlight

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Quick upload to TestFlight (skip waiting for processing)

### ios beta_external

```sh
[bundle exec] fastlane ios beta_external
```

Release to external testers on TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit to App Store for review

### ios bump_version

```sh
[bundle exec] fastlane ios bump_version
```

Increment version number

### ios bump_build

```sh
[bundle exec] fastlane ios bump_build
```

Increment build number

### ios latest_build

```sh
[bundle exec] fastlane ios latest_build
```

Get the latest TestFlight build number

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit tests

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

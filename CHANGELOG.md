# Change log

All notable changes to the LaunchDarkly Apex server-side SDK will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

## [1.6.0](https://github.com/launchdarkly/apex-server-sdk/compare/1.5.1...1.6.0) (2026-09-04)


### Features

* Add configurable event and flag poll intervals to the bridge ([#60](https://github.com/launchdarkly/apex-server-sdk/issues/60)) ([7aebb5b](https://github.com/launchdarkly/apex-server-sdk/commit/7aebb5bf4f1ca6cc35939f9c9e86876cb1299ee7))
* Push events on their own goroutines instead of blocking the drain ([#72](https://github.com/launchdarkly/apex-server-sdk/issues/72)) ([14f6efb](https://github.com/launchdarkly/apex-server-sdk/commit/14f6efb77b883549057526d350cf0979673c2922))
* Retry the event push to LaunchDarkly once before giving up ([#69](https://github.com/launchdarkly/apex-server-sdk/issues/69)) ([76f68d1](https://github.com/launchdarkly/apex-server-sdk/commit/76f68d18496ec7da1d668c49ebfe7b97d40c73c7))
* Support more than one LaunchDarkly project and environment per Salesforce org ([#64](https://github.com/launchdarkly/apex-server-sdk/issues/64)) ([941055a](https://github.com/launchdarkly/apex-server-sdk/commit/941055ac4f5b9cce8f6a440f7cb0ef2c8c20dcb6))
* Support the OAuth client credentials flow in the bridge ([#65](https://github.com/launchdarkly/apex-server-sdk/issues/65)) ([4536966](https://github.com/launchdarkly/apex-server-sdk/commit/453696628064f3db236af86385ec74d35c0807f2))


### Bug Fixes

* Check the error from constructing the event poll request ([#67](https://github.com/launchdarkly/apex-server-sdk/issues/67)) ([7e9a41d](https://github.com/launchdarkly/apex-server-sdk/commit/7e9a41d10847cd66ab938891954b6d8c9f3a4bdd))
* Check the token response body read error where the body is load-bearing ([#68](https://github.com/launchdarkly/apex-server-sdk/issues/68)) ([74f3036](https://github.com/launchdarkly/apex-server-sdk/commit/74f30366a33b5f6bdd04f0419323e69f8e24d2e8))
* Finish with HTTP responses so connections can be reused ([#62](https://github.com/launchdarkly/apex-server-sdk/issues/62)) ([9477007](https://github.com/launchdarkly/apex-server-sdk/commit/94770074a54e222c3022701967374f88f83fb5b2))
* Make a zero cache TTL disable caching instead of disabling flag data ([#66](https://github.com/launchdarkly/apex-server-sdk/issues/66)) ([07dec93](https://github.com/launchdarkly/apex-server-sdk/commit/07dec936e4678a3e5f253a10e279ea918a4c8566))
* Report a SALESFORCE_URL host mismatch when Salesforce refuses the request ([#73](https://github.com/launchdarkly/apex-server-sdk/issues/73)) ([5f119ab](https://github.com/launchdarkly/apex-server-sdk/commit/5f119abd59115b02db8f1e19f3c690401621b9af))
* Report the real error when the flag push request cannot be built ([#71](https://github.com/launchdarkly/apex-server-sdk/issues/71)) ([860b311](https://github.com/launchdarkly/apex-server-sdk/commit/860b3115c0295ffb0525cdddd8ac46674547b2ad))
* Retry a Salesforce request once after refreshing the token ([#70](https://github.com/launchdarkly/apex-server-sdk/issues/70)) ([08a8836](https://github.com/launchdarkly/apex-server-sdk/commit/08a883686e462e1338d15f4b17c24d1bf6a8c4da))

## [1.5.1](https://github.com/launchdarkly/apex-server-sdk/compare/1.5.0...1.5.1) (2026-06-22)


### Bug Fixes

* Exit with non-zero status code on fatal errors ([#57](https://github.com/launchdarkly/apex-server-sdk/issues/57)) ([81edc40](https://github.com/launchdarkly/apex-server-sdk/commit/81edc406c635edc5baa94ae37b0fb9f93755411a))

## [1.5.0](https://github.com/launchdarkly/apex-server-sdk/compare/1.4.1...1.5.0) (2026-05-26)


### Features

* add X-LaunchDarkly-Instance-Id header (SDK-2352) ([#51](https://github.com/launchdarkly/apex-server-sdk/issues/51)) ([5eb7561](https://github.com/launchdarkly/apex-server-sdk/commit/5eb7561927b1ddf3ed87f580691c9d20d685c582))

## [1.4.1](https://github.com/launchdarkly/apex-server-sdk/compare/1.4.0...1.4.1) (2025-08-07)


### Bug Fixes

* Fix Salesforce Governor limit when syncing from bridge ([#33](https://github.com/launchdarkly/apex-server-sdk/issues/33)) ([70ba7ea](https://github.com/launchdarkly/apex-server-sdk/commit/70ba7ea82b13006118762cb026f99164d61bb6eb))

## [1.4.0](https://github.com/launchdarkly/apex-server-sdk/compare/1.3.0...1.4.0) (2025-04-14)


### Features

* Add caching data store and batching event sink ([#25](https://github.com/launchdarkly/apex-server-sdk/issues/25)) ([6bee005](https://github.com/launchdarkly/apex-server-sdk/commit/6bee0050d5ee3197641792b466e11d79b1c77b71))

## [1.3.0] - 2024-01-23
### Added:
- Added additional unit tests to meet 75% minimum coverage required by Salesforce. Thanks, @estebanefi!

## [1.2.0] - 2022-09-27
### Fixed:
- Fixed name collision between internal Event type and Salesforce Event type. The SDK Event type is now named LDEvent.

### Changed:
- Updated scratch-org definition for CircleCI unit tests.

## [1.1.1] - 2022-05-31
### Changed:
- Updated some error message strings to be more specific.

### Fixed:
- Fixed nil pointer crash when invalid PEM is used as private key (`OAUTH_JWT_KEY`).

## [1.1.0] - 2021-07-20
### Added:
- The SDK now supports the ability to control the proportion of traffic allocation to an experiment. This works in conjunction with a new platform feature now available to early access customers.

## [1.0.1] - 2021-06-14
### Fixed:
- Fixed the OAUTH_URI environment variable not being respected by the bridge.

## [1.0.0] - 2021-06-08
### Fixed:
- Fixed rollout bucketing behavior when targeting a user attribute that does not exist.

## [1.0.0-beta.3] - 2021-02-04

### Added:
- Added the `alias` method. This can be used to associate two user objects for analytics purposes by generating an alias event.

## [1.0.0-beta.2] - 2021-01-20

### Added:
- Added support for JWT based authentication in the bridge daemon with the `OAUTH_JWT_KEY` environment variable
- Added support for HTTP timeout configuration in the bridge daemon with the `HTTP_TIMEOUT` environment variable

### Fixed:
- Fixed OAuth token expiration handling in the bridge daemon

## [1.0.0-beta.1] - 2020-11-18
This is the first public release of the LaunchDarkly Apex server-side SDK. The SDK is considered to be in beta until release 1.0.0. Do not use this SDK version in production environments.

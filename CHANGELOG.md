# Change log

All notable changes to the LaunchDarkly Apex server-side SDK will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

## [1.0.0-beta.2] - 2021-01-20

### Added:
- Added support for JWT based authentication in the bridge daemon with the `OAUTH_JWT_KEY` environment variable
- Added support for HTTP timeout configuration in the bridge daemon with the `HTTP_TIMEOUT` environment variable

### Fixed:
- Fixed OAuth token expiration handling in the bridge daemon

## [1.0.0-beta.1] - 2020-11-18
This is the first public release of the LaunchDarkly Apex server-side SDK. The SDK is considered to be in beta until release 1.0.0. Do not use this SDK version in production environments.
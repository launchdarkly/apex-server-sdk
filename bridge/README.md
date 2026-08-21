# LaunchDarkly Apex SDK Salesforce Bridge

This daemon is used to ensure LaunchDarkly and the Salesforce SDK stay synchronized. The daemon can be built with `go build .`

## Configuration

The daemon uses environment variables for configuration. Refer to
[Authentication](#authentication) for choosing a flow; **client credentials** is the one to
prefer for a new deployment.

```bash
# The secrets in this example are randomly generated

# required configuration options
export LD_SDK_KEY='Your LaunchDarkly SDK key'
# such as: 'sdk-36f084b0-a57b-42a6-831e-1e20b7631b92'
export SALESFORCE_URL='Your Salesforce Apex REST URL'
# such as: 'https://na123.salesforce.com/services/apexrest/'
export OAUTH_ID='Your Salesforce OAuth Id'
# such as: 'BfBGjyY0.8XTDtB6enx5WXSATZ6mhPhnn.V2xK2Q8aYIW7KBS4r.7RA5QDbhaVOc4swvGZUqao-4X2S6Z-MdP'

# which OAuth flow to use: 'client-credentials', 'jwt-bearer' or 'password'
export OAUTH_GRANT_TYPE='client-credentials'
# if not set, the flow is inferred: JWT bearer when OAUTH_JWT_KEY is set, otherwise password
# client credentials cannot be inferred and must be requested explicitly

# when using client credentials
export OAUTH_SECRET='Your Salesforce OAuth secret'
# such as: '1193EEA95E6E26978D5BA60B103CC419FB653E314EA5BF282BDD1D429769685E'
# no username: the run-as identity is designated on the app in Salesforce

# when using JWT bearer
export OAUTH_JWT_KEY='Your RSA private key in PEM format base64 encoded'
# such as: cat private.key | base64 -w 0
export OAUTH_USERNAME='Your Salesforce username'
# such as: 'address@example.com'

# when using password auth (deprecated)
export OAUTH_SECRET='Your Salesforce OAuth secret'
export OAUTH_USERNAME='Your Salesforce username'
export OAUTH_PASSWORD='Your Salesforce password + security token'
# such as: 'mypasswordmysalesforcesecuritytoken'

# optional configuration options
export OAUTH_URI='YOUR OAUTH URI'
# if not set, defaults to: 'https://login.salesforce.com/services/oauth2/token'
# if authenticating against sandbox, use: 'https://test.salesforce.com/services/oauth2/token'
export HTTP_TIMEOUT='Your timeout'
# such as: '1500ms'
# see https://golang.org/pkg/time/#ParseDuration for formatting
export EVENT_POLL_INTERVAL='How often to drain events from Salesforce'
# such as: '10s'
# if not set, unparseable, zero, or negative, defaults to: '30s'
# anything under '5s' is honored but logs a warning about org-wide API limits
export FLAG_POLL_INTERVAL='How often to poll LaunchDarkly for flag data'
# such as: '5m'
# if not set or unparseable, defaults to: '30s'
# minimum is '30s'; anything shorter is clamped up to '30s'
```

## Authentication

Three OAuth flows are supported. Set `OAUTH_GRANT_TYPE` to choose one; the resolved flow is
logged at startup, which is the quickest way to confirm what the daemon is actually doing.

| Flow | `OAUTH_GRANT_TYPE` | Needs | Use it when |
| --- | --- | --- | --- |
| Client credentials | `client-credentials` | `OAUTH_ID`, `OAUTH_SECRET` | Default choice for a new deployment |
| JWT bearer | `jwt-bearer` | `OAUTH_ID`, `OAUTH_USERNAME`, `OAUTH_JWT_KEY` | You need to act as a specific user, or policy requires a certificate |
| Password | `password` | `OAUTH_ID`, `OAUTH_SECRET`, `OAUTH_USERNAME`, `OAUTH_PASSWORD` | Deprecated -- avoid |

**Prefer client credentials.** It needs no certificate to generate, upload or rotate, and no
username -- the run-as identity is designated on the connected app or External Client App in
Salesforce, so the daemon holds no user credential at all. It also sends no time-bound
assertion, which makes it indifferent to host clock skew.

That last point is worth knowing if you run the bridge on a VM. The JWT bearer flow signs an
assertion that expires 120 seconds after it is issued, with no tolerance, so a host whose clock
has drifted more than two minutes will fail every authentication attempt. There is no
corresponding failure mode with client credentials.

Enable the flow on the app in Salesforce before configuring it here. On an External Client App
that is the **Enable Client Credentials Flow** setting, and it requires a run-as user to be
designated.

**JWT bearer** remains fully supported and is the right choice when the bridge must act as a
particular Salesforce user, or when your security policy requires certificate-based
authentication. Note the key must be PKCS#1 -- a PEM block labelled `RSA PRIVATE KEY`. OpenSSL 3
writes PKCS#8 by default, so generate with `openssl genrsa -traditional` or convert an existing
key with `openssl rsa -traditional -in old.key -out new.key`.

**Password auth is deprecated.** Salesforce disables the username-password flow by default on
new orgs and is retiring it, and it requires a security token appended to the password. The
daemon logs a warning at startup when this flow is selected. It will be removed in a future
major version.

### Choosing the flow implicitly

`OAUTH_GRANT_TYPE` is optional. When it is unset the flow is inferred from the credentials
present -- JWT bearer if `OAUTH_JWT_KEY` is set, otherwise password -- which is how the daemon
behaved before the variable existed, so an existing deployment needs no changes.

Client credentials cannot be inferred, because its credentials are a subset of the password
flow's. Selecting it always requires setting `OAUTH_GRANT_TYPE`.

## Polling intervals

The daemon runs two independent loops, each on its own interval:

| Loop | What it does | Variable | Default | Minimum |
| --- | --- | --- | --- | --- |
| Events | Drains `EventData__c` from Salesforce, then posts to LaunchDarkly | `EVENT_POLL_INTERVAL` | `30s` | greater than zero |
| Flags | Polls LaunchDarkly for flag data, then pushes it to Salesforce | `FLAG_POLL_INTERVAL` | `30s` | `30s` |

Both accept any [`time.ParseDuration`](https://golang.org/pkg/time/#ParseDuration) string.
When a variable is unset, the daemon uses the historical 30-second cadence, so an
existing deployment behaves exactly as it did before these options were added.

The daemon never refuses to start over a poll interval. Instead it falls back or clamps
and logs the interval actually in effect, so the startup log is the authoritative record
of what the daemon is doing:

| Configured value | Result |
| --- | --- |
| unset or empty | the `30s` default |
| unparseable, such as `'30'` with no unit | the `30s` default |
| below the variable's minimum | clamped up to that minimum |

Because a malformed value is treated as unset rather than as an error, check the startup
log after changing either variable. `time.ParseDuration` requires a unit, so `'30'` is
not 30 seconds -- it does not parse, and the daemon quietly keeps the default.

Note that `HTTP_TIMEOUT` does not behave this way: an unparseable `HTTP_TIMEOUT` stops
the daemon with an error.

### Choosing an event interval

`FLAG_POLL_INTERVAL` is floored at 30 seconds to match the minimum polling interval
used across LaunchDarkly's server SDKs. `EVENT_POLL_INTERVAL` has no such floor,
because draining events more often is a reasonable tradeoff to make -- but it is a
tradeoff worth understanding before you make it.

Every drain is one inbound Salesforce REST call, and inbound calls count against your
org's 24-hour API request allocation. (The SOQL query and DML delete the drain performs
run inside the Apex transaction and count against per-transaction governor limits, not
the daily API allocation.) `FLAG_POLL_INTERVAL` contributes too, since pushing flag data
to Salesforce is also an inbound call.

Salesforce allocates API requests per 24 hours by edition. For production orgs:

| Edition | 24-hour allocation |
| --- | --- |
| Enterprise / Professional | 100,000 + 1,000 per license |
| Unlimited / Performance | 100,000 + 5,000 per license |
| Full Sandbox | 5,000,000 |

So the smallest allocation a production org has to work with is about 100,000 calls per
day. Against that, the drain alone costs:

| `EVENT_POLL_INTERVAL` | Calls/day | Smallest production org (~100,000) | 200-license EE (~300,000) | 2,000-license EE (~2.1M) |
| --- | --- | --- | --- | --- |
| `30s` (default) | ~2,880 | 2.9% | 1.0% | 0.1% |
| `10s` | ~8,640 | 8.6% | 2.9% | 0.4% |
| `5s` | ~17,280 | 17% | 5.8% | 0.8% |
| `1s` | ~86,400 | **86%** | 29% | 4% |

Whether a short interval is affordable therefore depends on your edition and license
count. On a large org a 1-second drain is a few percent of the allocation; on a small
production org the same setting consumes most of the org's entire daily budget for this
one integration, leaving little for everything else that calls the API.

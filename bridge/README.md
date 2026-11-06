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
# both the host and the path have to be right, and the host authenticates as well under
# the client credentials grant -- refer to "Getting the host right" below
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
export LD_SCOPE_KEY='A name for this project and environment'
# such as: 'gps-production'
# scopes this bridge's records within the Salesforce org
# NOT your LaunchDarkly project key -- an SDK key names one environment, so each
# project and environment pair sharing the org needs its own value
# if not set, the bridge owns records that carry no scope
# refer to "Scoping an org" below -- the Apex client must use the same value
export OAUTH_URI='YOUR OAUTH URI'
# if not set, defaults to: 'https://login.salesforce.com/services/oauth2/token'
# if authenticating against sandbox, use: 'https://test.salesforce.com/services/oauth2/token'
# the client credentials grant is not accepted on either of those shared hosts. When that
# grant is selected and this is unset, the endpoint is derived from SALESFORCE_URL instead,
# and the derived value is logged at startup
export HTTP_TIMEOUT='Your timeout'
# such as: '1500ms'
# see https://golang.org/pkg/time/#ParseDuration for formatting
# for the flag stream it bounds getting connected, not the stream itself -- refer to
# "Flag delivery" below
export FLAG_STREAMING='Whether to stream flag data from LaunchDarkly'
# 'true' or 'false'; if not set or not a boolean, defaults to: 'false'
# 'false' polls LaunchDarkly every FLAG_POLL_INTERVAL
# 'true' holds a streaming connection instead and pushes changes as they happen, at most
# once every STREAM_MIN_PUSH_INTERVAL -- refer to "Flag delivery" below before turning it on
export STREAM_MIN_PUSH_INTERVAL='The least time between two pushes to Salesforce'
# such as: '5s'
# only used when FLAG_STREAMING is 'true'
# if not set, unparseable, or negative, defaults to: '5s'
# anything under '5s' is honored but logs a warning about org-wide API limits
export LD_STREAM_URI='Your LaunchDarkly streaming endpoint'
# only used when FLAG_STREAMING is 'true'
# if not set, defaults to: 'https://stream.launchdarkly.com'
# point it at a Relay Proxy to stream from that instead
export STREAM_INITIAL_RECONNECT_DELAY='How long to wait before the first reconnect'
# such as: '2s'
# only used when FLAG_STREAMING is 'true'
# if not set, unparseable, zero, or negative, defaults to: '1s'
# each consecutive failure doubles the delay, up to 30s, with random jitter
export EVENT_POLL_INTERVAL='How often to drain events from Salesforce'
# such as: '10s'
# if not set, unparseable, zero, or negative, defaults to: '30s'
# anything under '5s' is honored but logs a warning about org-wide API limits
export FLAG_POLL_INTERVAL='How often to poll LaunchDarkly for flag data'
# such as: '5m'
# only used when FLAG_STREAMING is 'false', the default; otherwise it is ignored and a
# notice is logged
# if not set or unparseable, defaults to: '30s'
# minimum is '30s'; anything shorter is clamped up to '30s'
export MAX_EVENTS_PER_DRAIN='How many events one drain may take'
# such as: '2000'
# if not set, unparseable, zero, or negative, defaults to: '10000'
# maximum is '10000'; anything larger is lowered to it
# lower it if a drain runs out of Apex heap -- refer to "How many events one drain takes"
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
designated -- the flow carries no user context, so Salesforce needs to be told which identity
to act as. Note the setting appears in two places, the app's OAuth settings and its policies,
and both must be enabled.

This grant is **not accepted on `login.salesforce.com` or `test.salesforce.com`**. Those hosts
answer `invalid_grant: request not supported on this domain`, which names neither the grant nor
the setting at fault. Point `OAUTH_URI` at the org's own domain instead:

```bash
export OAUTH_URI='https://MyDomainName.my.salesforce.com/services/oauth2/token'
```

Or leave `OAUTH_URI` unset and the bridge derives that endpoint from `SALESFORCE_URL`, logging
what it chose. Configuring a login host explicitly logs a warning, since the derivation cannot
override an explicit choice.

**JWT bearer** remains fully supported and is the right choice when the bridge must act as a
particular Salesforce user, or when your security policy requires certificate-based
authentication. Note the key must be PKCS#1 -- a PEM block labelled `RSA PRIVATE KEY`. OpenSSL 3
writes PKCS#8 by default, so generate with `openssl genrsa -traditional` or convert an existing
key with `openssl rsa -traditional -in old.key -out new.key`.

**Password auth is deprecated.** Salesforce disables the username-password flow by default on
new orgs and is retiring it, and it requires a security token appended to the password. The
daemon logs a warning at startup when this flow is selected. It will be removed in a future
major version.

### Getting the host right

`SALESFORCE_URL` supplies both the host and the path of every API call, and both have to be
correct. The host authenticates as well: under the client credentials grant the token
endpoint is derived from it when `OAUTH_URI` is unset.

The usual mistake is copying the URL out of the browser address bar. That is the
**Lightning host**, `https://mycompany.lightning.force.com/`, which serves the Salesforce UI
and not the API. The host you want is the org's **My Domain** host,
`https://mycompany.my.salesforce.com/`.

A session is only valid on the host it was issued for, so a `SALESFORCE_URL` naming a
different host fails every call with `INVALID_SESSION_ID`. Salesforce reports the host it did
issue the session for as `instance_url` in the token response, which you never see. The
daemon compares the two, and says so when a request is refused, the token is refreshed, and
the request is refused again:

```
Salesforce refused the request again after a token refresh, and SALESFORCE_URL does not match the URL Salesforce issued the session for. A session is only valid on the URL it was issued for, so check SALESFORCE_URL against the org's "My Domain" host.
```
### Choosing the flow implicitly

`OAUTH_GRANT_TYPE` is optional. When it is unset the flow is inferred from the credentials
present -- JWT bearer if `OAUTH_JWT_KEY` is set, otherwise password -- which is how the daemon
behaved before the variable existed, so an existing deployment needs no changes.

Client credentials cannot be inferred, because its credentials are a subset of the password
flow's. Selecting it always requires setting `OAUTH_GRANT_TYPE`.

## Scoping an org

A single Salesforce org can hold flag data for more than one source of LaunchDarkly flags. Run
one bridge per source, and give the bridge and the Apex client the *same* scope key:

```bash
export LD_SCOPE_KEY='gps-production'
```

```apex
LDConfig config = new LDConfig.Builder()
    .setScopeKey('gps-production')
    .build();
LDClient client = new LDClient(config);
```

**A scope is one environment of one project, not a project.** `LD_SDK_KEY` holds an SDK key,
and an SDK key is scoped to a single LaunchDarkly environment, so a bridge only ever sees one
environment of one project. The scope key must therefore be unique for every project and
environment pair that shares the org.

Do not set it to your LaunchDarkly project key. Two environments of the same project would
then share a scope, and each bridge's push deletes the other's flag data. The org would
alternate between the two environments' targeting with every push, and evaluation would
return real flag values from whichever environment pushed last. Combining both names, as in
`gps-production`, is the simplest value that stays unique.

The bridge sends its key to Salesforce as an `LD-Scope-Key` header, and the Apex side scopes
every read, write and delete to it. Leaving both unset is the default and scopes everything to
records carrying no scope, which is how the SDK behaved before this option existed.

**The two values must agree.** A mismatch produces no error. Evaluation simply finds no flag
data for the configured scope and every variation call returns its fallback, so check the
bridge's startup log, which reports the key in effect.

Source the scope key from one place in your Apex -- a custom setting or a single constant --
rather than at each call site. A partial rollout where some entry points name the scope and
others do not is the one state the migration below does not account for.

### Case sensitivity

Keys that differ only by letter case are not supported, for scopes, flags, or segments. Match
the case of every key exactly as it appears in LaunchDarkly, in `LD_SCOPE_KEY` and in
`setScopeKey` alike. Refer to "Key case sensitivity" in [the API documentation](../doc.md).

### Migrating an existing deployment

Nothing needs backfilling: the bridge replaces all of a scope's flag data on every push, and
queued events are drained continuously, so records are replaced rather than migrated.

1. Deploy the new Apex with no scope key configured. This changes nothing -- reads still
   match the records your current bridge writes.
2. Leave the existing bridge running, and start a second one with `LD_SCOPE_KEY` set. The two
   coexist safely: each owns its own records and neither deletes the other's.
3. Set the same key on the Apex client. Its data is already populated by step 2, so there is no
   window where evaluation falls back.
4. Keep both bridges running until the events that carry no scope have drained. No new ones
   are created once step 3 lands.
5. Stop the original bridge.
6. Delete the leftover flag data that carries no scope:

   ```apex
   delete [SELECT Id FROM VersionedData__c WHERE Scope__c = null LIMIT 10000];
   ```

Two details in that order are load-bearing:

- **Step 5 must come before step 6.** Delete those records while the original bridge is still
  running and its next push recreates them.
- **Do not stop the original bridge before step 4 finishes.** Nothing else drains events that
  carry no scope, and undrained events count against that scope's `maxEventsInQueue` forever.

Step 6 is a manual step by design. Each bridge only ever deletes its own scope's records, so
records left behind by a decommissioned bridge are not cleaned up for you. The `LIMIT` is there
because a single DML delete is capped at 10,000 rows; repeat it, or use Batch Apex, if you have
more than that.

## Flag delivery

By default the daemon **polls** LaunchDarkly for flag data every `FLAG_POLL_INTERVAL`, as
it always has, and pushes the data to the org when the poll says it changed.

Set `FLAG_STREAMING='true'` to **stream** instead. The daemon then holds one long-lived
connection to LaunchDarkly's streaming service, the same one the other server-side SDKs
use, and LaunchDarkly pushes each change down it as the change is saved. The daemon
applies the change to its own copy of the environment and pushes the whole set to the
org, so a flag change reaches Salesforce in about the time one Apex REST call takes,
rather than up to 30 seconds later.

```
delivering flags by streaming from https://stream.launchdarkly.com, pushing to Salesforce at most every 5s
connecting to the LaunchDarkly stream at: https://stream.launchdarkly.com/all
received 12 flags and 3 segments from the LaunchDarkly stream
pushing flags to: https://mycompany.my.salesforce.com/services/apexrest/store
the LaunchDarkly stream updated flags "checkout-redesign" to version 14
pushing flags to: https://mycompany.my.salesforce.com/services/apexrest/store
```

Nothing changes on the Apex side. The stream feeds the same `store` endpoint with the same
document a poll would have pushed, so the org and the bridge can still be upgraded in
either order.

Streaming is opt-in because a long-lived connection is something egress proxies and
firewalls often have to be told to allow. It will become the default in the next major
version.

To watch it work, deploy the Visualforce page in [`examples/flag-demo`](../examples/flag-demo):
it evaluates a flag with the SDK and shows the result, so a change saved in LaunchDarkly
appears on the next reload.

### What the stream costs

Streaming buys latency, not API calls. Every push of flag data is one inbound Salesforce
API call, and inbound calls count against the org's 24-hour allocation, which is shared
with every other integration in the org (refer to [Choosing an event
interval](#choosing-an-event-interval) for the allocations by edition). Polling already
pushes only when something changed: it sends `If-None-Match`, and a `304` costs the org
nothing. So an environment whose flags change ten times a day costs about ten calls a day
under polling, and about ten under streaming. Streaming is never cheaper than polling,
and without a floor it would be dearer, because LaunchDarkly sends one event per changed
flag or segment: a Terraform apply or a script that touches 300 flags arrives as 300
events over a few seconds, where a poll would have seen one change.

`STREAM_MIN_PUSH_INTERVAL` is that floor. Pushes are never closer together than it, and
every change that arrives while the daemon is waiting is folded into the next push, so
the interval is a ceiling on how many Salesforce API calls streaming can make rather than
a delay on each change:

- A change in a quiet period is pushed at once.
- A burst of changes costs one push, or two if it straddles the interval.
- Under sustained change the daemon pushes once per interval, however many changes
  arrive.

The default is five seconds, so a bulk edit lands within a few seconds of its last change
and a day of continuous change costs at most 17,280 calls, the same arithmetic as for
`EVENT_POLL_INTERVAL` below. Raise it to `30s` for the same ceiling on Salesforce API
calls that polling has, which still delivers a change in a quiet period at once. Lower it
if the latency matters more than the allocation: at `0s` every change is its own call.
Anything under five seconds logs a warning at startup.

A reconnect costs the org nothing unless something changed. Every connection opens with
the complete flag set, and the daemon compares that against what it last pushed; after a
network blip it finds them identical and skips the push. Only a change that happened while
the connection was down is pushed, and it is pushed as soon as the connection is back and
the interval allows.

### When the connection drops

The daemon reconnects on its own. The first attempt waits `STREAM_INITIAL_RECONNECT_DELAY`,
one second by default, and each consecutive failure doubles the wait up to 30 seconds, with
random jitter so a fleet of bridges does not reconnect in step. After a minute without a
failure the delay goes back to the start. A connection that goes silent for five minutes is
treated as dead and reconnected the same way -- LaunchDarkly sends a heartbeat every three
minutes or so, so a healthy connection is never silent that long.

A bridge started during a LaunchDarkly outage keeps retrying until the outage ends, rather
than exiting. The org keeps serving whatever flag data it holds throughout.

No response from the stream stops the daemon, since stopping flag delivery would stop
event delivery with it, and a daemon that has stopped needs someone to notice. Two kinds
of response do move the reconnects onto a slower schedule, because asking again every few
seconds cannot change the answer: five minutes before the next attempt, doubling to an
hour between attempts, until the service answers differently.

- A `401` or `403` from the stream, which means `LD_SDK_KEY` is wrong or has been revoked.
  The log says so and names the variable.
- Any other `4xx` apart from `400`, `408` and `429`, such as the `404` a wrong
  `LD_STREAM_URI` produces. The log names that variable instead.

Under polling the same `401` or `403` stops the daemon, as it always has.

### When Salesforce refuses a push

A push the org refuses, or that never arrives, is retried: after one second, then two, then
four, up to 30 seconds between attempts, and never sooner than `STREAM_MIN_PUSH_INTERVAL`
after the attempt before it. A change that lands while a retry is waiting goes out in the
retry, so no change is ever lost to a Salesforce outage, but it does not bring the retry
forward: an org that has hit its API limit answers every push with a `403`, and pushing at
the rate flags change would only dig the hole deeper. The retry stops only when a push
succeeds or the daemon shuts down. This differs from polling, where a failed push is simply
tried again on the next poll; a stream has no next poll until the flag changes again, so it
needs its own retry.

The one exception is the same one polling has: Salesforce rejecting the credential on a
token refresh is permanent, and stops the daemon.

### Settings that only apply to one mode

Under polling `FLAG_POLL_INTERVAL` applies, and `LD_STREAM_URI`,
`STREAM_INITIAL_RECONNECT_DELAY` and `STREAM_MIN_PUSH_INTERVAL` do not. Under streaming it
is the other way round, and a `FLAG_POLL_INTERVAL` that is set anyway earns a notice at
startup saying it has no effect.

`HTTP_TIMEOUT` behaves differently for the stream. For every other request it bounds the
whole exchange, which for a stream would end the connection after 30 seconds, so for the
stream it bounds getting connected instead: the TCP dial, the TLS handshake, and the wait
for response headers each have to finish within it. Silence after that is governed by the
five-minute read timeout above.

## Polling intervals

The daemon runs two independent loops, each on its own interval:

| Loop | What it does | Variable | Default | Minimum |
| --- | --- | --- | --- | --- |
| Events | Drains `EventData__c` from Salesforce, then posts to LaunchDarkly | `EVENT_POLL_INTERVAL` | `30s` | greater than zero |
| Flags | Polls LaunchDarkly for flag data, then pushes it to Salesforce | `FLAG_POLL_INTERVAL` | `30s` | `30s` |

The flags row is the default; with `FLAG_STREAMING` set to `'true'` the flag loop streams
instead, and `STREAM_MIN_PUSH_INTERVAL` takes the place of the poll interval as the bound
on how often it calls Salesforce -- refer to [Flag delivery](#flag-delivery). Both
intervals accept any [`time.ParseDuration`](https://golang.org/pkg/time/#ParseDuration)
string. When a variable is unset, the daemon uses the historical 30-second cadence, so an
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
the daily API allocation.) Flag pushes contribute too, since pushing flag data to
Salesforce is also an inbound call -- one per poll that found a change under polling, and
at most one per `STREAM_MIN_PUSH_INTERVAL` under streaming.

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

## How many events one drain takes

Each drain asks the org for at most `MAX_EVENTS_PER_DRAIN` rows, and the org deletes
exactly the rows it handed over. The default is 10,000, which is also the maximum: that is
how many rows one Apex transaction can delete.

Rows are not the only governor limit a drain has to fit inside. A transaction also has 6 MB
of heap, and that depends on the size of your event payloads rather than their number. If
drains start failing and the queue keeps growing, lower `MAX_EVENTS_PER_DRAIN`; the next
poll recovers on its own.

# Flag demo

A small Visualforce page that evaluates a flag with the SDK and shows the result, for
checking that the bridge is delivering flag data to an org.

It is a separate Salesforce DX project rather than part of `force-app`, so that deploying
the SDK never deploys the demo.

**Deploy it to a sandbox or a Developer Edition org only.** The page evaluates flags, and
so writes evaluation events, every time it loads, and it does so from a plain GET with no
confirmation token, so anyone who can reach the page can generate events. That is fine
for checking a bridge and not for a production org.

## What it shows

- One featured flag, evaluated for a user key you choose, with the SDK's evaluation reason
  and variation index. The flag is read with `jsonVariation`, so any flag type works.
- Every flag the bridge has mirrored into the org, with its value for the same user.

Each evaluation writes a feature event to `EventData__c`, which the bridge drains and
forwards to LaunchDarkly, so reloading the page exercises both directions.

## Deploying

Deploy the SDK from the repository root first, then the demo from this directory:

```bash
sf project deploy start --source-dir ../../force-app --target-org <org>
sf project deploy start --source-dir force-app --target-org <org>
```

Then open `/apex/FlagDemo` on the org's My Domain host. The page accepts three optional
parameters, `user`, `flag` and `scope`:

```
https://MyDomainName.my.salesforce.com/apex/FlagDemo?user=demo-user&flag=test-flag&scope=gps-production
```

`scope` must be the bridge's `LD_SCOPE_KEY`, if it has one. The SDK scopes every read to
it, and a mismatch produces no error: the page simply finds no flag data and shows the
fallback for everything. Leave it blank for a bridge started without `LD_SCOPE_KEY`.

With the bridge streaming, a change saved in LaunchDarkly shows on the next reload. A
second change made within the bridge's `STREAM_MIN_PUSH_INTERVAL` of the first, five
seconds by default, is held until that interval has passed.

## A note on the controller

The evaluation runs from the page's `action` attribute, not from the controller's
constructor. Every evaluation writes an event row, and Visualforce forbids DML during
construction; the first draft of this page failed with "DML currently not allowed" for
exactly that reason.

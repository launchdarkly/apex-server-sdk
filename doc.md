# Apex Server-Side SDK API Documentation

## Key case sensitivity

LaunchDarkly treats flag, segment, and project keys as case sensitive. `MyFlag` and `myflag`
are two different flags.

**This SDK does not support case-sensitive keys, for flags, for segments, or for the scope keys
you configure.**

The cause is the platform. Salesforce compares text fields without regard to case, and it only
allows a case-sensitive text field when that field is also unique. Neither field this SDK stores
keys in can be unique: the same flag key appears in every LaunchDarkly project, and a scope key
repeats on every one of its records. The SDK has no way to make the comparison exact.

### What this means for you

Choose keys that stay unique when case is ignored:

- Within a LaunchDarkly project, do not create two flags, or two segments, whose keys differ
  only by case.
- Across the scope keys you configure, do not use two that differ only by case.

Then match the case exactly everywhere a key is written: the key in LaunchDarkly, the key you
pass to a variation method, the `LD_SCOPE_KEY` given to the bridge, and the value given to
`setScopeKey`.

**If you do use keys that differ only by case, which record the SDK resolves to is undefined.**
A lookup can return either record. The answer can differ depending on whether you set a cache
TTL, because the cache is an Apex map and Apex compares map keys with regard to case. It can
change between releases without notice. Do not depend on it.

A lookup whose case does not match any stored key may still resolve to a record today, for the
same reason. That is not a supported fallback, and it is not something to build on.

### What the SDK does guarantee

Two things, both about data rather than about resolution:

- A push for one scope never deletes the records of a scope whose key differs only by case. A
  bridge started with `alpha` leaves everything belonging to `Alpha` in place.
- A bridge never drains and deletes the queued events of a scope whose key differs only by
  case, as long as that scope has events of its own.

### What is not affected

The SDK stores each key exactly as LaunchDarkly sends it, so stored data stays faithful even
when a lookup does not. These parts of evaluation compare with regard to case:

- Individual user targeting on a flag.
- The `included` and `excluded` lists of a segment.
- The clause operators, including `in`, `startsWith`, `endsWith`, `contains`, `matches`, and the
  semantic version comparisons.
- User attribute names. A custom attribute keeps its own case, even when its name matches a
  built-in attribute after case is ignored.

## class LDConfig

An immutable configuration object for `LDClient`. This class cannot be
constructed directly.

### Getter methods

See `LDConfig.Builder` for descriptions.

```java
Boolean getAllAttributesPrivate()
Integer getMaxEventsInQueue()
Integer getCacheTtl()
Boolean getBatchEvents()
String getScopeKey()
```

## class LDConfig.Builder

A builder to construct an instance of `LDConfig`. This builder may be re-used,
although this should not be required.

### Constructor

Unlike other SDKs an `LDConfig` does not require a key.

```java
Builder()
```

### Setter methods

#### `allAttributesPrivate`
If all events sent to LaunchDarkly by this client should have fully redacted
user attributes. If `allAttributesPrivate` is set to `null` it defaults to
`false`.

```java
Builder setAllAttributesPrivate(Boolean allAttributesPrivate)
```

#### `setCacheTtl`
By default, the SDK will issue an SOQL query to fetch each feature flag or segment on demand. This ensures the SDK is working on the latest known data. However, this can run into governor limits, depending on your usage patterns.

To prevent excessive querying, you can enable caching with `setCacheTtl`. This will cache the feature flags and segments for the specified number of milliseconds.

If the cache is enabled, the SDK will instead load the entire data set from the store, only requerying for data every `cacheTtl` milliseconds. This can help reduce the number of queries made to the store, but it may also mean that the SDK is working with potentially stale data.

The cache setting also changes how a key that differs only by case resolves, which is one reason
that behavior is undefined. Refer to "Key case sensitivity" above.

```java
Builder setCacheTtl(Long ttl)
```

#### `setMaxEventsInQueue`

The maximum number of events that can be queued for collection by the bridge.
If this limit is breached before events are delivered by the bridge events
will be dropped to prevent resource exhaustion. The default limit is 1000
queued events. If `maxEvents` is set to `null` the default limit is used.

```java
Builder setMaxEventsInQueue(Integer maxEvents)
```

#### `setBatchEvents`

By default, the SDK uses an event sink that writes each event to the `EventData__c` table immediately as it is generated. This means events are persisted in real time, and no explicit flush or close call is required to ensure delivery.

If you are generating a large number of events in a short period of time, this can be inefficient due to the overhead of individual DML operations. To address this, the SDK can be configured to use a batching event sink that accumulates events in memory and writes them to the table in a single transaction when `LDClient.close` is called.

>**Note:** If you are using the `batchEvents` feature, you *must* call `LDClient.close` at the end of your transaction. Without this call, batched events will not be written to the table.

```java
Builder setBatchEvents(Boolean batchEvents)
```

#### `setScopeKey`

Scopes this client within the Salesforce org, so that one org can hold flag data for more than
one source of LaunchDarkly flags. The client reads, writes, and deletes only the records that
carry the scope key you set here.

**A scope is one environment of one project, not a project.** A bridge authenticates with an
SDK key, and an SDK key is scoped to a single LaunchDarkly environment. The scope key must
therefore be unique for every project and environment pair that shares the org. Do not set it
to your LaunchDarkly project key: two environments of the same project would then share a
scope, and each bridge's push would delete the other's flag data on every poll. Combining both
names, as in `myproject-production`, is the simplest value that stays unique.

The bridge must be configured with the same key, through its `LD_SCOPE_KEY` variable. A
mismatch produces no error. Evaluation finds no flag data and every variation call returns
its fallback.

If `scopeKey` is `null` or an empty string, the client is scoped to the records that carry no
scope. This is the default, and it is how the SDK behaved before this option existed.

The setter trims the key and treats a blank key as an absent one, which matches the way the
bridge handles the key it sends. It does not change the letter case, because LaunchDarkly keys
are case sensitive.

Scope keys that differ only by case are not supported. Refer to "Key case sensitivity"
above.

```java
Builder setScopeKey(String scopeKey)
```

### Other methods

Construct an instance of `LDConfig` based on the builders state.

```java
LDConfig build()
```

## class LDClient

### Constructor

Create a client that can be used to evaluate flags. Unlike other SDKs this does
not initialize a connection to LaunchDarkly and is instantaneous. If `config` is
`null` a default `LDConfig` will be used.

```java
LDClient(LDConfig config)
```

A second constructor is available that always uses a default `LDConfig`.

```java
LDClient()
```

### Evaluation methods without details

Evaluate the flag `key` for `user`, returning `fallback` on failure. If either
`key`, or `user` are `null`, the value of `fallback` is returned.

```java
Boolean boolVariation(LDUser user, String key, Boolean fallback)
Integer intVariation(LDUser user, String key, Integer fallback)
Double doubleVariation(LDUser user, String key, Double fallback)
String stringVariation(LDUser user, String key, String fallback)
LDValue jsonVariation(LDUser user, String key, LDValue fallback)
```

### Evaluation methods with details

Evaluate a flag, but return an explanation as to why an evaluation happened.
You must pass an instance of `EvaluationDetail` as `details`. During evaluation
this object will be filled with an explanation.

```java
Boolean boolVariation(LDUser user, String key, Boolean fallback, EvaluationDetail details)
Integer intVariation(LDUser user, String key, Integer fallback, EvaluationDetail details)
Double doubleVariation(LDUser user, String key, Double fallback, EvaluationDetail details)
String stringVariation(LDUser user, String key, String fallback, EvaluationDetail details)
LDValue jsonVariation(LDUser user, String key, LDValue fallback, EvaluationDetail details)
```

### Other methods

#### `allFlags`
Evaluate all flags for a given user, returning a map of flag key to evaluation
result.

```java
Map<String, LDValue> allFlags(LDUser user)
```

#### `identify`
Send a user to LaunchDarkly.

```java
void identify(LDUser user)
```

#### `track`
Send an event to LaunchDarkly. If `user`, or `key` are `null` this is a no-op.
The fields `optionalMetric`, and `optionalValue` may both be `null`.

```java
void track(LDUser user, String key, Double optionalMetric, LDValue optionalValue)
```

#### `close`
When using the batching event sink (see `LDConfig.Builder.setBatchEvents`), call `close` when you are done with the SDK to ensure that all buffered events are written to the table. When using the default event sink, events are written immediately, so calling `close` is not strictly necessary but is still recommended for a clean shutdown.

```java
void close()
```

## class LDClient.EvaluationDetail

Details such as `EvaluationReason` associated with an evaluation.

### Methods

Return an explanation as to why the evaluation returned the value it did.

```java
EvaluationReason getReason()
```

If an evaluation did not return the default value, return the index of the
returned value. May be `null`.

```java
Integer getVariationIndex()
```

## class EvaluationReason

An explanation for why an evaluation returned the result that it did.

### Methods

Return the kind of the evaluation. Never `null`.

```java
Kind getKind()
```

When the kind is `RULE_MATCH`, return the index of the rule, otherwise `null`.

```java
Integer getRuleIndex()
```

## enum EvaluationReason.Kind

The kinds of reasons an evaluation can happen.

```java
enum Kind {
    OFF,
    FALLTHROUGH,
    TARGET_MATCH,
    RULE_MATCH,
    PREREQUISITE_FAILED,
    ERROR
}
```

## enum EvaluationReason.ErrorKind

The types of errors an evaluation can fail with.

```java
enum ErrorKind {
    FLAG_NOT_FOUND,
    MALFORMED_FLAG,
    USER_NOT_SPECIFIED,
    WRONG_TYPE,
    EXCEPTION_THROWN
}
```

## class LDUser

An immutable user object used for feature flag targeting and analytics events.
This class cannot be constructed directly.

### Getter methods

See `LDUser.Builder` for descriptions.

```java
String getKey()
Boolean getAnonymous()
String getIP()
String getFirstName()
String getLastName()
String getEmail()
String getName()
String getAvatar()
String getCountry()
String getSecondary()
LDValueObject getCustom()
```

### class LDUser.Builder

### Constructor

Create a builder for a non anonymous user with a `key`. The parameter `key`
should not be null.

```java
Builder(String key)
```

### Setter methods

Set a users attribute. Any of these parameters may be `null`.

```java
Builder setIP(String ip)
Builder setFirstName(String firstName)
Builder setLastName(String lastName)
Builder setEmail(String email)
Builder setName(String name)
Builder setAvatar(String avatar)
Builder setCountry(String country)
Builder setCustom(LDValueObject custom)
```

The set of user attributes that should be redacted from events sent to
LaunchDarkly. May be `null`.

```java
Builder setPrivateAttributeNames(Set<String> privateAttributeNames)
```

Set the users `key`, should not be `null.`

```java
Builder setKey(String key)
```

Mark a user as anonymous or not. If `null` this defaults to `false`.

```java
Builder setAnonymous(Boolean anonymous)
```

### Other methods

Construct an immutable `LDUser` based on the builders state.

```java
LDUser build()
```

## class LDValue

An immutable class representing a JSON value.

### Methods

Return the `LDValueType` of this value.

```java
LDValueType getType()
```

If the value is a `LDBOOLEAN` return the value, otherwise `false`.

```java
Boolean booleanValue()
```

If the value is a `LDNUMBER` return the value, otherwise `0`.

```java
Double doubleValue()
Integer intValue()
Long longValue()
```

If the value is a `LDSTRING` return the value, otherwise `""`.

```java
Boolean stringValue()
```

If the value is a `LDOBJECT` or `LDARRAY` return the number of elements, otherwise `0`.

```java
Integer size()
```

Convert an `LDValue` to something similar to the result of `deserializeUntyped`.

```java
Object toGeneric()
```

If the value is a `LDLIST`, and `index` is within bounds return the value at
`index`, otherwise return `null`.

```java
LDValue get(Integer index)
```

If the value is a `LDOBJECT`, and `key` is contained within the map,
return the value at key, otherwise `null`.

```java
LDValue get(String index)
```

Helpers that return `true` / `false` depending on the predicate.

```java
Boolean isInt()
Boolean isNumber()
Boolean isString()
Boolean equals(LDValue other)
```

### Static methods

Construct an instance of `LDValue` from normal Apex values.

```java
LDValue of(Boolean value)
LDValue of(Integer value)
LDValue of(Double value)
LDValue of(Decimal value)
LDValue of(String value)
LDValue ofGeneric(Object value)
```

## enum LDValueType

The types that an `LDValue` can be. Equivalent to JSON types.

```java
enum LDValueType {
    LDNULL,
    LDBOOLEAN,
    LDNUMBER,
    LDSTRING,
    LDARRAY,
    LDOBJECT
}
```

## class LDValueArray.Builder

A builder to assist the construction of an `LDValue` of type `LDARRAY`.

### Constructor

Create the builder. Defaults to an empty list.

```java
Builder()
```

### Methods

Append an `LDValue` to the end of the builders internal list.

```java
Builder add(LDValue value)
```

Create an immutable `LDValue` from the internal list.

```java
LDValue build()
```

## class LDValueObject.Builder

A builder to assist the construction of an `LDValue` of type `LDOBJECT`.

### Constructor

Create the builder. Defaults to an empty object.

```java
Builder()
```

### Methods

Set `key` to `value` in the internal map. If `key` is `null` this operation does
nothing. If `value` is `null` this functions as a delete.

```java
Builder set(String key, LDValue value)
```

Create an immutable `LDValue` from the internal map.

```java
LDValue build()
```

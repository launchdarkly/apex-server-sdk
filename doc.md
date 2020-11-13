# Apex Server-Side SDK API Documentation

## class LDConfig

An immutable configuration object for `LDClient`. This class cannot be
constructed directly.

### Getter methods

See `LDConfig.Builder` for descriptions.

```java
Boolean getAllAttributesPrivate()
Integer getMaxEventsInQueue()
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

If all events sent to LaunchDarkly by this client should have fully redacted
user attributes. If `allAttributesPrivate` is set to `null` it defaults to
`false`.

```java
Builder setAllAttributesPrivate(Boolean allAttributesPrivate)
```

The maximum number of events that can be queued for collection by the bridge.
If this limit is breached before events are delivered by the bridge events
will be dropped to prevent resource exhaustion. The default limit is 1000
queued events. If `maxEvents` is set to `null` the default limit is used.

```java
Builder setMaxEventsInQueue(Integer maxEvents)
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

Evaluate all flags for a given user, returning a map of flag key to evaluation 
result.

```java
Map<String, LDValue> allFlags(LDUser user)
```

Send a user to LaunchDarkly.

```java
void identify(LDUser user)
```

Send an event to LaunchDarkly. If `user`, or `key` are `null` this is a no-op.
The fields `optionalMetric`, and `optionalValue` may both be `null`.

```java
void track(LDUser user, String key, Double optionalMetric, LDValue optionalValue)
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
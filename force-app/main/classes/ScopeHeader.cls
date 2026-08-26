// Reads the LaunchDarkly scope key from an inbound Apex REST request.
//
// The scope travels as a header rather than in the body or the URL. The bridge forwards
// LaunchDarkly's flag payload verbatim, and DataStore.putAll treats every top-level key of
// that payload as a kind and casts its value to a Map, so adding a sibling key would throw
// in any org running an older version of this SDK. A header is ignored by older orgs and
// omitted by older bridges, so the two sides can be upgraded in either order.
public class ScopeHeader {
  // RestRequest.headers is a plain Map with case-sensitive lookup, while HTTP header names
  // are case-insensitive and intermediaries are free to change their casing. Scan instead
  // of indexing so a differently-cased header is still found.
  public static String read(RestRequest request, String name) {
    if (request == null || request.headers == null || name == null) {
      return null;
    }

    for (String header : request.headers.keySet()) {
      if (header != null && header.equalsIgnoreCase(name)) {
        String value = request.headers.get(header);

        // An absent scope and an empty one mean the same thing: records with no scope.
        if (String.isBlank(value)) {
          return null;
        }

        return value.trim();
      }
    }

    return null;
  }
}

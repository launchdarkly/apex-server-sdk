public class SemanticVersion {
  private final Integer major;
  private final Integer minor;
  private final Integer patch;
  private final String prerelease;
  private final List<String> prereleaseComponents;
  private final String build;

  private static Pattern VERSION_REGEX = Pattern.compile(
    '^(?<major>0|[1-9]\\d*)(\\.(?<minor>0|[1-9]\\d*))?(\\.(?<patch>0|[1-9]\\d*))?' +
    '(\\-(?<prerel>[0-9A-Za-z\\-\\.]+))?(\\+(?<build>[0-9A-Za-z\\-\\.]+))?$'
  );

  public SemanticVersion(Integer major, Integer minor, Integer patch, String prerelease, String build) {
    this.major = major;
    this.minor = minor;
    this.patch = patch;
    this.prerelease = prerelease;
    this.build = build;

    if (prerelease != null) {
      this.prereleaseComponents = prerelease.split('\\.');
    }
  }

  public Integer getMajor() {
    return major;
  }

  public Integer getMinor() {
    return minor;
  }

  public Integer getPatch() {
    return patch;
  }

  public String getPrerelease() {
    return prerelease;
  }

  public String getBuild() {
    return build;
  }

  public static SemanticVersion parse(String input) {
    Matcher matcher = VERSION_REGEX.matcher(input);

    if (!matcher.matches()) {
      return null;
    }

    Integer major = Integer.valueOf(matcher.group(1));
    Integer minor = 0;
    Integer patch = 0;
    String prerelease = matcher.group(7);
    String build = matcher.group(9);

    if (matcher.group(3) != null) {
      minor = Integer.valueOf(matcher.group(3));
    }

    if (matcher.group(5) != null) {
      patch = Integer.valueOf(matcher.group(5));
    }

    return new SemanticVersion(major, minor, patch, prerelease, build);
  }

  private static Integer compareInt(Integer a, Integer b) {
    if (a == b) {
      return 0;
    } else if (a < b) {
      return -1;
    } else {
      return 1;
    }
  }

  public Integer compare(SemanticVersion other) {
    if (other == null) {
      return 1;
    }

    if (this.major != other.major) {
      return compareInt(this.major, other.major);
    }

    if (this.minor != other.minor) {
      return compareInt(this.minor, other.minor);
    }

    if (this.patch != other.patch) {
      return compareInt(this.patch, other.patch);
    }

    if (this.prerelease == null && other.prerelease == null) {
      return 0;
    }

    if (this.prerelease == null) {
      return 1;
    }

    if (other.prerelease == null) {
      return -1;
    }

    return compareIdentifiers(this.prereleaseComponents, other.prereleaseComponents);
  }

  private Integer compareIdentifiers(List<String> ids1, List<String> ids2) {
    for (Integer i = 0;; i++) {
      if (i >= ids1.size()) {
        if (i >= ids2.size()) {
          return 0;
        } else {
          return -1;
        }
      }

      if (i >= ids2.size()) {
        return 1;
      }

      Integer n1, n2, d;
      Boolean isNum1, isNum2;

      try {
        n1 = Integer.valueOf(ids1.get(i));
        isNum1 = true;
      } catch (Exception err) {
        isNum1 = false;
      }

      try {
        n2 = Integer.valueOf(ids2.get(i));
        isNum2 = true;
      } catch (Exception err) {
        isNum2 = false;
      }

      if (isNum1 && isNum2) {
        d = compareInt(n1, n2);
      } else {
        if (isNum1) {
          d = -1;
        } else {
          if (isNum2) {
            d = 1;
          } else {
            d = ids1.get(i).compareTo(ids2.get(i));
          }
        }
      }

      if (d != 0) {
        return d;
      }
    }
    // impossible but required
    return 0;
  }
}

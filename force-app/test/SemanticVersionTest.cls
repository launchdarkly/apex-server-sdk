@isTest
private class SemanticVersionTest {
    @isTest static void canParseSimpleCompleteVersion() {
        SemanticVersion sv = SemanticVersion.parse('2.3.4');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(4, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithPrerelease() {
        SemanticVersion sv = SemanticVersion.parse('2.3.4-beta1.rc2');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(4, sv.getPatch());
        System.assertEquals('beta1.rc2', sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithBuild() {
        SemanticVersion sv = SemanticVersion.parse('2.3.4+build2.4');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(4, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals('build2.4', sv.getBuild());
    }
    
    @isTest static void canParseVersionWithPrereleaseAndBuild() {
        SemanticVersion sv = SemanticVersion.parse('2.3.4-beta1.rc2+build2.4');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(4, sv.getPatch());
        System.assertEquals('beta1.rc2', sv.getPrerelease());
        System.assertEquals('build2.4', sv.getBuild());    
    }
    
    @isTest static void leadingZeroNotAllowedInMajor() {
        SemanticVersion sv = SemanticVersion.parse('02.3.4');
        System.assertEquals(null, sv);
    }
    
    @isTest static void leadingZeroNotAllowedInMinor() {
        SemanticVersion sv = SemanticVersion.parse('2.03.4');
        System.assertEquals(null, sv);
    }
    
    @isTest static void leadingZeroNotAllowedInPatch() {
        SemanticVersion sv = SemanticVersion.parse('2.3.04');
        System.assertEquals(null, sv);
    }
    
    @isTest static void zeroByItselfIsAllowed() {
        System.assertEquals(0, SemanticVersion.parse('0.3.4').getMajor());
        System.assertEquals(0, SemanticVersion.parse('2.0.4').getMinor());
        System.assertEquals(0, SemanticVersion.parse('2.3.0').getPatch());
    }
    
    @isTest static void canParseVersionWithMajorOnly() {
        SemanticVersion sv = SemanticVersion.parse('2');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(0, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithMajorAndMinorOnly() {
        SemanticVersion sv = SemanticVersion.parse('2.3');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithMajorAndPrereleaseOnly() {
        SemanticVersion sv = SemanticVersion.parse('2-beta1');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(0, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals('beta1', sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithMajorMinorAndPrereleaseOnly() {
        SemanticVersion sv = SemanticVersion.parse('2.3-beta1');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals('beta1', sv.getPrerelease());
        System.assertEquals(null, sv.getBuild());
    }
    
    @isTest static void canParseVersionWithMajorAndBuildOnly() {
        SemanticVersion sv = SemanticVersion.parse('2+build1');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(0, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals('build1', sv.getBuild());
    }
    
    @isTest static void canParseVersionWithMajorMinorAndBuildOnly() {
        SemanticVersion sv = SemanticVersion.parse('2.3+build1');
        System.assertEquals(2, sv.getMajor());
        System.assertEquals(3, sv.getMinor());
        System.assertEquals(0, sv.getPatch());
        System.assertEquals(null, sv.getPrerelease());
        System.assertEquals('build1', sv.getBuild());
    }
    
    @isTest static void majorVersionMustBeNumeric() {
        System.assertEquals(null, SemanticVersion.parse('x.0.0'));
    }
    
    @isTest static void minorVersionMustBeNumeric() {
        System.assertEquals(null, SemanticVersion.parse('0.x.0'));
    }
    
    @isTest static void patchVersionMustBeNumeric() {
        System.assertEquals(null, SemanticVersion.parse('0.0.x'));
    }
    
    @isTest static void equalVersionsHaveEqualPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1');
        System.assertEquals(0, sv1.compare(sv2));

        SemanticVersion sv3 = SemanticVersion.parse('2.3.4');
        SemanticVersion sv4 = SemanticVersion.parse('2.3.4');
        System.assertEquals(0, sv3.compare(sv4));
    }
    
    @isTest static void lowerMajorVersionHasLowerPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('1.3.4-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }
    
    @isTest static void lowerMinorVersionHasLowerPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('2.2.4-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }
    
    @isTest static void lowerPatchVersionHasLowerPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.3-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }
    
    @isTest static void prereleaseVersionHasLowerPrecedenceThanRelease() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }

    @isTest static void shorterSubsetOfPrereleaseIdentifiersHasLowerPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1.rc1');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }
    
    @isTest static void numericPrereleaseIdentifiersAreSortedNumerically() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1.3');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1.23');
        System.assertEquals(-1, sv1.compare(sv2));
        System.assertEquals(1, sv2.compare(sv1));
    }
    
    @isTest static void nonNumericPrereleaseIdentifiersAreSortedAsStrings() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1.x3');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1.x23');
        System.assertEquals(1, sv1.compare(sv2));
        System.assertEquals(-1, sv2.compare(sv1));
    }
    
    @isTest static void numericPrereleaseIdentifiersAreLowerThanStrings() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1.x.100');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1.3.100');
        System.assertEquals(1, sv1.compare(sv2));
        System.assertEquals(-1, sv2.compare(sv1));
    }
    
    @isTest static void buildIdentifierDoesNotAffectPrecedence() {
        SemanticVersion sv1 = SemanticVersion.parse('2.3.4-beta1+build1');
        SemanticVersion sv2 = SemanticVersion.parse('2.3.4-beta1+build2');
        System.assertEquals(0, sv1.compare(sv2));
        System.assertEquals(0, sv2.compare(sv1));
    }
}

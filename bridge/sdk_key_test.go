package main

import (
	"net/http"
	"strings"
	"testing"
)

// TestResolveSDKKeyTrimsSurroundingWhitespace covers the shape a key usually arrives in
// when it comes from a file or a secret mount: correct, with a trailing newline. That key
// works, so the bridge has to accept it rather than refuse to start.
func TestResolveSDKKeyTrimsSurroundingWhitespace(t *testing.T) {
	const want = "sdk-11111111-2222-3333-4444-555555555555"

	for _, raw := range []string{want + "\n", "\n" + want, " " + want + " \t\n", want} {
		setEnv(t, "LD_SDK_KEY", raw)

		got, err := resolveSDKKey()
		if err != nil {
			t.Fatalf("resolveSDKKey() for %q returned %v, want the trimmed key", raw, err)
		}
		if got != want {
			t.Errorf("resolveSDKKey() for %q = %q, want %q", raw, got, want)
		}
	}
}

// TestResolveSDKKeyRefusesAnUnsendableKey covers a key holding a character no header can
// carry. net/http refuses such a header on its own, but the error it returns has quoted
// the rejected value on some Go versions, and both LaunchDarkly-bound call sites log that
// error -- which writes the SDK key to the log. The bridge refuses at startup instead.
//
// The assertion that matters is the second one: whatever the message says, it must not
// repeat the key.
func TestResolveSDKKeyRefusesAnUnsendableKey(t *testing.T) {
	const secret = "sdk-DEADBEEF"

	// Every control character here is interior, or is one trimming does not remove. A
	// trailing newline or vertical tab is whitespace, so TrimSpace takes it and the key
	// that remains is sendable -- which is the case above, not a refusal.
	//
	// A NUL byte is absent on purpose: os.Setenv refuses one, so LD_SDK_KEY can never
	// carry it. isSendableHeaderValue is tested against NUL directly instead.
	for _, raw := range []string{
		secret + "\nX-Injected: 1",
		secret + "\rmore",
		secret + "\vmore",
		secret + "\x7f",
	} {
		setEnv(t, "LD_SDK_KEY", raw)

		got, err := resolveSDKKey()
		if err == nil {
			t.Fatalf("resolveSDKKey() accepted %q, returning %q", raw, got)
		}
		if strings.Contains(err.Error(), secret) {
			t.Errorf("error for %q leaks the key: %v", raw, err)
		}
		if !strings.Contains(err.Error(), "LD_SDK_KEY") {
			t.Errorf("error for %q does not name the variable: %v", raw, err)
		}
	}
}

// A key that is only whitespace is the same as no key at all, since trimming leaves
// nothing to send.
func TestResolveSDKKeyTreatsWhitespaceAsUnset(t *testing.T) {
	for _, raw := range []string{"", " ", "\n", "\t\n "} {
		setEnv(t, "LD_SDK_KEY", raw)

		if _, err := resolveSDKKey(); err == nil {
			t.Errorf("resolveSDKKey() accepted %q, want the unset error", raw)
		}
	}
}

func TestResolveSDKKeyReportsAnUnsetVariable(t *testing.T) {
	unsetEnv(t, "LD_SDK_KEY")

	_, err := resolveSDKKey()
	if err == nil {
		t.Fatal("resolveSDKKey() accepted an unset LD_SDK_KEY")
	}
	if !strings.Contains(err.Error(), "LD_SDK_KEY") {
		t.Errorf("error does not name the variable: %v", err)
	}
}

// TestIsSendableHeaderValueMatchesNetHTTP pins the predicate against the authority it is
// copied from. A rule that drifts from net/http's is worse than no rule: too strict
// refuses a key that would have worked, and too loose lets one reach the logging path
// this change exists to close.
func TestIsSendableHeaderValueMatchesNetHTTP(t *testing.T) {
	values := []string{
		"sdk-11111111-2222-3333-4444-555555555555",
		"plain",
		"with space",
		"with\ttab",
		"trailing\n",
		"embedded\nnewline",
		"carriage\rreturn",
		"null\x00byte",
		"delete\x7fbyte",
		"vertical\vtab",
		"highÿbyte",
		"",
	}

	for _, v := range values {
		request, err := http.NewRequest("GET", "http://127.0.0.1:1/", nil)
		if err != nil {
			t.Fatalf("building a request failed: %v", err)
		}

		request.Header.Set("Authorization", v)

		// A transport error other than the header check would make this meaningless, so
		// the comparison is on the specific message net/http uses for an invalid value.
		_, doErr := (&http.Client{}).Do(request)
		acceptedByNetHTTP := doErr == nil ||
			!strings.Contains(doErr.Error(), "invalid header field value")

		if got := isSendableHeaderValue(v); got != acceptedByNetHTTP {
			t.Errorf("isSendableHeaderValue(%q) = %v, net/http accepts it = %v (%v)",
				v, got, acceptedByNetHTTP, doErr)
		}
	}
}

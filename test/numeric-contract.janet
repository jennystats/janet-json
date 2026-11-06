# numeric-contract.janet - the number contract: every encoder output for a
# number re-scans (scan-number) to the same double, integral doubles keep
# every digit, DBL_MAX stays inside the double range, -0 keeps its sign,
# and decode refuses literals outside the double range.
(import ../jennystats/json)

(defn assert-eq [a b msg]
  (unless (deep= a b) (errorf "FAIL %s: %q != %q" msg a b)))

(defn assert-msg [thunk needle lbl]
  (var msg nil)
  (try (thunk) ([e] (set msg e)))
  (assert msg (string lbl ": must throw"))
  (assert (not (nil? (string/find needle msg)))
          (string lbl ": message must contain \"" needle "\", got: " (string msg))))

(def dbl-max 1.7976931348623157e308)

# every encoding re-scans to the same double
(defn rt [x] (scan-number (json/encode x)))
(each x @[1 2.5 0.1 1e-7 1e300 1e308 dbl-max
          9007199254740991 9007199254740992 -9007199254740992
          (json/decode "9007199254740993") (json/decode "1e308")
          (json/decode "123456789012345678901") 18014398509481984 1e15 1e16]
  (assert-eq (rt x) x (string "encode re-scans to the same double: " (json/encode x))))

# integral doubles: exact integer tokens, digits kept above 2^53
(assert-eq (json/encode 100.0) "100" "integral value below 2^53 encodes without a fraction")
(assert-eq (json/encode 18014398509481984) "18014398509481984" "integral value below 2^53 keeps an exact token")
(assert-eq (json/encode 9007199254740992) "9007199254740992" "2^53 keeps its exact integer token")
(assert-eq (rt 9007199254740992) 9007199254740992 "2^53 round-trips exactly")
(assert-eq (rt (json/decode "9007199254740993")) (json/decode "9007199254740993")
           "2^53+1 text round-trips to the same double")

# DBL_MAX: 17 digits, still inside the double range
(assert-eq (json/decode "1.7976931348623157e308") dbl-max "DBL_MAX text decodes")
(assert-eq (json/encode dbl-max) "1.7976931348623157e+308" "DBL_MAX encodes as its 17-digit form")
(assert-eq (rt dbl-max) dbl-max "the DBL_MAX text parses back to the same double")
(assert-eq (json/encode (json/decode "1.7976931348623155e308")) "1.7976931348623155e+308"
           "the last-below-max double keeps 17 digits")
(assert-eq (json/decode "1.7976931348623155e308") 1.7976931348623155e308
           "the last in-range text decodes to its exact double")
(assert-eq (json/decode "-1.7976931348623157e308") (- dbl-max) "negative DBL_MAX decodes")

# large and small magnitude spellings
(assert-eq (json/encode (json/decode "1e300")) "1e+300" "large exponent round-trips")
(assert-eq (json/encode (json/decode "1e308")) "1e+308" "1e308 round-trips")
(assert-eq (json/encode (json/decode "1e15")) "1e+15" "1e15 uses the shortest form")

# decode refuses literals outside the double range
(assert-msg (fn [] (json/decode "1e400")) "number out of range" "1e400 refused")
(assert-msg (fn [] (json/decode "-1e400")) "number out of range" "-1e400 refused")
(assert-msg (fn [] (json/decode "123e456")) "number out of range" "123e456 refused")
(assert-msg (fn [] (json/decode "1.79769313486232e+308")) "number out of range"
            "a literal past DBL_MAX is refused")

# -0 keeps its sign through encode and decode
(assert-eq (/ 1 (json/decode "-0")) (- math/inf) "decode -0 is a real negative zero")
(assert-eq (json/encode (json/decode "-0")) "-0" "negative zero encodes -0")
(assert-eq (json/encode (json/decode "-0.0")) "-0" "decode -0.0 is the same double")

(print "numeric contract ok")

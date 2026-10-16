(import ../json)

(defn assert-eq [a b msg]
  (unless (deep= a b) (errorf "FAIL %s: %q != %q" msg a b)))

# scalars
(assert-eq (json/decode "123") 123 "int")
(assert-eq (json/decode "-2.5") -2.5 "negative float")
(assert-eq (json/decode "1e3") 1000 "exponent")
(assert-eq (json/decode "true") true "true")
(assert-eq (json/decode "false") false "false")
(assert-eq (json/decode "null") :null "null -> :null")

# containers, nesting, whitespace
(assert-eq (json/decode "[]") @[] "empty array")
(assert-eq (json/decode "{}") @{} "empty object")
(assert-eq (json/decode "[1, [2, [3]]]") @[1 @[2 @[3]]] "nested arrays")
(assert-eq (json/decode "{\"a\": {\"b\": [1, 2]}}") @{"a" @{"b" @[1 2]}} "nested obj")
(assert-eq (json/decode " [ 1 ,\n\t2 ] ") @[1 2] "whitespace")

# strings and escapes
(assert-eq (json/decode "\"hi\"") "hi" "plain string")
(assert-eq (json/decode "\"a\\\"b\\\\c\\n\\t\\r\\/\\b\\f\"")
           "a\"b\\c\n\t\r/\b\f" "std escapes")
(assert-eq (json/decode "\"\\u0041\\u00e9\\u4e2d\"") "Aé中" "bmp \\u escapes")
(assert-eq (json/decode "\"\\uD83D\\uDE00\"") "\xF0\x9F\x98\x80" "surrogate pair")

# errors: bad input must error, not silently pass
(var caught false)
(try (json/decode "{\"a\":}") ([e] (set caught true)))
(assert caught "unterminated value errors")
(set caught false)
(try (json/decode "[1,2") ([e] (set caught true)))
(assert caught "unterminated array errors")
(set caught false)
(try (json/decode "12 34") ([e] (set caught true)))
(assert caught "trailing garbage errors")
(set caught false)
(try (json/decode "\"\\q\"") ([e] (set caught true)))
(assert caught "bad escape errors")
(set caught false)
(try (json/decode 123) ([e] (set caught (not (nil? (string/find "expected string, buffer" e))))))
(assert caught "non-bytes input errors with clear message")

# decode error paths - malformed input must throw the module's own
# errors, with the module's own messages (position included)
(defn assert-decode-error [input needle lbl]
  (var msg nil)
  (try (json/decode input) ([e] (set msg e)))
  (assert msg (string lbl ": decode must throw"))
  (assert (not (nil? (string/find needle msg)))
          (string lbl ": message must contain \"" needle "\", got: " (string msg))))

(assert-decode-error "" "unexpected end of input" "empty input")
(assert-decode-error "  \n\t" "unexpected end of input" "whitespace-only input")
(assert-decode-error "{\"a\":" "unexpected end of input" "input truncated after a colon")
(assert-decode-error "[1,2" "unterminated array" "truncated array")
(assert-decode-error "{\"a\":1" "unterminated object" "truncated object")
(assert-decode-error "tru" "bad number" "truncated literal")
(assert-decode-error "\"abc" "unterminated string at index 0" "unterminated string")
(assert-decode-error "\"\\q\"" "bad escape \\q" "bad escape")
(assert-decode-error "\"\\uZZZZ\"" "bad \\u escape at index 2" "non-hex \\u escape")
# regression: a truncated \u escape used to leak a raw Janet slice error
# ("end index 7 out of range") - hex4 sliced past the end before its guard
(assert-decode-error "\"\\u12\"" "bad \\u escape" "truncated \\u escape")
(assert-decode-error "\"\\uD800\"" "lone surrogate at index 1" "lone high surrogate")
(assert-decode-error "\"\\uDC00\"" "lone surrogate at index 1" "lone low surrogate")
(assert-decode-error "\"\\uD800\\u0041\"" "bad surrogate pair" "bad surrogate pair")
(assert-decode-error "1.2.3" "bad number at index 0" "malformed number")
(assert-decode-error "-" "bad number" "bare minus sign")
(assert-decode-error "{1:2}" "expected object key at index 1" "non-string object key")
(assert-decode-error "{\"a\" 1}" "expected ':' at index 5" "missing colon")
(assert-decode-error "{\"a\":1 2}" "expected ',' or '}' at index 7" "missing object separator")
(assert-decode-error "[1 2]" "expected ',' or ']' at index 3" "missing array separator")
(assert-decode-error "12 34" "trailing garbage at index 3" "trailing garbage is positioned")
# regression: a trailing backslash used to leak a raw format error
# ("bad slot #1, expected 32 bit signed integer, got nil")
(assert-decode-error "\"ab\\" "unterminated string" "trailing backslash")

# encode: scalars
(assert-eq (json/encode 1) "1" "encode int (no .0)")
(assert-eq (json/encode 2.5) "2.5" "encode float shortest")
(assert-eq (json/encode 0.1) "0.1" "encode 0.1 shortest")
(assert-eq (json/encode true) "true" "encode true")
(assert-eq (json/encode :null) "null" "encode :null")
(assert-eq (json/encode nil) "null" "encode nil")
(assert-eq (json/encode "s") "\"s\"" "encode string")
(assert-eq (json/encode "a\"b\\c\n") "\"a\\\"b\\\\c\\n\"" "encode escapes")
(assert-eq (json/encode :tag) "\"tag\"" "encode keyword -> name")

# encode: containers, determinism, ordering
(assert-eq (json/encode [1 "a" nil]) "[1,\"a\",null]" "encode array")
(assert-eq (json/encode {:z 1 :a 2}) "{\"a\":2,\"z\":1}" "sorted keys")
(assert-eq (json/encode @{:nested [true :null]}) "{\"nested\":[true,null]}" "nested encode")

# round trips
(def doc-data {"name" "jenny" "nums" [1 2.5] "inner" {"ok" true "miss" :null}})
(assert-eq (freeze (json/decode (json/encode doc-data))) doc-data "round trip (string keys; JSON normalizes keyword keys to strings)")
(set caught false)
(try (json/encode math/nan) ([e] (set caught true)))
(assert caught "NaN errors")

# encode edge cases
(var enc-err nil)
(try (json/encode math/inf) ([e] (set enc-err e)))
(assert (not (nil? (string/find "cannot encode Infinity" enc-err)))
        "Infinity errors with a clear message")
(set enc-err nil)
(try (json/encode (- math/inf)) ([e] (set enc-err e)))
(assert (not (nil? (string/find "cannot encode -Infinity" enc-err)))
        "-Infinity errors with a clear message")
(set enc-err nil)
(try (json/encode (fiber/new (fn []))) ([e] (set enc-err e)))
(assert (not (nil? (string/find "cannot encode" enc-err)))
        "unencodable types error with a clear message")
(set enc-err nil)
(try (json/encode @{1 "a"}) ([e] (set enc-err e)))
(assert (not (nil? (string/find "object keys must be strings or keywords" enc-err)))
        "non-string object keys error")
(assert-eq (json/encode "\x01") "\"\\u0001\"" "encode a control char as \\u escape")
(assert-eq (json/encode @"buf") "\"buf\"" "encode a buffer as a string")
(assert-eq (json/encode @[]) "[]" "encode an empty array")
(assert-eq (json/encode @{}) "{}" "encode an empty table")
(assert-eq (json/encode -0.5) "-0.5" "encode a negative float")

# decode accepts the whole bytes family, not just strings
(assert-eq (json/decode @"[1]") @[1] "decode buffer input")
(assert-eq (json/decode :null) :null "decode keyword input")
(assert-eq (json/decode (symbol "123")) 123 "decode symbol input")

(print "json smoke ok")

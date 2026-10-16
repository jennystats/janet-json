# json.janet - pure-Janet JSON encode/decode, spork-compatible.
# License: AGPLv3 (see LICENSE in the package root).
#
# Why pure Janet (short): no native module, no C toolchain, core stdlib
# only - runs anywhere Janet does. Full rationale in the README.
#
# Semantics (spork-compatible, documented):
#   decode: object → table, array → array, string → string,
#           true/false → boolean, null → :null, numbers → doubles.
#   encode: string/buffer → escaped string, boolean → true/false,
#           nil or :null → null, keyword → its name as a JSON string,
#           array/tuple → array, table/struct → object (keys sorted for
#           deterministic output; keys must be strings or keywords),
#           number → shortest round-tripping form (integers without ".0").
#   NaN/Infinity cannot be encoded (error) - JSON has no representation.

(defn- hex4 [s i]
  # [codepoint end-index] of a \uXXXX escape; i points at 'u'. The slice
  # end is clamped so a truncated escape reaches the length guard below
  # instead of a raw out-of-range error from string/slice.
  (def hex (string/slice s (+ i 1) (min (+ i 5) (length s))))
  (when (not= 4 (length hex)) (errorf "json: bad \\u escape at index %d" i))
  (def cp (scan-number (string "0x" hex)))
  (when (nil? cp) (errorf "json: bad \\u escape at index %d" i))
  [cp (+ i 5)])

(defn- utf8 [cp]
  (cond
    (< cp 0x80) (string/from-bytes cp)
    (< cp 0x800) (string/from-bytes (bor 0xC0 (brshift cp 6))
                                     (bor 0x80 (band cp 0x3F)))
    (< cp 0x10000) (string/from-bytes (bor 0xE0 (brshift cp 12))
                                      (bor 0x80 (band (brshift cp 6) 0x3F))
                                      (bor 0x80 (band cp 0x3F)))
    (string/from-bytes (bor 0xF0 (brshift cp 18))
                       (bor 0x80 (band (brshift cp 12) 0x3F))
                       (bor 0x80 (band (brshift cp 6) 0x3F))
                       (bor 0x80 (band cp 0x3F)))))

(defn- skip-ws [s i]
  (def n (length s))
  (var j i)
  (while (and (< j n) (def c (get s j)) (or (= c 32) (= c 9) (= c 10) (= c 13)))
    (++ j))
  j)

(defn- parse-string-body [s i]
  # i points at the opening quote → [string next-index]
  (label exit
    (def n (length s))
    (var j (+ i 1))
    (def acc @"")
    (while (< j n)
      (def c (get s j))
      (cond
        (= c 34) (return exit [(string acc) (+ j 1)])
        (= c 92)
        (do
          (def e (get s (+ j 1)))
          # a backslash at end of input ends the string - the errorf below
          # would otherwise feed nil to %c
          (when (nil? e) (errorf "json: unterminated string at index %d" i))
          (cond
            (= e 117)
            (do
              (def [cp nj] (hex4 s (+ j 1)))
              (def low-escape (and (>= cp 0xD800) (<= cp 0xDBFF)
                                   (= 92 (get s nj)) (= 117 (get s (+ nj 1)))))
              (if low-escape
                (do
                  (def [lo end] (hex4 s (+ nj 1)))
                  (unless (and (>= lo 0xDC00) (<= lo 0xDFFF))
                    (errorf "json: bad surrogate pair at index %d" j))
                  (buffer/push-string acc
                    (utf8 (+ 0x10000 (* 0x400 (- cp 0xD800)) (- lo 0xDC00))))
                  (set j end))
                (do
                  (when (and (>= cp 0xD800) (<= cp 0xDFFF))
                    (errorf "json: lone surrogate at index %d" j))
                  (buffer/push-string acc (utf8 cp))
                  (set j nj))))
            (do
              (buffer/push-string acc
                (case e 34 "\"" 92 "\\" 98 "\b" 102 "\f" 110 "\n" 114 "\r" 116 "\t" 47 "/"
                  (errorf "json: bad escape \\%c" e)))
              (set j (+ j 2)))))
        (do (buffer/push-byte acc c) (++ j))))
    (errorf "json: unterminated string at index %d" i)))

(defn- parse-number-body [s i]
  (def n (length s))
  (var j i)
  (while (and (< j n) (def c (get s j))
              (or (and (>= c 48) (<= c 57))
                  (= c 43) (= c 45) (= c 46) (= c 101) (= c 69)))
    (++ j))
  (def num (scan-number (string/slice s i j)))
  (when (nil? num) (errorf "json: bad number at index %d" i))
  [num j])

(defn- parse-object [s j pv]
  # j points at '{' → [table next-index]; pv is the value parser (mutual rec)
  (label exit
    (def n (length s))
    (def t @{})
    (var k (skip-ws s (+ j 1)))
    (when (and (< k n) (= (get s k) 125)) (return exit [t (+ k 1)]))
    (while true
      (when (or (>= k n) (not= (get s k) 34))
        (errorf "json: expected object key at index %d" k))
      (def [key nk] (parse-string-body s k))
      (def colon (skip-ws s nk))
      (when (or (>= colon n) (not= (get s colon) 58))
        (errorf "json: expected ':' at index %d" colon))
      (def [val nv] (pv s (+ colon 1)))
      (put t key val)
      (def after (skip-ws s nv))
      (when (>= after n) (errorf "json: unterminated object"))
      (case (get s after)
        44 (set k (skip-ws s (+ after 1)))
        125 (return exit [t (+ after 1)])
        (errorf "json: expected ',' or '}' at index %d" after)))
    (error "json: unreachable")))

(defn- parse-array [s j pv]
  # j points at '[' → [array next-index]
  (label exit
    (def n (length s))
    (def a @[])
    (var k (skip-ws s (+ j 1)))
    (when (and (< k n) (= (get s k) 93)) (return exit [a (+ k 1)]))
    (while true
      (def [val nv] (pv s k))
      (array/push a val)
      (def after (skip-ws s nv))
      (when (>= after n) (errorf "json: unterminated array"))
      (case (get s after)
        44 (set k (skip-ws s (+ after 1)))
        93 (return exit [a (+ after 1)])
        (errorf "json: expected ',' or ']' at index %d" after)))
    (error "json: unreachable")))

(defn- bounded-prefix? [s j word]
  # bounded prefix check - NEVER (string/slice s j) unbounded here: that
  # copies the whole tail per scalar and makes decode quadratic
  (def wl (length word))
  (def n (length s))
  (and (<= (+ j wl) n)
       (= word (string/slice s j (+ j wl)))))

(defn- parse-value [s i]
  # → [value next-index]
  (def j (skip-ws s i))
  (def n (length s))
  (when (>= j n) (errorf "json: unexpected end of input"))
  (def c (get s j))
  (cond
    (= c 123) (parse-object s j parse-value)
    (= c 91) (parse-array s j parse-value)
    (= c 34) (parse-string-body s j)
    (bounded-prefix? s j "true") [true (+ j 4)]
    (bounded-prefix? s j "false") [false (+ j 5)]
    (bounded-prefix? s j "null") [:null (+ j 4)]
    (parse-number-body s j)))

(defn decode [s]
  # JSON text (string/buffer/keyword/symbol) → Janet data.
  # Trailing garbage is an error.
  (unless (or (string? s) (buffer? s) (keyword? s) (symbol? s))
    (errorf "json/decode: expected string, buffer, keyword or symbol, got %v" (type s)))
  (def str (string s))
  (def [v i] (parse-value str 0))
  (def end (skip-ws str i))
  (unless (= end (length str))
    (errorf "json: trailing garbage at index %d" end))
  v)

(defn- enc-string-body [x]
  (def acc @"\"")
  (each c (string x)
    (cond
      (= c 34) (buffer/push-string acc "\\\"")
      (= c 92) (buffer/push-string acc "\\\\")
      (= c 8) (buffer/push-string acc "\\b")
      (= c 12) (buffer/push-string acc "\\f")
      (= c 10) (buffer/push-string acc "\\n")
      (= c 13) (buffer/push-string acc "\\r")
      (= c 9) (buffer/push-string acc "\\t")
      (< c 32) (buffer/push-string acc (string/format "\\u%04x" c))
      (buffer/push-byte acc c)))
  (buffer/push-string acc "\"")
  (string acc))

(defn- enc-float-loop [x]
  # shortest form that round-trips, by ascending precision
  (var out nil)
  (loop [prec :range [1 18] :until out]
    (def s (string/format (string "%." prec "g") x))
    (when (= (scan-number s) x) (set out s)))
  (or out (string/format "%.17g" x)))

(defn- enc-float-body [x]
  # shortest round-trip form: %.15g first, then %.16g, %.17g - %g strips
  # trailing zeros and 17 digits always round-trip a double, so one pass
  # covers typical data. Subnormal tail (<1e-309): the ulp outgrows the
  # 15-digit decimal spacing there, so that rare range keeps the loop.
  (if (< (math/abs x) 1e-309)
    (enc-float-loop x)
    (let [s15 (string/format "%.15g" x)]
      (if (= (scan-number s15) x)
        s15
        (let [s16 (string/format "%.16g" x)]
          (if (= (scan-number s16) x)
            s16
            (string/format "%.17g" x)))))))

(defn- enc-number-body [x]
  (cond
    (not= x x) (error "json: cannot encode NaN")
    (= x math/inf) (error "json: cannot encode Infinity")
    (= x (- math/inf)) (error "json: cannot encode -Infinity")
    (= x (math/floor x)) (string (math/trunc x))
    (enc-float-body x)))

(defn- encode-body [v]
  (cond
    (or (string? v) (buffer? v)) (enc-string-body v)
    (= v true) "true"
    (= v false) "false"
    (or (nil? v) (= v :null)) "null"
    (number? v) (enc-number-body v)
    (keyword? v) (enc-string-body (string v))
    (or (array? v) (tuple? v))
    (string "[" (string/join (map encode-body v) ",") "]")
    (or (table? v) (struct? v))
    (let [ks (sort (keys v))]
      (unless (all (fn [k] (or (string? k) (keyword? k))) ks)
        (error "json: object keys must be strings or keywords"))
      (string "{"
              (string/join
                (map (fn [k] (string (enc-string-body (if (keyword? k) (string k) k))
                                     ":"
                                     (encode-body (get v k))))
                     ks)
              ",")
              "}"))
    (errorf "json: cannot encode %v" (type v))))

(defn encode [v] (encode-body v))

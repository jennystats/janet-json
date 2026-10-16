# float-encode-cases.janet - byte-exact regression pins for the number
# encoder (json.janet enc-float-body): a %.15g/16g/17g cascade above
# 1e-309, the ascending loop below it. Breaks if string/format or
# scan-number rounding ever changes in the Janet core.
(import ../json)

(defn assert-bytes [x want msg]
  (def got (json/encode x))
  (unless (= got want)
    (errorf "FAIL %s: %q != %q" msg got want))
  (unless (= (scan-number got) x)
    (errorf "FAIL %s: %q does not round-trip" msg got)))

# cascade: one pass, the %.15g form round-trips
(assert-bytes 0.1 "0.1" "15-digit minimal")
(assert-bytes 2.5 "2.5" "15-digit minimal")

# cascade: minimal form needs 16, then 17 significant digits
(assert-bytes (+ 0.1 0.7) "0.7999999999999999" "16-digit minimal")
(assert-bytes (+ 0.1 0.2) "0.30000000000000004" "17-digit minimal")
(assert-bytes 123456.78901234567 "123456.78901234567" "17-digit minimal, fixed style")

# guard boundary: 1e-309 and up take the cascade, below keeps the loop
(assert-bytes 1e-309 "1e-309" "boundary, cascade side")
(assert-bytes 5e-310 "5e-310" "boundary, loop side")

# the subnormal tail must stay shortest, not cascade-overshot
(assert-bytes 5e-324 "5e-324" "smallest subnormal")
(assert-bytes 1.5e-323 "1.5e-323" "subnormal tail")
(assert-bytes 1e-320 "1e-320" "subnormal tail")
(assert-bytes -5e-324 "-5e-324" "negative subnormal tail")

(print "float encode cases ok")

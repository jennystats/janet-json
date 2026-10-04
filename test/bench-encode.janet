# bench-encode.janet - number-encode cost by value class, min-of-5.
# Run from the package root: janet test/bench-encode.janet
# Fixtures are seeded, so runs are comparable across code versions.
(import ../json)

(def n 10000)
(math/seedrandom "json-bench")

# typical decimals: 2 decimal places, minimal forms of a few digits
(def decimals (seq [i :range [0 n]] (/ (mod (* i 37) 100000) 100)))
# full-mantissa doubles: arbitrary 53-bit mantissas, minimal forms of
# 16-17 significant digits
(def full-mantissa
  (seq [i :range [0 n]] (* (math/random) (math/pow 10 (mod i 12)))))
# integers: never reach the float path
(def integers (seq [i :range [0 n]] (mod (* i 13) 100000)))

(defn- single-pass [xs]
  # one %.17g format per number: the single-pass reference cost
  (string "[" (string/join (map |(string/format "%.17g" $) xs) ",") "]"))

(defn- time-min5 [f]
  # one timed run = enough calls to last >= 40ms; report the min of 5
  (def t0 (os/clock))
  (f)
  (def per-call (max (- (os/clock) t0) 1e-7))
  (def reps (max 1 (math/floor (/ 0.04 per-call))))
  (var best math/inf)
  (loop [_ :range [0 5]]
    (def start (os/clock))
    (loop [_ :range [0 reps]] (f))
    (set best (min best (/ (- (os/clock) start) reps))))
  best)

(printf "n = %d values per fixture, min of 5 timed runs\n" n)
(printf "%-14s %12s %12s %8s\n" "fixture" "single-pass" "json/encode" "ratio")
(each [name xs] [["decimals" decimals] ["full-mantissa" full-mantissa] ["integers" integers]]
  (def t-single (time-min5 (fn [] (single-pass xs))))
  (def t-mod (time-min5 (fn [] (json/encode xs))))
  (printf "%-14s %10.2fms %10.2fms %7.2fx\n"
          name (* 1000 t-single) (* 1000 t-mod) (/ t-mod t-single)))
(print "ratio = json/encode vs one %.17g format per number")

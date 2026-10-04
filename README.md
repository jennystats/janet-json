# janet-json

JSON encode/decode in plain Janet - one .janet file, no native module, no
build step. It runs anywhere Janet does, including statically-linked
Janet binaries where the usual native-module route has pitfalls.

Part of [Jenny Stats](https://github.com/jennystats), a home for Janet
data and statistics packages. Jenny is just Janet.

Core stdlib only. Developed and tested on Janet 1.42.

## Usage

```janet
(import json)

(json/decode "{\"a\": [1, 2.5], \"b\": null}")
# -> @{"a" @[1 2.5] "b" :null}

(json/encode {:z 1 :a [true nil]})
# -> "{\"a\":[true,null],\"z\":1}"
```

Spork-compatible semantics, documented:

- decode: object → table, array → array, string → string, true/false →
  boolean, null → `:null`, numbers → doubles.
- encode: keyword → its name as a JSON string; nil or `:null` → `null`;
  array/tuple → array; table/struct → object with **sorted keys**
  (deterministic output); numbers → shortest round-tripping form
  (integers without `.0`). NaN/Infinity error - JSON has no representation.

Decode accepts string, buffer, keyword, or symbol input; trailing garbage
is an error.

## Why pure Janet?

spork's json is a native module: C, and by default built linked against
`libjanet.so`. On a Janet that itself runs from that shared library,
this is one runtime and everything works as intended. On a
statically-linked Janet binary, though, that build brings in a *second*
Janet runtime alongside the host - separate state and GC - and values
crossing between them come out corrupt.

The same C can also be built without linking `libjanet.so`, so that it
binds to the host's exported API instead; spork's `json.c` built that way
passes this module's full test suite and decodes an order of magnitude
faster than pure Janet. If a C toolchain is available and the payloads
are large, that is the better tool for the job.

This module is the other side of that trade-off: plain Janet, core stdlib
only, bundles as source, nothing to build. For utility-scale JSON that is
a good trade-off - and the whole module is short enough to read in one
go.

## Alternatives

- **[spork/json](https://github.com/janet-lang/spork)** - the reference C
  module. Fast, but a jpm-built native artifact (see "Why pure Janet?"
  for the static-binary caveat).
- **[janet-json-pure](https://github.com/Techcable/janet-json-pure)**
  (Techcable, unlisted) - a ~100-line PEG-based pure-Janet decoder. Its
  PEG decode measured ~4-5x faster than this module's on a 700KB fixture
  (2026-10-02), and its contract is Janet-native rather than
  spork-compatible (keyword keys, `nil` for null). Its encoder is
  ASCII-only and its errors carry no position.
- **[medea](https://github.com/pyrmont/medea)** (pyrmont, unlisted) - a
  PEG-based pure-Janet encoder/decoder with a CLI, by the author of
  testament. Its decode contract is the closest sibling to this module's:
  string keys, arrays, `:null` (spork-compatible shapes). Errors are
  generic ("invalid JSON"). Its encode offers pretty-printing, which this
  module does not.
- **[janet-json](https://github.com/jennystats/janet-json)** (this module)
  differs from the above in deterministic encoding (sorted keys,
  shortest round-trip floats, full UTF-8), positioned error messages,
  and a test suite with byte-exact encode pins.

## Install

Clone anywhere, then either:

**Import by path** - zero setup, works everywhere:

```janet
(import "/path/to/janet-json/json")
```

**Or make the module importable by name** - if you keep a Janet module
directory, symlink the file into it:

```bash
git clone https://github.com/jennystats/janet-json janet-json
ln -s "$(pwd)/janet-json/json.janet" /your/janet/module/dir
```

Then `(import json)` works everywhere.

**Or with jpm** - installs into your module path:

```bash
jpm install https://github.com/jennystats/janet-json
```

## Tests

Run from the repo root; the tests use module-relative imports and need
no setup.

```bash
janet test/smoke-json.janet
janet test/float-encode-cases.janet
```

`test/bench-encode.janet` measures number-encode cost by value class
(min of 5 timed runs); it is a benchmark, not a test.

## License

GPLv3 - see `LICENSE`.

## AI assistance

The code in this repository was written with the assistance of a large
language model and reviewed by its maintainer.

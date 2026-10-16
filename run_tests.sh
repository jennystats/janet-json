#!/bin/sh
# run_tests.sh - janet-json smoke suite (conformance + float encode cases);
# runs from the repo root.
if janet test/smoke-json.janet && janet test/float-encode-cases.janet; then
  echo "RESULT: pass"
else
  echo "RESULT: fail"
  exit 1
fi

-- View output of telemetry 3cd1ad8 (before the host layer) for the states
-- in tests/core/view_spec.lua. The pure views must write the same bytes.
return {
  ["live_40_color"] = "\27[?25l\27[1mtest\27[0m \27[31m███████████\27[0m\27[2m░░░░░░░░░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spec.lua\27[0m\
    \27[2m描述 a 很長的測試名稱 that is far …\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m   tests 3 passed,…\27[0m\
\27[4F\27[J\27[1mtest\27[0m \27[31m███████████\27[0m\27[2m░░░░░░░░░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spec.lua\27[0m\
    \27[2m描述 a 很長的測試名稱 that is far …\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m   tests 3 passed,…\27[0m\
\27[4F\27[J\27[31mFAIL\27[0m tests/失敗_spec.lua (1m01s) exit=1\
\27[31mFail\27[0m line\
second\
  \27[31merror\27[0m: 壞掉 test\
\27[31mtimed out\27[0m\
\27[1mtest\27[0m \27[31m███████████\27[0m\27[2m░░░░░░░░░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spec.lua\27[0m\
    \27[2m描述 a 很長的測試名稱 that is far …\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m   tests 3 passed,…\27[0m\
\27[4F\27[J\27[31m1 of 2 test suites passed (2m05s).\27[0m\
Tests: 3 passed, 1 failed.\
Failed: tests/失敗_spec.lua\
\27[33mInterrupted.\27[0m\
\27[?25h",
  ["live_40_mono"] = "\27[?25ltest ███████████░░░░░░░░░░░░ 2/4  1m15s\
  ▶ tests/中文名稱_spec.lua\
    描述 a 很長的測試名稱 that is far …\
  1 passed  1 failed   tests 3 passed,…\
\27[4F\27[Jtest ███████████░░░░░░░░░░░░ 2/4  1m15s\
  ▶ tests/中文名稱_spec.lua\
    描述 a 很長的測試名稱 that is far …\
  1 passed  1 failed   tests 3 passed,…\
\27[4F\27[JFAIL tests/失敗_spec.lua (1m01s) exit=1\
Fail line\
second\
  error: 壞掉 test\
timed out\
test ███████████░░░░░░░░░░░░ 2/4  1m15s\
  ▶ tests/中文名稱_spec.lua\
    描述 a 很長的測試名稱 that is far …\
  1 passed  1 failed   tests 3 passed,…\
\27[4F\27[J1 of 2 test suites passed (2m05s).\
Tests: 3 passed, 1 failed.\
Failed: tests/失敗_spec.lua\
Interrupted.\
\27[?25h",
  ["live_24_color"] = "\27[?25l\27[1mtest\27[0m \27[31m███\27[0m\27[2m░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spe…\27[0m\
    \27[2m描述 a 很長的測試…\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m  …\27[0m\
\27[4F\27[J\27[1mtest\27[0m \27[31m███\27[0m\27[2m░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spe…\27[0m\
    \27[2m描述 a 很長的測試…\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m  …\27[0m\
\27[4F\27[J\27[31mFAIL\27[0m tests/失敗_spec.lua (1m01s) exit=1\
\27[31mFail\27[0m line\
second\
  \27[31merror\27[0m: 壞掉 test\
\27[31mtimed out\27[0m\
\27[1mtest\27[0m \27[31m███\27[0m\27[2m░░░░\27[0m 2/4  1m15s\
  \27[36m▶ tests/中文名稱_spe…\27[0m\
    \27[2m描述 a 很長的測試…\27[0m\
  \27[32m1 passed\27[0m  \27[31m1 failed\27[0m\27[2m  …\27[0m\
\27[4F\27[J\27[31m1 of 2 test suites passed (2m05s).\27[0m\
Tests: 3 passed, 1 failed.\
Failed: tests/失敗_spec.lua\
\27[33mInterrupted.\27[0m\
\27[?25h",
  ["plain"] = "ok tests/ok_spec.lua (1.2s)\
TIMEOUT tests/中文_spec.lua (3.0s) exit=-1 signal=9\
Fail\9||\9outer\
  fail: x\
timed out after 300 ms\
1 of 2 test suites passed (4.0s).\
Tests: 1 passed, 1 failed.\
Failed: tests/中文_spec.lua\
",
  ["plain_github"] = "ok tests/ok_spec.lua (1.2s)\
TIMEOUT tests/中文_spec.lua (3.0s) exit=-1 signal=9\
::group::tests/中文_spec.lua output\
Fail\9||\9outer\
  fail: x\
timed out after 300 ms\
::endgroup::\
::error::tests/中文_spec.lua failed\
1 of 2 test suites passed (4.0s).\
Tests: 1 passed, 1 failed.\
Failed: tests/中文_spec.lua\
",
}

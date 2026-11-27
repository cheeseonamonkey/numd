version     = "0.1.0"
author      = "cheeseonamonkey"
description = "Configurable Num Lock modifier and numpad shortcut daemon"
license     = "MIT"
srcDir      = "src"
bin         = @["numd", "numd-config"]
backend     = "c"

requires "nim >= 2.2.0"
requires "ngum >= 0.3.0"

task test, "run unit tests":
  exec "nim c -r --hints:off --out:build/core-tests tests/test_core.nim"

task dist, "build Debian package":
  exec "nim c -d:release --hints:off --out:build/numd src/numd.nim"
  exec "build/numd --check config/numd.ini"
  exec "bash packaging/build-deb.sh 0.1.0"

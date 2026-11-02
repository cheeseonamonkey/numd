import std/[unittest, tables]
import ../src/core

suite "numd":
  test "tap preserves Num Lock":
    var m = initMapper(initTable[int, seq[int]]())
    check m.handle(NumLock, 1).len == 0
    check m.handle(NumLock, 0) == @[(NumLock, 1), (NumLock, 0)]

  test "ordinary numpad events pass through":
    var m = initMapper(initTable[int, seq[int]]())
    check m.handle(71, 1) == @[(71, 1)]
    check m.handle(71, 2) == @[(71, 2)]
    check m.handle(71, 0) == @[(71, 0)]

  test "held layer produces a chord without toggling Num Lock":
    var map = initTable[int, seq[int]]()
    map[71] = parseChord("ctrl+alt+7")
    var m = initMapper(map)
    discard m.handle(NumLock, 1)
    check m.handle(71, 1) == @[(29, 1), (56, 1), (8, 1),
                                (8, 0), (56, 0), (29, 0)]
    check m.handle(71, 2).len == 0
    check m.handle(NumLock, 0).len == 0
    check m.handle(71, 0).len == 0

  test "key released after Num Lock still has suppressed release":
    var map = initTable[int, seq[int]]()
    map[71] = parseChord("super+left")
    var m = initMapper(map)
    discard m.handle(NumLock, 1)
    discard m.handle(71, 1)
    discard m.handle(NumLock, 0)
    check m.handle(71, 0).len == 0
    check m.handle(71, 1) == @[(71, 1)]

  test "unmapped chord cancels Num Lock tap but passes key":
    var m = initMapper(initTable[int, seq[int]]())
    discard m.handle(NumLock, 1)
    check m.handle(80, 1) == @[(80, 1)]
    check m.handle(NumLock, 0).len == 0

  test "bad bindings are rejected":
    expect ValueError: discard parseChord("ctrl+nonsense")
    expect ValueError: discard parseChord("ctrl+ctrl+x")
    expect ValueError: discard parseChord("a+b")
    expect ValueError: discard parseChord("ctrl")

  test "example config parses every binding":
    let settings = loadSettings("config/numd.ini")
    check settings.device == "auto"
    check settings.bindings.len == 11
    check settings.bindings[71] == parseChord("super+7")
    check settings.bindings[82] == parseChord("ctrl+alt+t")

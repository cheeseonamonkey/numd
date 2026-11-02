## Pure mapping and event state; Linux I/O lives in numd.nim.
import std/[parsecfg, strutils, tables, sets]

const NumLock* = 69

type
  Stroke* = tuple[code: int, value: int]
  Settings* = object
    device*: string
    bindings*: Table[int, seq[int]]
  Mapper* = object
    bindings*: Table[int, seq[int]]
    numHeld*: bool
    used*: bool
    suppressed: HashSet[int]

proc keyCode*(name: string): int =
  let n = name.toLowerAscii().strip()
  case n
  of "ctrl", "leftctrl": 29
  of "shift", "leftshift": 42
  of "alt", "leftalt": 56
  of "super", "meta", "win", "leftmeta": 125
  of "rightctrl": 97
  of "rightshift": 54
  of "rightalt": 100
  of "rightmeta": 126
  of "left": 105
  of "right": 106
  of "up": 103
  of "down": 108
  of "home": 102
  of "end": 107
  of "pageup": 104
  of "pagedown": 109
  of "enter", "return": 28
  of "esc", "escape": 1
  of "space": 57
  of "tab": 15
  of "backspace": 14
  of "delete": 111
  of "insert": 110
  of "print", "printscreen": 99
  of "numlock": NumLock
  of "kp0": 82
  of "kp1": 79
  of "kp2": 80
  of "kp3": 81
  of "kp4": 75
  of "kp5": 76
  of "kp6": 77
  of "kp7": 71
  of "kp8": 72
  of "kp9": 73
  of "kpdot": 83
  of "kpenter": 96
  of "kpplus": 78
  of "kpminus": 74
  of "kpslash": 98
  of "kpasterisk": 55
  else:
    if n.len == 1:
      const letters = [30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38,
                       50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44]
      const digits = [11, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      if n[0] in {'a'..'z'}: return letters[ord(n[0]) - ord('a')]
      if n[0] in {'0'..'9'}: return digits[ord(n[0]) - ord('0')]
    if n.len in 2..3 and n[0] == 'f':
      try:
        let f = parseInt(n[1..^1])
        if f in 1..10: return 58 + f
        if f == 11: return 87
        if f == 12: return 88
      except ValueError: discard
    raise newException(ValueError, "unknown key: " & name)

proc parseChord*(s: string): seq[int] =
  let parts = s.split('+')
  if parts.len == 0: raise newException(ValueError, "empty binding")
  for i, part in parts:
    let code = keyCode(part)
    if i < parts.high and code notin [29, 42, 56, 125, 97, 54, 100, 126]:
      raise newException(ValueError, "only modifiers may precede the final key: " & s)
    if code in result:
      raise newException(ValueError, "duplicate key in binding: " & s)
    result.add(code)
  if result[^1] in [29, 42, 56, 125, 97, 54, 100, 126]:
    raise newException(ValueError, "binding needs a non-modifier key: " & s)

proc loadSettings*(path: string): Settings =
  let cfg = loadConfig(path)
  result.device = cfg.getSectionValue("device", "path", "auto").strip()
  if result.device.len == 0: raise newException(ValueError, "device.path is empty")
  result.bindings = initTable[int, seq[int]]()
  if cfg.hasKey("bindings"):
    for key, chord in cfg["bindings"].pairs:
      let source = keyCode(key)
      if source notin [71, 72, 73, 75, 76, 77, 79, 80, 81, 82, 83, 96, 98, 55, 74, 78]:
        raise newException(ValueError, "binding source must be a numpad key: " & key)
      result.bindings[source] = parseChord(chord)

proc initMapper*(bindings: Table[int, seq[int]]): Mapper =
  Mapper(bindings: bindings, suppressed: initHashSet[int]())

proc handle*(m: var Mapper, code, value: int): seq[Stroke] =
  ## EV_KEY values: 1=press, 0=release, 2=repeat.
  if code == NumLock:
    if value == 1 and not m.numHeld:
      m.numHeld = true
      m.used = false
    elif value == 0 and m.numHeld:
      if not m.used:
        result.add((NumLock, 1))
        result.add((NumLock, 0))
      m.numHeld = false
    return

  if code in m.suppressed:
    if value == 0: m.suppressed.excl(code)
    return

  if m.numHeld and value == 1:
    m.used = true
    if m.bindings.hasKey(code):
      m.suppressed.incl(code)
      let chord = m.bindings[code]
      for k in chord: result.add((k, 1))
      for i in countdown(chord.high, 0): result.add((chord[i], 0))
      return

  result.add((code, value))

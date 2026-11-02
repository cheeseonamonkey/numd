## Linux evdev -> uinput numpad layer. Standard library only.
import std/[os, strutils, algorithm, tables]
import posix
import core

const
  EvKey = 1'u16
  EvSyn = 0'u16
  SynReport = 0'u16
  EvIocGrab = 0x40044590'u64
  UiSetEvBit = 0x40045564'u64
  UiSetKeyBit = 0x40045565'u64
  UiDevSetup = 0x405c5503'u64
  UiDevCreate = 0x5501'u64
  UiDevDestroy = 0x5502'u64
  KeyMax = 0x2ff

type
  LinuxTimeval = object
    sec, usec: clong
  InputEvent = object
    timestamp: LinuxTimeval
    kind, code: uint16
    value: int32
  InputId = object
    busType, vendor, product, version: uint16
  UinputSetup = object
    id: InputId
    name: array[80, char]
    ffEffectsMax: uint32

proc ioctlArg(fd: cint, request: culong, arg: pointer): cint
  {.importc: "ioctl", header: "<sys/ioctl.h>", varargs.}

proc callIoctl(fd: cint, request: uint64, arg: int): cint =
  ioctlArg(fd, culong(request), cast[pointer](arg))

proc send(fd: cint, kind, code: uint16, value: int32) =
  var ev = InputEvent(kind: kind, code: code, value: value)
  if posix.write(fd, addr ev, sizeof(ev)) != sizeof(ev):
    raise newException(IOError, "failed to write virtual keyboard event")

proc emit(fd: cint, key: Stroke) =
  send(fd, EvKey, uint16(key.code), int32(key.value))
  send(fd, EvSyn, SynReport, 0)

proc createKeyboard(): cint =
  let fd = posix.open("/dev/uinput", O_WRONLY or O_NONBLOCK or O_CLOEXEC)
  if fd < 0:
    raise newException(IOError, "cannot open /dev/uinput (load uinput module and run with input permissions)")
  try:
    if callIoctl(fd, UiSetEvBit, int(EvKey)) != 0 or
       callIoctl(fd, UiSetEvBit, int(EvSyn)) != 0:
      raise newException(IOError, "cannot set uinput event types")
    for code in 1..KeyMax:
      if callIoctl(fd, UiSetKeyBit, code) != 0:
        raise newException(IOError, "cannot set uinput key " & $code)

    var setup = UinputSetup(id: InputId(busType: 0x03, vendor: 0x1, product: 0x1, version: 1))
    const label = "numd virtual keyboard"
    for i, c in label: setup.name[i] = c
    if ioctlArg(fd, culong(UiDevSetup), addr setup) != 0 or
       callIoctl(fd, UiDevCreate, 0) != 0:
      raise newException(IOError, "failed to create virtual keyboard")
    sleep(150) # allow udev/libinput to discover the device
    result = fd
  except:
    discard posix.close(fd)
    raise

proc findKeyboard(device: string): string =
  if device != "auto": return device
  for directory in ["/dev/input/by-id", "/dev/input/by-path"]:
    if not dirExists(directory): continue
    var choices: seq[string]
    for _, path in walkDir(directory):
      if not path.endsWith("-event-kbd"): continue
      choices.add(path)
    choices.sort()
    if choices.len > 0: return choices[0]

proc run(settings: Settings) =
  let outFd = createKeyboard()
  defer:
    discard callIoctl(outFd, UiDevDestroy, 0)
    discard posix.close(outFd)

  var lastMissing = ""
  while true:
    let path = findKeyboard(settings.device)
    if path.len == 0:
      if path != lastMissing:
        stderr.writeLine("numd: waiting for keyboard: " & (if path.len > 0: path else: settings.device))
        lastMissing = path
      sleep(2000)
      continue

    let fd = posix.open(path.cstring, O_RDONLY or O_CLOEXEC)
    if fd < 0:
      stderr.writeLine("numd: cannot open " & path & "; retrying")
      sleep(2000)
      continue

    if callIoctl(fd, EvIocGrab, 1) != 0:
      stderr.writeLine("numd: cannot grab " & path & " (another remapper may own it)")
      discard posix.close(fd)
      sleep(2000)
      continue

    stderr.writeLine("numd: grabbed " & path)
    var mapper = initMapper(settings.bindings)
    lastMissing = ""
    while true:
      var ev: InputEvent
      let n = posix.read(fd, addr ev, sizeof(ev))
      if n != sizeof(ev): break
      if ev.kind != EvKey: continue
      for stroke in mapper.handle(int(ev.code), int(ev.value)):
        emit(outFd, stroke)

    discard callIoctl(fd, EvIocGrab, 0)
    discard posix.close(fd)
    stderr.writeLine("numd: keyboard disconnected; reconnecting")
    sleep(500)

when isMainModule:
  let args = commandLineParams()
  if args.len > 0 and args[0] in ["-h", "--help"]:
    echo "Usage: numd [--check] [config-path]"
    echo "Default: /etc/numd/config.ini"
    quit(0)
  if args.len > 0 and args[0] == "--version":
    echo "numd 0.1.0"
    quit(0)
  let checkOnly = args.len > 0 and args[0] == "--check"
  let configPath = if args.len > (if checkOnly: 1 else: 0):
                     args[if checkOnly: 1 else: 0]
                   else: "/etc/numd/config.ini"
  try:
    let settings = loadSettings(configPath)
    if settings.device != "auto" and not settings.device.isAbsolute:
      raise newException(ValueError, "device.path must be absolute or auto")
    if checkOnly:
      echo "OK: ", settings.bindings.len, " bindings, device=", settings.device
    else:
      run(settings)
  except CatchableError as e:
    stderr.writeLine("numd: " & e.msg)
    quit(1)

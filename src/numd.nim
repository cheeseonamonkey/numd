## Linux evdev -> uinput numpad layer and command-line management interface.
import std/[os, strutils, algorithm, tables, osproc]
import posix
import core
import numdconfig

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

proc usage() =
  echo """numd — Num Lock numpad shortcuts

Usage:
  numd setup                 configure and enable the system service
  numd config [config-file]  edit bindings in the ngum TUI
  numd status                show daemon status
  numd start|stop|restart    control the service
  numd enable|disable        enable/disable service at boot
  numd logs                  follow service logs
  numd devices               list keyboard devices
  numd check [config-file]   validate configuration
  numd run [config-file]     run the daemon in the foreground
  numd help

Run `sudo numd setup` once after installing the package.
"""

proc systemctl(args: seq[string]): int =
  if findExe("systemctl").len == 0:
    raise newException(IOError, "systemctl not found; this command requires systemd")
  let process = startProcess("systemctl", args = args,
                             options = {poUsePath, poParentStreams})
  result = process.waitForExit()
  process.close()

proc listDevices() =
  var found = false
  for directory in ["/dev/input/by-id", "/dev/input/by-path"]:
    if not dirExists(directory): continue
    for _, path in walkDir(directory):
      if path.endsWith("-event-kbd"):
        echo path
        found = true
  if not found:
    echo "No keyboard symlinks found under /dev/input/by-id or /dev/input/by-path."

proc checkConfig(path: string) =
  let settings = loadSettings(path)
  if settings.device != "auto" and not settings.device.isAbsolute:
    raise newException(ValueError, "device.path must be absolute or auto")
  echo "OK: ", settings.bindings.len, " bindings, device=", settings.device

proc runSetup() =
  if geteuid() != 0:
    raise newException(IOError, "setup needs root; run: sudo numd setup")
  if not fileExists("/etc/numd/config.ini"):
    raise newException(IOError, "missing /etc/numd/config.ini; reinstall the numd package")
  if not fileExists("/usr/lib/systemd/system/numd.service") and
     not fileExists("/etc/systemd/system/numd.service"):
    raise newException(IOError, "service unit missing; install the numd package first")

  if not runTui("/etc/numd/config.ini"):
    echo "Setup cancelled; service unchanged."
    return

  if not fileExists("/dev/uinput"):
    if findExe("modprobe").len == 0:
      raise newException(IOError, "modprobe not found; load the uinput module manually")
    let moduleLoad = startProcess("modprobe", args = ["uinput"],
                                  options = {poUsePath, poParentStreams})
    let status = moduleLoad.waitForExit()
    moduleLoad.close()
    if status != 0 or not fileExists("/dev/uinput"):
      raise newException(IOError, "could not load uinput kernel module")

  if systemctl(@["daemon-reload"]) != 0 or
     systemctl(@["enable", "--now", "numd"]) != 0:
    raise newException(IOError, "systemd setup failed; inspect `systemctl status numd`")
  echo "numd is enabled and running. Hold Num Lock and press a configured numpad key."

proc main(args: seq[string]) =
  if args.len == 0 or args[0] in ["help", "-h", "--help"]:
    usage()
    return
  if args[0] in ["version", "--version"]:
    echo "numd 0.1.0"
    return

  let command = args[0]
  let config = if args.len > 1: args[1] else: "/etc/numd/config.ini"
  case command
  of "setup":
    runSetup()
  of "config":
    if config == "/etc/numd/config.ini" and geteuid() != 0:
      raise newException(IOError, "editing the system config needs root; run: sudo numd config")
    if runTui(config) and config == "/etc/numd/config.ini" and
       systemctl(@["is-active", "--quiet", "numd"]) == 0:
      discard systemctl(@["restart", "numd"])
      echo "Service restarted with the saved configuration."
  of "check", "--check":
    checkConfig(config)
  of "run":
    run(loadSettings(config))
  of "devices":
    listDevices()
  of "status":
    quit(systemctl(@["status", "--no-pager", "numd"]))
  of "logs":
    if findExe("journalctl").len == 0:
      raise newException(IOError, "journalctl not found")
    let process = startProcess("journalctl", args = @["-u", "numd", "-f"],
                               options = {poUsePath, poParentStreams})
    quit(process.waitForExit())
  of "start", "stop", "restart", "enable", "disable":
    quit(systemctl(@[command, "numd"]))
  else:
    # Keep the old `numd [config-file]` invocation working for existing units.
    if command.isAbsolute:
      run(loadSettings(command))
    else:
      raise newException(ValueError, "unknown command: " & command & " (try `numd help`)")

when isMainModule:
  try:
    main(commandLineParams())
  except CatchableError as error:
    stderr.writeLine("numd: " & error.msg)
    quit(1)

import benchy
import os

timeIt "no cache":
  discard execShellCmd("nim c -f -d:nwtCacheOff -r testSpeed.nim")
  discard execShellCmd("nim c -f -d:nwtCacheOff -r testSpeedFile.nim")

timeIt "Cache":
  discard execShellCmd("nim c -f -r testSpeed.nim")
  discard execShellCmd("nim c -f -r testSpeedFile.nim")
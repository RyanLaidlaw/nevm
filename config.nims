import std/os

let home = getEnv("HOME")

if home.len > 0:
  --nimblePath: home / ".nimble/pkgs2"
  --nimblePath: home / ".nimble/pkgs"

--path: home / "MiniProjects/foundry_compilers_nim/src"

# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
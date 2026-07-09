# Package

version       = "0.1.0"
author        = "Ryan Laidlaw"
description   = "Mini EVM built in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["main"]


# Dependencies

requires "nim >= 2.2.10"
requires "clapfn"
requires "stint"
requires "nimcrypto"
requires "noise"
requires "foundry_compilers_nim"

when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
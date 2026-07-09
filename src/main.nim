import tables, json, os, strutils
import clapfn
import evm
import runner
import foundry_compilers_nim

proc hexToBytes(hexStr: string): Bytearray =
  var s = hexStr
  if s.startsWith("0x") or s.startsWith("0X"):
    s = s[2..^1]

  if s.len mod 2 != 0:
    raise newException(ValueError, "hex string has odd length: " & $s.len)

  result = newSeq[uint8](s.len div 2)
  for i in 0 ..< result.len:
    let byteStr = s[i*2 .. i*2+1]
    result[i] = uint8(parseHexInt(byteStr))

var parser = ArgumentParser(
    programName: "nevm",
    fullName: "Nim EVM",
    description: "Mini EVM written in Nim",
    version: "0.1.0"
)

parser.addRequiredArgument(name="project", help="Project to compile")

let args = parser.parse()
let absPath = expandFilename(args["project"])

let artifacts = compileSolidity(absPath).getFields()

var names: seq[string] = @[]
var bytecodes: seq[Bytearray] = @[]

for contract, info in artifacts:
    names.add(contract)
    bytecodes.add(hexToBytes(info["bytecode"]["object"].getStr()))

var accounts = initAccounts(names, bytecodes)

startEvm(accounts)

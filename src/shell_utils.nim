import strutils
import stint
import evm

type
    EncodedArg = object
        head: Bytearray
        tail: Bytearray

proc functionSelector*(signature: string): array[4, uint8] =
    let hash = keccak256(signature.toOpenArrayByte(0, signature.high))
    [hash[0], hash[1], hash[2], hash[3]]

proc encodeArg*(ty, value: string): EncodedArg =
    case ty
    of "uint256", "uint":
        let v = UInt256.fromDecimal(value)
        result.head = @(v.toBytesBE())
    of "address":
        var address = value
        if address.startsWith("0x") or address.startsWith("0X"):
            address = address[2..^1]
        var buf = newSeq[uint8](32)
        let raw = parseHexStr(address)
        assert raw.len == 20
        for i, c in raw:
            buf[12 + i] = uint8(c)
        result.head = buf
    of "bool":
        var buf = newSeq[uint8](32)
        buf[31] = if value == "true" or value == "1": 1'u8 else: 0'u8
        result.head = buf
    of "string":
        var bytes = newSeq[uint8](value.len)
        for i in 0 ..< value.len:
            bytes[i] = uint8(value[i])
        var lenBuf = newSeq[uint8](32)
        let lenVal = value.len.u256
        for i, b in lenVal.toBytesBE():
            lenBuf[i] = b
        var data = newSeq[uint8](value.len)
        for i in 0 ..< value.len:
            data[i] = bytes[i]
        while data.len mod 32 != 0:
            data.add(0'u8)
        result.head = newSeq[uint8](32)
        result.tail = lenBuf & data
    else:
        raise newException(ValueError, "unsupported type: " & ty)

proc encodeConstructorArgs*(argTypes: seq[string], args: seq[string]): Bytearray =
    var heads: seq[Bytearray] = @[]
    var tails: seq[Bytearray] = @[]

    for i in 0 ..< args.len:
        let encoded = encodeArg(argTypes[i], args[i])
        heads.add(encoded.head)
        tails.add(encoded.tail)

    let headSize = 32 * heads.len
    var currentOffset = headSize

    for i in 0 ..< heads.len:
        if tails[i].len > 0:
            var offsetBuf = newSeq[uint8](32)
            let offVal = currentOffset.u256
            for j, b in offVal.toBytesBE():
                offsetBuf[j] = b
            heads[i] = offsetBuf
            currentOffset += tails[i].len

    result = @[]
    for h in heads:
        result.add(h)
    for t in tails:
        result.add(t)

proc buildCalldata*(signature: string, argTypes: seq[string], args: seq[string]): Bytearray =
    var calldata = @(functionSelector(signature))

    var heads: seq[Bytearray] = @[]
    var tails: seq[Bytearray] = @[]

    for i in 0 ..< args.len:
        let encoded = encodeArg(argTypes[i], args[i])
        heads.add(encoded.head)
        tails.add(encoded.tail)

    let headSize = 32 * heads.len
    var currentOffset = headSize

    for i in 0 ..< heads.len:
        if tails[i].len > 0:
            var offsetBuf = newSeq[uint8](32)
            let offVal = currentOffset.u256
            let offBytes = offVal.toBytesBE()
            for j, b in offBytes:
                offsetBuf[j] = b
            heads[i] = offsetBuf
            currentOffset += tails[i].len

    for h in heads:
        calldata.add(h)
    for t in tails:
        calldata.add(t)

    result = calldata

proc decodeReturn*(ret: Bytearray, outputTypes: seq[string]): string =
    if ret.len == 0:
        return "()"

    if outputTypes.len == 0:
        var hex = "0x"
        for b in ret:
            hex.add(toHex(b, 2))
        return hex.toLowerAscii() & "  (no output types specified)"

    var outputs: seq[string] = @[]

    for i, ty in outputTypes:
        let headOffset = i * 32
        let head = ret[headOffset ..< headOffset + 32]

        case ty
        of "uint256", "uint":
            outputs.add($UInt256.fromBytesBE(head))
        of "bool":
            outputs.add($(head[31] == 1'u8))
        of "address":
            var s = "0x"
            for b in head[12..31]:
                s.add(toHex(b, 2))
            outputs.add(s.toLowerAscii())
        of "string":
            let offset = UInt256.fromBytesBE(head).truncate(int)
            let lenBytes = ret[offset ..< offset + 32]
            let strLen = UInt256.fromBytesBE(lenBytes).truncate(int)
            let dataStart = offset + 32
            let data = ret[dataStart ..< dataStart + strLen]
            var s = newString(strLen)
            for j in 0 ..< strLen:
                s[j] = char(data[j])
            outputs.add("\"" & s & "\"")
        else:
            outputs.add("<unsupported " & ty & ">")

    if outputs.len == 1:
        result = outputs[0]
    else:
        result = "(" & outputs.join(", ") & ")"

proc parseSignature*(sig: string): tuple[name: string, inputs: seq[string], outputs: seq[string]] =
    let openParen = sig.find('(')
    let name = sig[0 ..< openParen]
    let closeParen = sig.find(')', openParen)
    let inputsStr = sig[openParen+1 ..< closeParen]
    let inputs = if inputsStr.len == 0: @[] else: inputsStr.split(',')

    var outputs: seq[string] = @[]
    let secondOpen = sig.find('(', closeParen)
    if secondOpen != -1:
        let secondClose = sig.find(')', secondOpen)
        let outputsStr = sig[secondOpen+1 ..< secondClose]
        outputs = if outputsStr.len == 0: @[] else: outputsStr.split(',')

    result = (name: name, inputs: inputs, outputs: outputs)
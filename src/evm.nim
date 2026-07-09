import stint
import tables
import nimcrypto

const MSG_SENDER: UInt256 = 0xDEADBEEFDEADBEEF.u256
const CONTRACT_ADDRESS: UInt256 = 0xADDDECAFADDDECAF.u256
const CHAIN_ID: UInt256 = 0xBEEEEEF.u256

type
    Bytearray* = seq[uint8]

    Info = object
        code*: Bytearray
        storage*: Table[UInt256, UInt256]
        balance*: UInt256

    Name* = string
    Accounts* = Table[Name, Info]

    Evm* = object
        pc*: int
        stack*: seq[UInt256]
        memory*: Bytearray
        storage*: Table[Name, Table[UInt256, UInt256]]
        code*: Table[Name, Bytearray]
        halted*: bool
        calldata*: Bytearray
        callvalue*: UInt256
        balance*: Table[Name, UInt256]

    ExitKind* = enum
        Return
        Revert
        Stop
    ExitReason* = object
        case kind*: ExitKind
        of Return:
            returnBytes*: Bytearray
        of Revert:
            revertBytes*: Bytearray
        of Stop:
            discard


proc newInfo*(c: Bytearray): Info =
    result.code = c
    result.storage = initTable[UInt256, UInt256]()
    result.balance = 0'u256

proc initAccounts*(names: seq[Name], bytecodes: seq[Bytearray]): Accounts =
  assert names.len == bytecodes.len

  result = initTable[Name, Info]()
  
  for i, name in names:
    let code = bytecodes[i]
    result[name] = newInfo(code)
        
proc initEvm*(accounts: Accounts, calldata: Bytearray): Evm =
    result.pc = 0
    result.stack = @[]
    result.memory = @[]
    result.storage = initTable[Name, Table[UInt256, UInt256]]()
    result.code = initTable[Name, Bytearray]()
    result.halted = false
    result.calldata = calldata
    result.callvalue = UInt256.zero # TODO not 0
    result.balance = initTable[Name, UInt256]()
    
    for name, info in accounts:
        result.storage[name] = info.storage
        result.code[name] = info.code
        result.balance[name] = info.balance

proc popTwo(evm: var Evm): tuple[a: UInt256, b: UInt256] =
    let a = evm.stack.pop()
    let b = evm.stack.pop()
    return (a, b)

proc keccak256(data: openArray[uint8]): array[32, uint8] =
    var ctx: keccak256
    ctx.init()
    ctx.update(data)
    result = ctx.finish().data

proc ensureMemory(evm: var Evm, minLen: int) =
    if evm.memory.len < minLen:
        evm.memory.setLen(minLen)

const SIGN_BIT = 1.u256 shl 255

proc isNegative(x: UInt256): bool =
    x >= SIGN_BIT

proc twosComplementNegate(x: UInt256): UInt256 =
    (not x) + 1.u256

proc slt(a, b: UInt256): bool =
    let negA = isNegative(a)
    let negB = isNegative(b)
    if negA and not negB: return true
    if not negA and negB: return false
    return a < b
        
proc run*(evm: var Evm, storage: var Table[UInt256, UInt256], code: var Bytearray, balance: var UInt256): ExitReason =
    evm.pc = 0
    while not evm.halted:
        let opcode = code[evm.pc]
        evm.pc += 1

        case opcode:
        of 0x00:
            return ExitReason(kind: Stop)
        of 0x01:
            let (a, b) = evm.popTwo()
            evm.stack.add(a + b)
        of 0x02:
            let (a, b) = evm.popTwo()
            evm.stack.add(a * b)
        of 0x03:
            let (a, b) = evm.popTwo()
            evm.stack.add(a - b)
        of 0x04:
            let (a, b) = evm.popTwo()
            if b == UInt256.zero:
                evm.stack.add(UInt256.zero)
            else:
                evm.stack.add(a div b)
        of 0x05:
            let (a, b) = evm.popTwo()
            if b == 0.u256:
                evm.stack.add(0.u256)
            else:
                let negA = isNegative(a)
                let negB = isNegative(b)
                let absA = if negA: twosComplementNegate(a) else: a
                let absB = if negB: twosComplementNegate(b) else: b
                let q = absA div absB
                evm.stack.add(if negA != negB: twosComplementNegate(q) else: q)
        of 0x06:
            let (a, b) = evm.popTwo()
            evm.stack.add(a mod b)
        of 0x07:
            let (a, b) = evm.popTwo()
            if b == 0.u256:
                evm.stack.add(0.u256)
            else:
                let negA = isNegative(a)
                let absA = if negA: twosComplementNegate(a) else: a
                let absB = if isNegative(b): twosComplementNegate(b) else: b
                let r = absA mod absB
                evm.stack.add(if negA: twosComplementNegate(r) else: r)
        of 0x08:
            let (a, b) = evm.popTwo()
            let n = evm.stack.pop()
            if n == UInt256.zero:
                evm.stack.add(UInt256.zero)
            else:
                evm.stack.add((a + b) mod n)
        of 0x09:
            let (a, b) = evm.popTwo()
            let n = evm.stack.pop()
            if n == UInt256.zero:
                evm.stack.add(UInt256.zero)
            else:
                evm.stack.add((a * b) mod n)
        of 0x0A:
            let (a, b) = evm.popTwo()
            evm.stack.add(a.pow(b))
        of 0x10:
            let (a, b) = evm.popTwo()
            evm.stack.add(if a < b: UInt256.one else: UInt256.zero)
        of 0x11:
            let (a, b) = evm.popTwo()
            evm.stack.add(if a > b: UInt256.one else: UInt256.zero)
        of 0x12:
            let (a, b) = evm.popTwo()
            evm.stack.add(if slt(a, b): 1.u256 else: 0.u256)
        of 0x13:
            let (a, b) = evm.popTwo()
            evm.stack.add(if slt(b, a): 1.u256 else: 0.u256)  
        of 0x14:
            let (a, b) = evm.popTwo()
            evm.stack.add(if a == b: UInt256.one else: UInt256.zero)
        of 0x15:
            let a = evm.stack.pop()
            evm.stack.add(if a == UInt256.zero: UInt256.one else: UInt256.zero)
        of 0x16:
            let (a, b) = evm.popTwo()
            evm.stack.add(a and b)
        of 0x17:
            let (a, b) = evm.popTwo()
            evm.stack.add(a or b)
        of 0x18:
            let (a, b) = evm.popTwo()
            evm.stack.add(a xor b)
        of 0x19:
            let a = evm.stack.pop()
            evm.stack.add(not a)
        of 0x1A:
            let (i, x) = evm.popTwo()
            if i >= 32.u256:
                evm.stack.add(UInt256.zero)
            else:
                let index = i.truncate(int)
                let shift = 8 * (31 - index)
                let b = (x shr shift) and UInt256.fromHex("0xFF")
                evm.stack.add(b)
        of 0x1B:
            let (shift, value) = evm.popTwo()
            if shift >= 256.u256:
                evm.stack.add(UInt256.zero)
            else:
                let shiftInt = shift.truncate(int)
                evm.stack.add(value shl shiftInt)
        of 0x1C:
            let (shift, value) = evm.popTwo()
            if shift >= 256.u256:
                evm.stack.add(UInt256.zero)
            else:
                let shiftInt = shift.truncate(int)
                evm.stack.add(value shr shiftInt)
        of 0x20:
            let (offset, length) = evm.popTwo()
            let off = offset.truncate(int)
            let len = length.truncate(int)

            evm.ensureMemory(off + 32)

            var data = newSeq[uint8](len)
            for j in 0 ..< len:
                let idx = off + j
                if idx < evm.memory.len:
                    data[j] = evm.memory[idx]

            let hash = keccak256(data)
            let value = UInt256.fromBytesBE(hash)
            evm.stack.add(value)
        of 0x30:
            evm.stack.add(CONTRACT_ADDRESS)
        of 0x32:
            evm.stack.add(MSG_SENDER)
        of 0x33:
            evm.stack.add(MSG_SENDER)
        of 0x34:
            evm.stack.add(evm.callvalue)
        of 0x35:
            let offset = evm.stack.pop().truncate(int)
            var buffer = newSeq[uint8](32)

            for j in 0 .. 31:
                if offset + j < evm.calldata.len():
                    buffer[j] = evm.calldata[offset + j]

            let value = UInt256.fromBytesBE(buffer)
            evm.stack.add(value)
        of 0x36:
            evm.stack.add(evm.calldata.len().u256)
        of 0x37:
            let dest_offset = evm.stack.pop().truncate(int)
            let offset = evm.stack.pop().truncate(int)
            let size = evm.stack.pop().truncate(int)

            evm.ensureMemory(dest_offset + size)

            for i in 0 ..< size:
                if offset + i < evm.calldata.len():
                    evm.memory[dest_offset + i] = evm.calldata[offset + i]
                else:
                    evm.memory[dest_offset + i] = 0
        of 0x39:
            let dest_offset = evm.stack.pop().truncate(int)
            let offset = evm.stack.pop().truncate(int)
            let size = evm.stack.pop().truncate(int)

            evm.ensureMemory(dest_offset + size)

            for i in 0 ..< size:
                if offset + i < evm.code.len():
                    evm.memory[dest_offset + i] = code[offset + i]
                else:
                    evm.memory[dest_offset + i] = 0
        of 0x43:
            evm.stack.add(0.u256)
        of 0x46:
            evm.stack.add(CHAIN_ID)
        of 0x47:
            evm.stack.add(balance)
        of 0x48:
            evm.stack.add(1.u256)
        of 0x50:
            discard evm.stack.pop()
        of 0x51:
            let offset = evm.stack.pop().truncate(int)

            evm.ensureMemory(offset + 32)
            
            var buffer = newSeq[uint8](32)
            for i in 0..31:
                buffer[i] = evm.memory[offset + i]
            
            let value = UInt256.fromBytesBE(buffer)
            evm.stack.add(value)
        of 0x52:
            let offset = evm.stack.pop().truncate(int)
            let value = evm.stack.pop()

            evm.ensureMemory(offset + 32)

            let buffer = value.toBytesBE()
            for i in 0..31:
                evm.memory[offset + i] = buffer[i]
        of 0x53:
            let offset = evm.stack.pop().truncate(int)
            let value = evm.stack.pop()
            evm.ensureMemory(offset + 32)
            evm.memory[offset] = value.truncate(uint8)
        of 0x54:
            let key = evm.stack.pop()
            let value = storage[key]
            evm.stack.add(value)
        of 0x55:
            let (key, value) = evm.popTwo()
            if value == 0.u256:
                storage.del(key)
            else:
                storage[key] = value
        of 0x56:
            let counter = evm.stack.pop().truncate(int)
            if not (counter < code.len() and code[counter] == 0x5b):
                return ExitReason(kind: Revert, revertBytes: @[0x56])
            evm.pc = counter
        of 0x57:
            let counter_dest = evm.stack.pop().truncate(int)
            let condition = evm.stack.pop()

            if condition != 0.u256:
                if not (counter_dest < code.len() and code[counter_dest] == 0x5b):
                    return ExitReason(kind: Revert, revertBytes: @[0x56])
                evm.pc = counter_dest
        of 0x58:
            let pc = evm.pc - 1
            evm.stack.add(pc.u256)
        of 0x5b:
            # nothing
            continue
        of 0x5e:
            let dest_offset = evm.stack.pop().truncate(int)
            let offset = evm.stack.pop().truncate(int)
            let size = evm.stack.pop().truncate(int)
            evm.ensureMemory(dest_offset + size)
            for i in 0 ..< size:
                if offset + i < evm.memory.len():
                    evm.memory[dest_offset + i] = evm.memory[offset + i]
        of 0x5f:
            evm.stack.add(0.u256)
        of 0x60..0x7f:
            let n = int(opcode - 0x5f)
            
            let data = code[evm.pc ..< evm.pc + n]
            evm.pc += n

            var buffer = newSeq[uint8](32)
            buffer[32 - data.len() .. 31] = data
            evm.stack.add(UInt256.fromBytesBE(buffer))
        of 0x80..0x8f:
            let n = int(opcode - 0x7f)

            let value = evm.stack[evm.stack.len() - n]
            evm.stack.add(value)
        of 0x90..0x9f:
            let n = int(opcode - 0x7f)
            let len: int = evm.stack.len()

            swap(evm.stack[len - 1], evm.stack[len - 1 - n])
        of 0xf3:
            let offset = evm.stack.pop().truncate(int)
            let size = evm.stack.pop().truncate(int)
            let endOffset = offset + size

            evm.ensureMemory(offset + size)

            let data = evm.memory[offset ..< endOffset]
            return ExitReason(kind: Return, returnBytes: data)
        of 0xfd:
            let offset = evm.stack.pop().truncate(int)
            let size = evm.stack.pop().truncate(int)
            let endOffset = offset + size

            evm.ensureMemory(offset + size)

            let data = evm.memory[offset ..< endOffset]
            return ExitReason(kind: Revert, revertBytes: data)
        of 0xfe:
            return ExitReason(kind: Revert, revertBytes: @[0xfe])
        else:
            return ExitReason(kind: Stop)
    return ExitReason(kind: Stop)


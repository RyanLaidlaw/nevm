import tables, strutils
import evm
import shell_utils
import noise

proc tokenize(line: string): seq[string] =
    var tokens: seq[string] = @[]
    var i = 0
    while i < line.len:
        while i < line.len and line[i] == ' ': inc i
        if i >= line.len: break
        if line[i] == '"':
            inc i
            let start = i
            while i < line.len and line[i] != '"': inc i
            tokens.add(line[start ..< i])
            inc i
        else:
            let start = i
            while i < line.len and line[i] != ' ': inc i
            tokens.add(line[start ..< i])
    tokens

proc handleDeploy(accounts: var Accounts, tokens: seq[string]) =
    if tokens.len < 2:
        echo "usage: deploy <contract> [\"constructor(types)\" [args...]]"
        return

    let contractName = tokens[1]
    if not accounts.hasKey(contractName):
        echo "unknown contract: ", contractName
        return

    var info = accounts[contractName]
    var deployCode = info.code

    if tokens.len >= 3:
        let (_, inputTypes, _) = parseSignature(tokens[2])
        let ctorArgs = tokens[3 ..^ 1]

        if ctorArgs.len != inputTypes.len:
            echo "expected ", inputTypes.len, " constructor args, got ", ctorArgs.len
            return

        let encodedArgs = encodeConstructorArgs(inputTypes, ctorArgs)
        deployCode = deployCode & encodedArgs 

    var deployEvm = initEvm(accounts, @[])

    let exitReason = deployEvm.run(info.storage, deployCode, info.balance)

    case exitReason.kind
    of Return:
        info.code = exitReason.returnBytes
        accounts[contractName] = info
        echo contractName, " deployed"
    of Revert:
        echo "deployment reverted: ", exitReason.revertBytes
    of Stop:
        echo "deployment stopped with no return data"

proc handleCall(accounts: var Accounts, tokens: seq[string]) =
    if tokens.len < 3:
        echo "usage: call <contract> \"sig(types)\" [args...]"
        return

    let contractName = tokens[1]
    if not accounts.hasKey(contractName):
        echo "unknown contract: ", contractName
        return

    let (name, inputTypes, outputTypes) = parseSignature(tokens[2])
    let callArgs = tokens[3 ..^ 1]

    if callArgs.len != inputTypes.len:
        echo "expected ", inputTypes.len, " args, got ", callArgs.len
        return

    let fullSig = name & "(" & inputTypes.join(",") & ")"
    let calldata = buildCalldata(fullSig, inputTypes, callArgs)

    var evm = initEvm(accounts, calldata)
    let info = accounts[contractName]
    var storage = info.storage
    var code = info.code
    var balance = info.balance

    let exitReason = evm.run(storage, code, balance)
    accounts[contractName].storage = storage

    case exitReason.kind
    of Return:
        echo decodeReturn(exitReason.returnBytes, outputTypes)
    of Revert:
        echo "revert: ", exitReason.revertBytes
    of Stop:
        echo "()"

proc handleBalance(accounts: Accounts, tokens: seq[string]) =
    if tokens.len < 2:
        echo "usage: balance <contract>"
        return
    if not accounts.hasKey(tokens[1]):
        echo "unknown contract: ", tokens[1]
        return
    echo accounts[tokens[1]].balance

proc startEvm*(accounts: var Accounts) =
    var noise = Noise.init()
    noise.setPrompt(Styler.init(fgGreen, "nevm> "))

    while true:
        let ok = noise.readLine()
        if not ok:
            break

        let line = noise.getLine
        if line.len == 0:
            continue
        noise.historyAdd(line)

        let tokens = tokenize(line)
        case tokens[0]
        of "exit", "quit":
            break
        of "deploy":
            handleDeploy(accounts, tokens)
        of "call":
            handleCall(accounts, tokens)
        of "balance":
            handleBalance(accounts, tokens)
        of "contracts":
            for name, info in accounts.pairs:
                echo name
        of "help":
            echo "deploy <contract> [\"constructor(types)\" [args...]]   - deploy a contract"
            echo "call <contract> \"sig(types)\" [args...]               - call a contracts functions"
            echo "balance <contract>                                   - get the balance of a contract"
            echo "contracts                                            - get a list of all compiled contracts"
            echo "exit | quit                                          - close the shell"
        else:
            echo "unknown command: ", tokens[0]
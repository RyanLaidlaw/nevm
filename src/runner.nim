import tables
import evm

proc startEvm*(accounts: var Accounts) =
    var deploy_evm = initEvm(accounts, @[])
    
    for name, info in accounts.mpairs:
        let exitReason = deploy_evm.run(info.storage, info.code, info.balance)
        if exitReason.kind == Return:
            let bytes = exitReason.returnBytes
            accounts[name].code = bytes
    

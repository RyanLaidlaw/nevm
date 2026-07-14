# NEVM

This mini Ethereum Virtual Machine is based of the [Mini-EVM](https://github.com/RyanLaidlaw/Mini-EVM) project writtten in Rust with some added capabilities, namely:

- Compilation of a full project of Solidity files, using the [foundry_compilers_nim](https://github.com/RyanLaidlaw/foundry_compilers_nim) package.

- Shell-style interactive design, where users can deploy and interact with multiple contracts.

# Usage
```
nimble run -- {root directory}
```

For example, you can clone this project and run `nimble run -- test_files`.

```
nevm> help
deploy <contract> ["constructor(types)" [args...]]   - deploy a contract
call <contract> "sig(types)" [args...]               - call a contracts functions
balance <contract>                                   - get the balance of a contract
contracts                                            - get a list of all compiled contracts
exit | quit                                          - close the shell
```

When deploying a contract, use this format:

```
nevm> deploy Bank "constructor(uint256)" 10
Bank deployed
```

When interacting with a contract, use a similar format:

```
nevm> call Bank "deposit(uint256)" 5
()
nevm> call Bank "balance()(uint256)"
15
```
Where `()` is the param types and `(uint256)` is the return types.
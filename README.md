# AurellionPublic

Standalone Foundry regression harness for the public Diamond contracts.

## Layout

- `contracts/diamond/`: canonical contract source tree
- `test/diamond/`: focused regression and smoke suites
- `lib/forge-std/`: vendored Foundry test library
- `node_modules/@openzeppelin/`: vendored OpenZeppelin dependencies

## Run tests

Use offline mode when running locally:

```sh
forge test --offline
```

Target a single suite:

```sh
forge test --offline --match-contract AuditHighTest
```

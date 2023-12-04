# Pearl Token Project

## Overview
The Pearl Token Project is a Solidity-based smart contract suite designed for the Pearl cryptocurrency ecosystem. This advanced system includes the Pearl token, a governance model with vePEARL, and a migration mechanism for tokens. The project leverages OpenZeppelin's Universal Upgradeable Proxy Standard (UUPS) and Foundry for testing and deployment.

## Project Components

### Core Contracts (`src/`)
- **Directly under `src/`:**
  - `PearlMigrator.sol`: Handles migrations from legacy tokens.
- **Token Contracts (`src/token/`):**
  - `Pearl.sol`: ERC20 token contract with extended features for the Pearl token.
- **Governance Contracts (`src/governance/`):**
  - `VotingEscrow.sol`, `VotingEscrowVesting.sol`: Manage the governance system, including the vesting mechanism for vePEARL.

### Interfaces and Utilities (`src/interfaces/`, `src/utils/`)
- Define interactions between contracts and provide utility functionalities.

### User Interface (`src/ui/`)
- `VotingEscrowArtProxy.sol`: Related to UI components for governance.

### Governance (`src/governance/`)
- Contracts for implementing the voting and governance mechanisms of the Pearl ecosystem.

## Deployment and Scripts (`script/`)
- `DeployAll.s.sol`: Main deployment script for the contracts, including specific addresses and network aliases.
- `EmptyUUPS.sol` in `utils/`: Used for deploying UUPS upgradeable proxies.
- Deployment scripts include specific Foundry commands for execution.

## Testing Framework (`test/`)
- Comprehensive test suites for each contract, ensuring functionality and security.
- `mocks/`: Mock contracts simulate external dependencies for controlled testing.

## Getting Started
1. Clone the repository.
2. Install dependencies using Foundry.
3. Set up environment variables as per `.env.example`.
4. Execute test scripts to validate contract functionalities.
5. Run Foundry commands to deploy contracts. For example:
   ```
   FOUNDRY_PROFILE=optimized forge script script/DeployAllTestnet.s.sol --legacy --broadcast
   ```
6. Verify contracts. For example:
   ```
   FOUNDRY_PROFILE=optimized forge verify-contract 0xaBA5FF73Bec90ef637e3A75a205A7A084A651097 \
     --chain-id 18231 \
     --verifier blockscout \
     --verifier-url "https://unreal.blockscout.com/api" \
     --watch src/token/Pearl.sol:Pearl
   FOUNDRY_PROFILE=optimized forge verify-contract 0xa15d9b6cCA037B0d3BA7f76d9C38c13D6485F025 \
     --chain-id 5 \
     --verifier etherscan \
     --etherscan-api-key "<etherscan-key>" \
     --constructor-args $(
         cast abi-encode "constructor(uint256,address)" \
         18231 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23
       ) \
     --watch src/token/Pearl.sol:Pearl
   ```

## Current Deployment Addresses

### Mumbai
```
Pearl Migrator: 0x14cd7fACf3a215149377896FE58DaD019d72E002
```

### Unreal
```
Pearl:           0x1ef116600bBb2e99Ce6CE96B7E66A0df71AF5980
vePearl:         0xee60171b3A81EE2DF0caf0aAd894772B6Acaa772
vePearl Vesting: 0xA1Bc24d9043C364bF9BAc192ef9a46B8d8f24dCD
```

### Goerli
```
Pearl: 0x1ef116600bBb2e99Ce6CE96B7E66A0df71AF5980
```

## License
This project is licensed under MIT. See the `LICENSE` file for more details.

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
   FOUNDRY_PROFILE=optimized forge script script/DeployAllTestnet.s.sol --broadcast
   ```

## License
This project is licensed under MIT. See the `LICENSE` file for more details.

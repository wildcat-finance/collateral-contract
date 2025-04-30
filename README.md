# Wildcat Market Collateral Contracts

Smart contracts for managing credit line collateral within the Wildcat protocol. This implementation provides a mechanism for borrowers to deposit collateral that can be liquidated in case of delinquency.

## Overview

This repository contains Solidity smart contracts for collateral management in Wildcat markets:

- `WildcatMarketCollateral`: Core contract for collateral management
- `WildcatMarketCollateralFactory`: Factory contract for deploying collateral contracts
- `SimpleMarketCollateral`: Simplified collateral implementation
- `SimpleMarketCollateralMultiParty`: Multi-party collateral implementation

## SimpleMarketCollateralMultiParty

The `SimpleMarketCollateralMultiParty` contract is the core collateral management system designed for Wildcat markets with these key features:

### Purpose and Design
A collateral contract that supports multiple depositors providing collateral assets that can be liquidated when the underlying Wildcat market enters a penalized delinquency state. The contract integrates with Bebop PMM (Private Market Maker) for efficient liquidation processing.

### Key Functionality

- **Multi-Party Deposit System**: Allows multiple users to deposit collateral assets while maintaining individual accounting.
- **Share-Based Accounting**: Users receive shares equivalent to their deposit amounts, with internal accounting to track liquidations.
- **Liquidation Management**: Liquidations are processed through Bebop PMM by approved liquidators when markets enter penalized delinquency.
- **Liquidation Points**: Utilizes a dividend-like system (but for debits) to track the amount of collateral liquidated from each user's deposit.
- **Fair Distribution**: New depositors are not penalized for liquidations that occurred before their deposits.
- **Reclaim Mechanism**: Users can withdraw their remaining collateral once the underlying market is terminated.
- **Token Rescue**: Borrowers can rescue tokens mistakenly sent to the contract.

### Deployment through WildcatMarketCollateralFactory

The `WildcatMarketCollateralFactory` is responsible for deploying `SimpleMarketCollateralMultiParty` contracts using these key mechanisms:

- **Deterministic Deployment**: Uses Create2 for deterministic address generation, ensuring contracts can be located predictably.
- **Collateral Parameters**: Temporarily stores parameters (collateral token, associated market, borrower) in transient storage during deployment.
- **Deployment Process**:
  1. Market participants call `deployCollateralContract(collateralToken, associatedMarket)`
  2. Factory creates a unique salt based on the collateral token and associated market
  3. Factory verifies no duplicate contract exists for the same parameters
  4. Factory retrieves the borrower from the associated market
  5. Parameters are temporarily stored for the contract constructor to access
  6. Contract is deployed using LibStoredInitCode for efficient deployment
  7. Deployed contract is registered in the factory's tracking system

- **Contract Registry**: Maintains a mapping of deployed collateral contracts by market, allowing query functions like `listCollateralMarkets(market, asset)`
- **Liquidator Management**: Provides functions to approve and remove liquidators who can execute collateral liquidations

### Security Considerations

- The liquidation process carries an inherent risk where a malicious executor collaborating with a malicious maker on Bebop could potentially process liquidations at unfavorable prices.
- The contract does not support rebasing tokens or assets with non-standard transfer semantics due to its internal balance tracking approach.
- Liquidations are restricted by cooldown periods and maximum repayment limits to prevent abuse.

### Key Functions

- `deposit(uint256 _amount)`: Allows users to deposit collateral
- `liquidateCollateral(bytes, uint, uint, uint)`: Sells collateral to repay delinquent debt via Bebop PMM
- `reclaimCollateral()`: Allows users to reclaim their remaining collateral after market termination
- `getLiquidatedCollateral(address)`: Returns the total collateral that has been liquidated from an account
- `getReclaimableAmount(address)`: Returns the amount of collateral that can be reclaimed by an account

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for Ethereum development.

### Setup

```shell
# Clone the repository with submodules
git clone --recursive https://github.com/wildcat-finance/collateral-contract.git
cd collateral-contract

# Install dependencies
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Code Coverage

```shell
yarn coverage
```

## License

Apache-2.0 WITH LicenseRef-Commons-Clause-1.0

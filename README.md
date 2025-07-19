# Yearn V3 Lock-Stake Compounding Strategy

This repository contains the implementation of a Yearn V3 tokenized strategy for compounding rewards from a MakerDAO-style `Lockstake` contract. The strategy is designed to automatically claim and reinvest rewards, maximizing returns for users.

## Overview

The `LockStakeCumpounder` strategy is designed to manage deposits in a staking contract where rewards are distributed in a secondary token. The core functions of the strategy include:

- **Staking**: Deposits the underlying asset into the `Lockstake` contract.
- **Reward Compounding**: Periodically claims rewards and swaps them for the underlying asset, which is then redeposited to compound returns.
- **Auction Mechanism**: Includes a `kick` function to initiate an auction for claimed rewards, allowing for efficient and decentralized reward conversion.

## Architecture

The project consists of the following key components:

- **`LockStakeCumpounder.sol`**: The main strategy implementation, inheriting from Yearn's `BaseStrategy`.
- **`LockStakeCumpounderFactory.sol`**: A factory contract for deploying new instances of the `LockStakeCumpounder` strategy.
- **`StrategyAprOracle.sol`**: A periphery contract to calculate the APR of the strategy based on debt changes.
- **Interfaces**: A collection of interfaces for interacting with external contracts, such as `ILockstakeEngine`, `IQuoter`, and `IStaking`.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/en/download/package-manager/)

### Installation

1.  **Clone the repository:**

    ```sh
    git clone --recursive https://github.com/yearn/tokenized-strategy-foundry-mix
    cd tokenized-strategy-foundry-mix
    ```

2.  **Install dependencies:**

    ```sh
    yarn
    ```

3.  **Set up environment variables:**

    Create a `.env` file from the `.env.example` template and populate it with your RPC URLs.

    ```sh
    cp .env.example .env
    ```

### Build and Test

- **Build the project:**

  ```sh
  make build
  ```

- **Run tests:**

  ```sh
  make test
  ```

## Deployment

To deploy the contracts, you can use the provided `Deploy` script. The script will deploy the `StrategyAprOracle`, `LockstakeCumpounderFactory`, and a new `LockStakeCumpounder` strategy instance.

```sh
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --broadcast
```

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue.

## License

This project is licensed under the MIT License.

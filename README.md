# 🌟 Decentralized StableCoin (DSC) and DSCEngine

Welcome to the world of Decentralized StableCoin (DSC) and DSCEngine! 🚀 This repository houses the smart contracts and unit tests that bring a new stablecoin to life, backed by the power of decentralized finance. Let's dive in!

## Table of Contents

- [Introduction](#introduction)
- [Contracts](#contracts)
  - [DecentralizedStableCoin](#decentralizedstablecoin)
  - [DSCEngine](#dscengine)
- [Unit Tests](#unit-tests)
- [Invariant Tests](#invariant-tests)
- [Setup](#setup)
- [Running Tests](#running-tests)
- [Notes](#notes)
- [Contact](#contact)

## Introduction

Meet DSC: a stablecoin that maintains its value through robust collateral management. 🏦 Paired with the DSCEngine, they form a dynamic duo ensuring the stability and trustworthiness of your digital assets. Together, they create a system where users can deposit collateral, mint stablecoins, and keep the financial ecosystem balanced. ⚖️

## Contracts

### DecentralizedStableCoin

The heart of our system ❤️, the `DecentralizedStableCoin` contract represents the stablecoin. It has straightforward yet powerful functionalities to mint and burn DSC, ensuring the supply aligns with the collateral backing.

Key features:
- ✨ Minting DSC
- 🔥 Burning DSC
- 👑 Ownership transfer

### DSCEngine

The brain 🧠 behind the operation, the `DSCEngine` contract, manages collateral deposits, minting and burning DSC, and ensuring the overall health of the system through liquidation mechanisms.

Key features:
- 💰 Deposit collateral
- ✨ Mint DSC
- 🔥 Burn DSC
- 🔄 Redeem collateral
- 🛡️ Liquidate under-collateralized positions

## Unit Tests

We've put our contracts through rigorous testing 🧪 using Foundry, a framework for Solidity. These tests ensure that every function performs as expected, keeping the system robust and reliable.

### DSCEngineTest

Tests for the `DSCEngine` contract:
- 🏗️ Constructor tests
- 💲 Price tests
- 🏦 Collateral tests
- ✨ Minting tests
- 🔥 Burning tests
- 🔄 Redeeming collateral tests
- ⚔️ Liquidation tests
- 📢 Public function tests

### DecentralizedStableCoinTest

Tests for the `DecentralizedStableCoin` contract:
- 🏗️ Constructor test
- 👑 Ownership test
- ✨ Minting tests
- 🔥 Burning tests

## Invariant Tests

To ensure the robustness of our system, we have implemented invariant tests that continuously validate our core principles. 🔒

### StopOnRevertHandler

This contract interacts with the deployed `DSCEngine` and `DecentralizedStableCoin` contracts, performing various operations like minting, redeeming, and liquidating collateral.

### StopOnRevertInvariants

This contract defines the invariants for our system:
- The protocol must never be insolvent or undercollateralized.
- Users can't create stablecoins with a bad health factor.
- Users should only be liquidated if they have a bad health factor.

## Setup

Ready to get started? Follow these steps to set up your development environment:

1. **Install Foundry** by following the instructions at [Foundry](https://book.getfoundry.sh/getting-started/installation). 🛠️

2. **Clone this repository**:
   ```bash
   git clone https://github.com/hrmneffdii/foundry-defi-stablecoin
   cd foundry-defi-stablecoin
   ```

3. **Install dependencies**:
   ```bash
   forge install
   ```

## Running Tests

Time to see the magic in action! 🧙‍♂️ Run the tests with the following command:
```bash
forge test
```

This command will execute all the unit and invariant tests, showing you the results. 🏆

## Notes

- Make sure you have all the required dependencies installed and configured properly.
- Check out the `test/` directory for the complete test cases and the detailed assertions used. 🧾

## Contact

Got questions or feedback? We'd love to hear from you! 📧 Reach out at hermaneffendi0502@gmail.com.

**Currently i find the opportunities internship as junior smart contract enginerr 👐**

---

Thank you for exploring DSC and DSCEngine! Happy coding and may your stablecoins always remain stable! 🌟

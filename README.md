# Sei AgentFi - Bonding Curve Trading Platform

A decentralized token trading platform built on Uniswap V4 that implements a bonding curve mechanism inspired by PUMP.FUN. Tokens start in a bonding curve phase, then graduate to normal Uniswap trading at 20,000 USDT raised.

## Token Lifecycle

### Phase 1: Bonding Curve Trading

- **Token Creation**: Create tokens with metadata (name, symbol, image, social links)
- **Initial Supply**: 0 tokens - all minted through bonding curve purchases
- **Trading**: Direct buy/sell with bonding curve contract using PUMP.FUN formula
- **Price Mechanism**: Each purchase increases price, each sale decreases price

### Phase 2: Graduation (20,000 USDT raised)

- **Pool Creation**: Automatically creates Uniswap V4 liquidity pool
- **Liquidity Addition**: Remaining tokens (1B total - minted) + all USDT added as liquidity
- **Price Continuity**: Pool starts at final bonding curve price

### Phase 3: Normal Trading

- **Standard AMM**: Normal Uniswap trading with fixed 1B token supply
- **No More Minting**: Bonding curve disabled, price set by market forces

## Bonding Curve Formula

The bonding curve uses PUMP.FUN's mathematics with virtual reserves:

### Virtual Reserve Model

The bonding curve operates using virtual reserves that create a constant product:

```
Virtual USDT Reserve = 6,000 + x
Virtual Token Reserve = k ÷ (6,000 + x)
```

Where:

- `x` = Total USDT raised through bonding curve trading
- `k` = 6,438,000,006,000 (constant product)
- `6,000` = Virtual initial USDT reserve

### Token Supply Function

The total tokens issued as a function of USDT contributed:

$$
S(x) = T - \frac{k}{6000 + x}
$$

Where:

- `T` = Virtual total token supply (≈ 1.073B tokens)
- `k` = 6,438,000,006,000 (scaling constant)
- `x` = USDT contributed to the bonding curve

### Instantaneous Token Price

The current price per token (in USDT) at any point in the curve:

$$
p(x) = \frac{(6000 + x)^2}{k}
$$

**Properties:**

- Price starts low when `x` is small (early purchases cheaper)
- Price increases quadratically with total USDT raised
- Deterministic pricing follows mathematical formula
- No front-running during bonding curve phase

### Example Pricing

With our constants:

- **Initial Price** (x=0): `(6000)² ÷ 6,438,000,006,000 ≈ 0.0000056 USDT per token`
- **At 1,000 USDT raised**: `(7000)² ÷ 6,438,000,006,000 ≈ 0.0076 USDT per token`
- **At 10,000 USDT raised**: `(16000)² ÷ 6,438,000,006,000 ≈ 0.0398 USDT per token`
- **At graduation (20,000 USDT)**: `(26000)² ÷ 6,438,000,006,000 ≈ 0.105 USDT per token`

This creates a smooth price curve that increases predictably with purchases.

## Smart Contracts

### Core Contracts

#### BondingCurve.sol

Uniswap V4 hook that manages the token lifecycle:

- **Token Creation**: Creates tokens via TokenFactory with metadata
- **Bonding Curve Logic**: Implements PUMP.FUN's pricing formula
- **Buy/Sell Functions**: Direct token trading with automated pricing
- **Graduation System**: Creates pools and adds liquidity at 20K USDT
- **Swap Protection**: Prevents Uniswap swaps during bonding curve phase
- **Event Logging**: Emits price and trading events

Constants:

- 1 billion token max supply per token
- 20,000 USDT graduation threshold

#### TokenFactory.sol

Factory contract for creating ERC20 tokens:

- **Token Deployment**: Creates MockERC20 tokens with custom parameters
- **Metadata Support**: Stores token information (name, symbol, decimals, initial supply)
- **Creator Tracking**: Tracks tokens created by each address
- **Registry**: Maintains list of all created tokens

#### MockERC20.sol

ERC20 token with additional functionality:

- **Standard ERC20**: Full ERC20 compliance with custom decimals
- **Mint/Burn**: Functions for bonding curve to mint/burn tokens

## Deployment Scripts

### Infrastructure Setup

#### 00_DeployUniswapV4Infrastructure.s.sol

Deploys the complete Uniswap V4 ecosystem:

- Permit2 (token approvals)
- PoolManager (core pool management)
- PositionManager (liquidity positions)
- V4Router (swap routing)

#### 01_DeployTokens.s.sol

Sets up the token infrastructure:

- Deploys TokenFactory
- Creates USDT token (1B supply, 18 decimals)
- Saves addresses to deployment JSON

#### 02_DeployHook.s.sol

Deploys the BondingCurve hook:

- Mines correct hook address (Uniswap V4 requirement)
- Deploys hook with proper permissions
- Configures bonding curve parameters

### Token Operations

#### 03_CreateToken.s.sol

Creates a new token for bonding curve trading:

- Creates token with metadata (name, symbol, description, social links)
- Starts in bonding curve phase (0 initial supply)
- Ready for buy/sell operations

#### 04_Swap.s.sol

Bonding curve token purchases:

- Buys tokens using USDT via bonding curve
- Shows price impact and curve progression
- Handles automatic graduation if threshold reached

#### 05_SellTokens.s.sol

Bonding curve token sales:

- Sells tokens back to bonding curve for USDT
- Shows inverse price calculation
- Updates virtual reserves accordingly

#### 06_NormalSwap.s.sol

Normal Uniswap trading after graduation:

- Executes standard AMM swaps
- Compares AMM vs bonding curve pricing
- Confirms normal trading functionality

## Getting Started

### Requirements

This template requires Foundry (stable). Update your installation:

```bash
foundryup
```

### Installation

Install dependencies and run tests:

```bash
forge install
forge test
```

### Deployment Sequence

1. **Deploy Infrastructure**: `forge script script/00_DeployUniswapV4Infrastructure.s.sol`
2. **Deploy Tokens**: `forge script script/01_DeployTokens.s.sol`
3. **Deploy Hook**: `forge script script/02_DeployHook.s.sol`
4. **Create Token**: `forge script script/03_CreateToken.s.sol`
5. **Test Trading**: `forge script script/04_Swap.s.sol`

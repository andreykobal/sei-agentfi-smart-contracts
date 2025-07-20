# Uniswap v4 Infrastructure Deployment

This guide explains how to deploy the complete Uniswap v4 infrastructure including all core contracts needed for a functioning DEX.

## Overview

The Uniswap v4 infrastructure consists of four main contracts:

1. **Permit2** - EIP-712 permit system for gasless approvals
2. **PoolManager** - Core contract that manages all liquidity pools
3. **PositionManager** - NFT-based system for managing liquidity positions
4. **V4Router** - Router contract for executing swaps and liquidity operations

## Quick Start

### Deploy All Infrastructure

```bash
# Deploy to local anvil
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url http://localhost:8545 --broadcast --private-key $PRIVATE_KEY

# Deploy to testnet (e.g., Sepolia)
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $PRIVATE_KEY --verify

# Deploy to mainnet
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --private-key $PRIVATE_KEY --verify
```

### What Gets Deployed

The script will deploy all contracts in the correct order and handle dependencies:

```
Uniswap v4 Infrastructure
├── Permit2 (EIP-712 permit system)
├── PoolManager (Core pool management)
├── PositionManager (NFT liquidity positions)
└── V4Router (Swap and liquidity router)
```

## Detailed Contract Information

### 1. Permit2

- **Purpose**: Enables gasless token approvals using EIP-712 signatures
- **Dependencies**: None
- **Key Features**:
  - Signature-based token transfers
  - Batch operations
  - Expiration and nonce management

### 2. PoolManager

- **Purpose**: Central registry and manager for all Uniswap v4 pools
- **Dependencies**: None (but requires an owner)
- **Key Features**:
  - Pool initialization
  - Swap execution
  - Liquidity modification
  - Hook integration
  - Fee collection

### 3. PositionManager

- **Purpose**: NFT-based system for managing liquidity positions
- **Dependencies**: PoolManager, Permit2
- **Key Features**:
  - ERC-721 NFT representation of positions
  - Complex liquidity management
  - Multi-position operations
  - Gas-optimized operations

### 4. V4Router

- **Purpose**: User-facing router for swaps and basic operations
- **Dependencies**: PoolManager, Permit2
- **Key Features**:
  - Multi-hop swaps
  - Exact input/output swaps
  - Slippage protection
  - Deadline protection

## Usage Examples

### After Deployment

1. **Update your scripts** with the deployed addresses:

   ```solidity
   // In script/base/BaseScript.sol
   IPoolManager poolManager = IPoolManager(0x...); // Your deployed address
   IPositionManager positionManager = IPositionManager(0x...);
   IUniswapV4Router04 swapRouter = IUniswapV4Router04(0x...);
   ```

2. **Deploy your hooks** (if any):

   ```bash
   forge script script/00_DeployHook.s.sol --rpc-url $RPC_URL --broadcast
   ```

3. **Create and initialize pools**:

   ```bash
   forge script script/01_CreatePoolAndAddLiquidity.s.sol --rpc-url $RPC_URL --broadcast
   ```

4. **Add liquidity**:

   ```bash
   forge script script/02_AddLiquidity.s.sol --rpc-url $RPC_URL --broadcast
   ```

5. **Execute swaps**:
   ```bash
   forge script script/03_Swap.s.sol --rpc-url $RPC_URL --broadcast
   ```

## Configuration

### Network-Specific Settings

For different networks, you may need to update:

- **Wrapped Native Token**: Set `wrappedNative` address for non-ETH chains
- **Position Descriptor**: Deploy and set a position descriptor for better NFT metadata
- **Gas Limits**: Adjust `unsubscribeGasLimit` based on network gas costs

### Example for Polygon:

```solidity
// In the deployment script
wrappedNative = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // WMATIC
```

### Example for Arbitrum:

```solidity
// In the deployment script
wrappedNative = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
```

## Testing the Deployment

### Local Testing with Anvil

1. **Start Anvil**:

   ```bash
   anvil --fork-url $MAINNET_RPC_URL
   ```

2. **Deploy infrastructure**:

   ```bash
   forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url http://localhost:8545 --broadcast
   ```

3. **Run tests**:
   ```bash
   forge test --fork-url http://localhost:8545
   ```

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐
│   V4Router      │────│  PositionMgr    │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────┬───────────────┘
                 │
         ┌─────────────────┐
         │   PoolManager   │
         └─────────────────┘
                 │
         ┌─────────────────┐
         │     Permit2     │
         └─────────────────┘
```

## Gas Costs

Typical deployment costs (may vary by network):

| Contract        | Gas Used   | Cost @ 20 gwei |
| --------------- | ---------- | -------------- |
| Permit2         | ~2.5M      | ~0.05 ETH      |
| PoolManager     | ~6M        | ~0.12 ETH      |
| PositionManager | ~8M        | ~0.16 ETH      |
| V4Router        | ~3M        | ~0.06 ETH      |
| **Total**       | **~19.5M** | **~0.39 ETH**  |

## Security Considerations

1. **Owner Privileges**: The PoolManager owner can:

   - Set protocol fees
   - Update fee collectors
   - Always use a multisig for mainnet deployments

2. **Upgradeability**: These contracts are **not upgradeable**

   - Ensure thorough testing before mainnet deployment
   - Consider using CREATE2 for deterministic addresses

3. **Hook Integration**:
   - Hooks have significant power over pool behavior
   - Always audit hooks thoroughly
   - Consider hook governance mechanisms

## Troubleshooting

### Common Issues

1. **"Contract creation failed"**:

   - Check gas limits
   - Ensure sufficient ETH balance
   - Verify network connectivity

2. **"Nonce too high"**:

   - Reset your wallet nonce
   - Use `--slow` flag with forge script

3. **"Verification failed"**:
   - Ensure exact compiler version match
   - Check constructor arguments
   - Use `--verify` flag during deployment

### Getting Help

- Check the [Uniswap v4 documentation](https://docs.uniswap.org/protocol/V4/overview)
- Review the [v4-periphery repository](https://github.com/Uniswap/v4-periphery)
- Join the [Uniswap Discord](https://discord.gg/uniswap)

## License

MIT License - see LICENSE file for details.

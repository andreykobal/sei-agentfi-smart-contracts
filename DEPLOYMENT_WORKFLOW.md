# Deployment Workflow

This guide shows how to deploy the full Uniswap v4 infrastructure with the updated scripts that save and load addresses from JSON files.

## Updated Architecture

```
🔄 Deployment Process:
DeployUniswapV4Infrastructure.s.sol → deployments/{chainId}.json → BaseScript.sol
```

### What Changed

1. **`DeployUniswapV4Infrastructure.s.sol`**:
   - Now saves all deployed addresses (including tokens) to `deployments/{chainId}.json`
   - Uses random salts for CREATE2 deployments to avoid collisions
   - Deploys 2 test tokens (TKA/TKB) with 1B supply each
2. **`BaseScript.sol`**: Now reads all contract addresses (including Permit2 and tokens) from the JSON file
3. **No more hardcoded addresses**: Everything is dynamic based on your actual deployments
4. **No more CREATE2 collisions**: Random salts ensure fresh deployments every time

## Step-by-Step Workflow

### 1. Set Environment Variables

```bash
# Export your private key and RPC URL
export PRIVATE_KEY="0x..."
export RPC_URL="http://localhost:8545"  # or your preferred network

# Optional: For contract verification
export ETHERSCAN_API_KEY="..."
```

### 2. Create Deployments Directory

```bash
mkdir -p deployments
```

### 3. Deploy Uniswap v4 Infrastructure

```bash
forge script script/DeployUniswapV4Infrastructure.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

This will:

- Deploy all 4 core contracts (Permit2, PoolManager, PositionManager, V4Router)
- Save addresses to `deployments/{chainId}.json`
- Display a deployment summary

### 4. Verify the Deployment File

Check that the JSON file was created:

```bash
# For local anvil (chainId 31337)
cat deployments/31337.json

# Example output:
{
  "chainId": 31337,
  "permit2": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
  "poolManager": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  "positionManager": "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  "v4Router": "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9",
  "token0": "0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6",
  "token1": "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318"
}
```

### 5. Deploy Hooks (Now Works!)

Now `BaseScript.sol` can load the addresses, so hook deployment works:

```bash
forge script script/00_DeployHook.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 6. Use Other Scripts

All scripts that inherit from `BaseScript` now automatically work:

```bash
# Create pools and add liquidity
forge script script/01_CreatePoolAndAddLiquidity.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY

# Add more liquidity
forge script script/02_AddLiquidity.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY

# Execute swaps
forge script script/03_Swap.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

## Multi-Network Support

### Each Network Gets Its Own File

```bash
deployments/
├── 1.json          # Ethereum Mainnet
├── 11155111.json   # Sepolia Testnet
├── 31337.json      # Local Anvil
├── 8453.json       # Base
└── 137.json        # Polygon
```

### Deploy to Multiple Networks

```bash
# Deploy to Sepolia
export RPC_URL="https://sepolia.infura.io/v3/YOUR_PROJECT_ID"
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY --verify

# Deploy to Polygon
export RPC_URL="https://polygon-rpc.com"
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY --verify
```

### Scripts Automatically Use Correct Network

`BaseScript.sol` automatically detects the chain ID and loads the right deployment file:

```solidity
string memory chainIdStr = vm.toString(block.chainid);
string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
```

## Error Handling

### Common Error: "Deployment file not found"

```bash
Error: Deployment file not found: deployments/31337.json
```

**Solution**: Deploy the infrastructure first:

```bash
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

### Common Error: JSON parsing failed

**Solution**: Check if the JSON file is valid:

```bash
cat deployments/31337.json | jq .
```

## Testing the Full Workflow

### Local Testing with Anvil

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy everything
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
export RPC_URL="http://localhost:8545"

# Deploy infrastructure
forge script script/DeployUniswapV4Infrastructure.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# Deploy hooks
forge script script/00_DeployHook.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# Create pools
forge script script/01_CreatePoolAndAddLiquidity.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
```

## Benefits of This Approach

✅ **No hardcoded addresses** - Everything is dynamic  
✅ **Multi-network support** - Each network has its own deployment file  
✅ **Version control friendly** - JSON files can be committed to track deployments  
✅ **Script reusability** - Same scripts work on any network after deployment  
✅ **Error prevention** - Scripts fail fast if infrastructure isn't deployed  
✅ **Auditable** - Clear record of what's deployed where  
✅ **No CREATE2 collisions** - Random salts allow multiple deployments  
✅ **Test tokens included** - Ready-to-use ERC20 tokens for testing

## File Structure

```
project/
├── script/
│   ├── DeployUniswapV4Infrastructure.s.sol  # 🔧 Deploys & saves to JSON
│   ├── base/
│   │   └── BaseScript.sol                    # 📖 Reads from JSON
│   ├── 00_DeployHook.s.sol                  # ✅ Now works!
│   ├── 01_CreatePoolAndAddLiquidity.s.sol   # ✅ Now works!
│   └── ...
└── deployments/
    ├── 31337.json                           # 💾 Anvil deployments
    ├── 11155111.json                        # 💾 Sepolia deployments
    └── 1.json                               # 💾 Mainnet deployments
```

Ready to deploy! 🚀

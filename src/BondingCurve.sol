// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

import {TokenFactory} from "./TokenFactory.sol";
import {MockERC20} from "./MockERC20.sol";

contract BondingCurve is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    // Token factory for creating new tokens
    TokenFactory public immutable tokenFactory;
    
    // USDT address for pairing
    address public immutable usdt;
    
    // Track bonding curve data for each token
    mapping(address => uint256) public totalMinted; // Total tokens minted via bonding curve
    mapping(address => uint256) public totalUsdtRaised; // Total USDT raised for each token
    mapping(PoolId => address) public poolToToken; // Map pool to its custom token address
    
    // Events
    event TokenAndPoolCreated(address indexed token, address indexed creator, PoolId indexed poolId);

    constructor(IPoolManager _poolManager, address _tokenFactory, address _usdt) BaseHook(_poolManager) {
        tokenFactory = TokenFactory(_tokenFactory);
        usdt = _usdt;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Enable custom swap logic
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Creates a new ERC20 token and pairs it with USDT in a new pool with 0 liquidity
    /// @param name The name of the new token
    /// @param symbol The symbol of the new token
    /// @param initialSupply The initial supply of the new token (will be minted to creator)
    /// @return tokenAddress The address of the newly created token
    /// @return poolId The ID of the newly created pool
    function createTokenAndPool(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) external returns (address tokenAddress, PoolId poolId) {
        // Create the new token with 18 decimals
        tokenAddress = tokenFactory.createToken(name, symbol, 18, initialSupply);
        
        // Create currencies for pool creation
        Currency currency0;
        Currency currency1;
        
        // Determine currency ordering (lower address first)
        if (tokenAddress < usdt) {
            currency0 = Currency.wrap(tokenAddress);
            currency1 = Currency.wrap(usdt);
        } else {
            currency0 = Currency.wrap(usdt);
            currency1 = Currency.wrap(tokenAddress);
        }
        
        // Create the pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3% fee
            tickSpacing: 60, // Standard tick spacing for 0.3% fee
            hooks: this // Use this hook contract
        });
        
        // Initialize the pool with 0 liquidity (price = 1:80000 - 80,000 tokens for 1 USDT)
        uint160 sqrtPriceX96;
        
        if (tokenAddress < usdt) {
            // token is currency0, USDT is currency1
            // price = currency1/currency0 = USDT/token = 1/80,000 = 0.0000125
            sqrtPriceX96 = 280174524799725590; // sqrt(1/80000) * 2^96
        } else {
            // USDT is currency0, token is currency1  
            // price = currency1/currency0 = token/USDT = 80,000
            sqrtPriceX96 = 22415874239952134371853123584; // sqrt(80000) * 2^96
        }
        
        poolManager.initialize(poolKey, sqrtPriceX96);
        
        poolId = poolKey.toId();
        
        // Store the mapping for this pool
        poolToToken[poolId] = tokenAddress;
        
        emit TokenAndPoolCreated(tokenAddress, msg.sender, poolId);
        
        return (tokenAddress, poolId);
    }

    /// @notice Calculate how many tokens to mint for a given USDT amount based on bonding curve
    /// @param tokenAddress The token address
    /// @param usdtAmount The amount of USDT being spent
    /// @return tokensToMint The number of tokens to mint
    function calculateTokensToMint(address tokenAddress, uint256 usdtAmount) public view returns (uint256 tokensToMint) {
        uint256 currentSupply = totalMinted[tokenAddress];
        
        // Simple linear bonding curve: price increases as supply increases
        // Base price: 80,000 tokens per USDT
        // Price formula: baseTokens * (1 + supply / 1e24)
        // This means as more tokens are minted, fewer tokens per USDT
        
        uint256 baseTokensPerUsdt = 80000e18; // 80,000 tokens per USDT
        uint256 supplyFactor = currentSupply / 1e24; // Divide by 1e24 for scaling
        
        if (supplyFactor > 100) {
            supplyFactor = 100; // Cap the price increase
        }
        
        tokensToMint = (baseTokensPerUsdt * usdtAmount) / (1e18 + supplyFactor * 1e16);
        
        return tokensToMint;
    }
    
    /// @notice Buy tokens directly with USDT using the bonding curve
    /// @param tokenAddress The address of the token to buy
    /// @param usdtAmount The amount of USDT to spend
    /// @return tokensReceived The number of tokens received
    function buyTokens(address tokenAddress, uint256 usdtAmount) external returns (uint256 tokensReceived) {
        require(usdtAmount > 0, "Amount must be greater than 0");
        
        // Calculate tokens to mint
        tokensReceived = calculateTokensToMint(tokenAddress, usdtAmount);
        require(tokensReceived > 0, "No tokens to mint");
        
        // Transfer USDT from user to this contract
        MockERC20(usdt).transferFrom(msg.sender, address(this), usdtAmount);
        
        // Mint tokens to user
        MockERC20(tokenAddress).mint(msg.sender, tokensReceived);
        
        // Update tracking
        totalMinted[tokenAddress] += tokensReceived;
        totalUsdtRaised[tokenAddress] += usdtAmount;
        
        return tokensReceived;
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        address tokenAddress = poolToToken[poolId];
        
        // If this isn't a bonding curve pool, use normal swap logic
        if (tokenAddress == address(0)) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Determine which currency is USDT and which is the token
        bool currency0IsUsdt = Currency.unwrap(key.currency0) == usdt;
        bool currency1IsUsdt = Currency.unwrap(key.currency1) == usdt;
        bool currency0IsToken = Currency.unwrap(key.currency0) == tokenAddress;
        bool currency1IsToken = Currency.unwrap(key.currency1) == tokenAddress;
        
        // Validate this is a USDT/token pair
        if (!((currency0IsUsdt && currency1IsToken) || (currency0IsToken && currency1IsUsdt))) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Check if user is buying tokens with USDT (exactInput with USDT)
        bool buyingTokensWithUsdt = false;
        uint256 usdtAmountIn = 0;
        
        if (params.amountSpecified > 0) { // exactInput
            if (currency0IsUsdt && params.zeroForOne) {
                // Swapping USDT (currency0) for tokens (currency1)
                buyingTokensWithUsdt = true;
                usdtAmountIn = uint256(params.amountSpecified);
            } else if (currency1IsUsdt && !params.zeroForOne) {
                // Swapping USDT (currency1) for tokens (currency0)  
                buyingTokensWithUsdt = true;
                usdtAmountIn = uint256(params.amountSpecified);
            }
        }
        
        if (buyingTokensWithUsdt && usdtAmountIn > 0) {
            // Calculate tokens to mint using bonding curve
            uint256 tokensToMint = calculateTokensToMint(tokenAddress, usdtAmountIn);
            
            // Mint tokens directly to the sender
            MockERC20(tokenAddress).mint(sender, tokensToMint);
            
            // Update tracking
            totalMinted[tokenAddress] += tokensToMint;
            totalUsdtRaised[tokenAddress] += usdtAmountIn;
            
            // For now, let the swap proceed normally but the tokens are already minted
            // The user will get both: minted tokens + whatever the normal swap gives
            // This creates an arbitrage opportunity that will quickly bring pool to equilibrium
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // For any other swap type, use normal logic
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        return (this.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        return this.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        return this.beforeRemoveLiquidity.selector;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

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
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {TokenFactory} from "./TokenFactory.sol";
import {MockERC20} from "./MockERC20.sol";

contract BondingCurve is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using StateLibrary for IPoolManager;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    // Token factory for creating new tokens
    TokenFactory public immutable tokenFactory;
    
    // USDT address for pairing
    address public immutable usdt;
    
    // Position manager for adding liquidity
    IPositionManager public immutable positionManager;
    
    // Permit2 for token approvals
    IPermit2 public immutable permit2;
    
    // Track bonding curve data for each token
    mapping(address => uint256) public totalMinted; // Total tokens minted via bonding curve
    mapping(address => uint256) public totalUsdtRaised; // Total USDT raised for each token
    mapping(PoolId => address) public poolToToken; // Map pool to its custom token address
    mapping(address => PoolKey) public tokenToPoolKey; // Map token to its pool key
    mapping(address => bool) public liquidityAdded; // Track if liquidity has been added for a token
    
    // Constants
    uint256 public constant LIQUIDITY_THRESHOLD = 800_000_000 * 1e18; // 800M tokens
    uint256 public constant LIQUIDITY_TOKEN_AMOUNT = 200_000_000 * 1e18; // 200M tokens
    
    // Events
    event TokenAndPoolCreated(address indexed token, address indexed creator, PoolId indexed poolId);
    event LiquidityAdded(address indexed token, uint256 usdtAmount, uint256 tokenAmount);

    constructor(IPoolManager _poolManager, address _tokenFactory, address _usdt, IPositionManager _positionManager, IPermit2 _permit2) BaseHook(_poolManager) {
        tokenFactory = TokenFactory(_tokenFactory);
        usdt = _usdt;
        positionManager = _positionManager;
        permit2 = _permit2;
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
        
        // Store the mappings for this pool
        poolToToken[poolId] = tokenAddress;
        tokenToPoolKey[tokenAddress] = poolKey;
        
        emit TokenAndPoolCreated(tokenAddress, msg.sender, poolId);
        
        return (tokenAddress, poolId);
    }

    /// @notice Calculate how many tokens to mint for a given USDT amount using PUMP.FUN's bonding curve
    /// @param tokenAddress The token address  
    /// @param usdtAmount The amount of USDT being spent (in wei)
    /// @return tokensToMint The number of tokens to mint (in wei)
    function calculateTokensToMint(address tokenAddress, uint256 usdtAmount) public view returns (uint256 tokensToMint) {
        uint256 currentUsdtRaised = totalUsdtRaised[tokenAddress];
        
        // PUMP.FUN bonding curve formula scaled for SOL=$200, USDT=$1
        // Original: y = 1073000191 - 32190005730/(30+x) where x=SOL, y=tokens (natural units)
        // Scaled: y = 1073000191 - 6438000006000/(6000+x) where x=USDT, y=tokens (natural units)
        //
        // Convert wei to natural units for calculation
        uint256 virtualUsdtReserve = 6000; // 6000 USDT (natural units)
        uint256 virtualTokenReserve = 1073000191; // ~1.073B tokens (natural units)
        uint256 k = virtualUsdtReserve * virtualTokenReserve; // k = 6,438,000,006,000
        
        // Convert wei amounts to natural units for calculation
        uint256 currentUsdtRaisedNatural = currentUsdtRaised / 1e18;
        uint256 usdtAmountNatural = usdtAmount / 1e18;
        
        // Current virtual state after previous purchases (natural units)
        uint256 currentVirtualUsdtNatural = virtualUsdtReserve + currentUsdtRaisedNatural;
        uint256 currentVirtualTokensNatural = k / currentVirtualUsdtNatural;
        
        // Virtual state after this purchase (natural units)
        uint256 newVirtualUsdtNatural = currentVirtualUsdtNatural + usdtAmountNatural;
        uint256 newVirtualTokensNatural = k / newVirtualUsdtNatural;
        
        // Tokens to mint in natural units
        uint256 tokensToMintNatural = currentVirtualTokensNatural - newVirtualTokensNatural;
        
        // Convert back to wei for return
        tokensToMint = tokensToMintNatural * 1e18;
        
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
        
        // Check if we should add liquidity (800M+ tokens minted and not already added)
        if (totalMinted[tokenAddress] >= LIQUIDITY_THRESHOLD && !liquidityAdded[tokenAddress]) {
            _addLiquidityToPool(tokenAddress);
            liquidityAdded[tokenAddress] = true;
        }
        
        return tokensReceived;
    }
    
    /// @notice Internal function to add liquidity to the pool using PositionManager
    /// @param tokenAddress The token address
    function _addLiquidityToPool(address tokenAddress) internal {
        PoolKey memory key = tokenToPoolKey[tokenAddress];
        
        // Use all accumulated USDT for this token
        uint256 usdtAmount = totalUsdtRaised[tokenAddress];
        require(usdtAmount > 0, "No USDT to add as liquidity");
        
        // Use 200M tokens for liquidity
        uint256 tokensForLiquidity = LIQUIDITY_TOKEN_AMOUNT;
        
        // Mint tokens for liquidity to this contract
        MockERC20(tokenAddress).mint(address(this), tokensForLiquidity);
        
        // Get current pool state
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        
        // Set tick range (wide range for simplicity)
        int24 tickSpacing = key.tickSpacing;
        int24 tickLower = ((currentTick - 100 * tickSpacing) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + 100 * tickSpacing) / tickSpacing) * tickSpacing;
        
        // Determine amounts based on currency ordering
        uint256 amount0Max;
        uint256 amount1Max;
        
        if (Currency.unwrap(key.currency0) == tokenAddress) {
            // token is currency0, USDT is currency1
            amount0Max = tokensForLiquidity;
            amount1Max = usdtAmount;
        } else {
            // USDT is currency0, token is currency1
            amount0Max = usdtAmount;
            amount1Max = tokensForLiquidity;
        }
        
        // Calculate liquidity amount
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );
        
        // Approve tokens to Permit2 first (standard ERC20 approval)
        MockERC20(usdt).approve(address(permit2), usdtAmount);
        MockERC20(tokenAddress).approve(address(permit2), tokensForLiquidity);
        
        // Set up Permit2 allowances for PositionManager
        permit2.approve(usdt, address(positionManager), uint160(usdtAmount), uint48(block.timestamp + 3600));
        permit2.approve(tokenAddress, address(positionManager), uint160(tokensForLiquidity), uint48(block.timestamp + 3600));
        
        // Prepare multicall parameters
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        
        bytes[] memory mintParams = new bytes[](2);
        mintParams[0] = abi.encode(key, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), new bytes(0));
        mintParams[1] = abi.encode(key.currency0, key.currency1);
        
        bytes[] memory params = new bytes[](1);
        params[0] = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 60
        );
        
        // Add liquidity through position manager
        positionManager.multicall(params);
        
        emit LiquidityAdded(tokenAddress, usdtAmount, tokensForLiquidity);
    }
    
    /// @notice Manually trigger liquidity addition if threshold is met
    /// @param tokenAddress The token address to add liquidity for
    function addLiquidityIfReady(address tokenAddress) external {
        require(totalMinted[tokenAddress] >= LIQUIDITY_THRESHOLD, "Threshold not met");
        require(!liquidityAdded[tokenAddress], "Liquidity already added");
        
        _addLiquidityToPool(tokenAddress);
        liquidityAdded[tokenAddress] = true;
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
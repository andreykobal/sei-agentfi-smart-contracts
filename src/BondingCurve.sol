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
    uint256 public constant USDT_GRADUATION_THRESHOLD = 20_000 * 1e18; // 20K USDT
    uint256 public constant TOTAL_TOKEN_SUPPLY = 1_000_000_000 * 1e18; // 1B total token supply
    
    // Bonding curve constants (PUMP.FUN formula scaled for USDT)
    uint256 private constant VIRTUAL_USDT_RESERVE = 6000; // 6000 USDT (natural units)
    uint256 private constant VIRTUAL_TOKEN_RESERVE = 1073000191; // ~1.073B tokens (natural units)
    uint256 private constant BONDING_CURVE_K = VIRTUAL_USDT_RESERVE * VIRTUAL_TOKEN_RESERVE; // k = 6,438,000,006,000
    
    // Events
    event TokenCreated(address indexed token, address indexed creator, string name, string symbol);
    event LiquidityAdded(address indexed token, uint256 usdtAmount, uint256 tokenAmount);
    event TokenGraduated(address indexed token, uint256 totalMinted, uint256 totalUsdtRaised);
    
    /// @notice Get current virtual reserves state for a token's bonding curve
    /// @param tokenAddress The token address
    /// @return virtualUsdtNatural Current virtual USDT reserve in natural units
    /// @return virtualTokensNatural Current virtual token reserve in natural units
    function _getCurrentVirtualReserves(address tokenAddress) private view returns (uint256 virtualUsdtNatural, uint256 virtualTokensNatural) {
        uint256 currentUsdtRaisedNatural = totalUsdtRaised[tokenAddress] / 1e18;
        virtualUsdtNatural = VIRTUAL_USDT_RESERVE + currentUsdtRaisedNatural;
        virtualTokensNatural = BONDING_CURVE_K / virtualUsdtNatural;
    }

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
            beforeAddLiquidity: false,  // Disabled - use normal Uniswap flow
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,  // Disabled - use normal Uniswap flow
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

    /// @notice Creates a new ERC20 token for bonding curve trading (pool created later at graduation)
    /// @param name The name of the new token
    /// @param symbol The symbol of the new token
    /// @param initialSupply The initial supply of the new token (will be minted to creator)
    /// @return tokenAddress The address of the newly created token
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) external returns (address tokenAddress) {
        // Create the new token with 18 decimals
        tokenAddress = tokenFactory.createToken(name, symbol, 18, initialSupply);
        
        // Pool key will be created when token graduates and pool is created
        // For now, just emit the token creation event
        emit TokenCreated(tokenAddress, msg.sender, name, symbol);
        
        return tokenAddress;
    }

    /// @notice Calculate how many tokens to mint for a given USDT amount using PUMP.FUN's bonding curve
    /// @param tokenAddress The token address  
    /// @param usdtAmount The amount of USDT being spent (in wei)
    /// @return tokensToMint The number of tokens to mint (in wei)
    function calculateTokensToMint(address tokenAddress, uint256 usdtAmount) public view returns (uint256 tokensToMint) {
        // Get current virtual reserves state
        (uint256 currentVirtualUsdtNatural, uint256 currentVirtualTokensNatural) = _getCurrentVirtualReserves(tokenAddress);
        
        // Convert wei to natural units for calculation
        uint256 usdtAmountNatural = usdtAmount / 1e18;
        
        // Virtual state after this purchase (natural units)
        uint256 newVirtualUsdtNatural = currentVirtualUsdtNatural + usdtAmountNatural;
        uint256 newVirtualTokensNatural = BONDING_CURVE_K / newVirtualUsdtNatural;
        
        // Tokens to mint in natural units
        uint256 tokensToMintNatural = currentVirtualTokensNatural - newVirtualTokensNatural;
        
        // Convert back to wei for return
        tokensToMint = tokensToMintNatural * 1e18;
        
        return tokensToMint;
    }
    
    /// @notice Calculate the current price on the bonding curve (USDT per token)
    /// @param tokenAddress The token address
    /// @return priceUsdtPerToken The current price in USDT per token (in wei units)
    function getCurrentBondingCurvePrice(address tokenAddress) public view returns (uint256 priceUsdtPerToken) {
        // Get current virtual reserves state
        (uint256 currentVirtualUsdtNatural, uint256 currentVirtualTokensNatural) = _getCurrentVirtualReserves(tokenAddress);
        
        // Price = USDT / Token (in natural units)
        // priceNatural = currentVirtualUsdtNatural / currentVirtualTokensNatural
        // Convert to wei: multiply by 1e18
        priceUsdtPerToken = (currentVirtualUsdtNatural * 1e18) / currentVirtualTokensNatural;
        
        return priceUsdtPerToken;
    }
    
    /// @notice Calculate integer square root using Newton's method
    /// @param x The input value
    /// @return result The square root of x
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // Initial guess
        result = x;
        uint256 k = (x >> 1) + 1;
        
        // Newton's method iterations
        while (k < result) {
            result = k;
            k = (x / k + k) >> 1;
        }
    }
    
    /// @notice Check if a token has graduated (liquidity added to pool)
    /// @param tokenAddress The token address to check
    /// @return graduated True if token has graduated and liquidity is available for normal swaps
    function isTokenGraduated(address tokenAddress) public view returns (bool graduated) {
        return liquidityAdded[tokenAddress];
    }
    
    /// @notice Get graduation progress for a token
    /// @param tokenAddress The token address to check
    /// @return isGraduated True if token has graduated
    /// @return usdtRaised Current USDT raised via bonding curve
    /// @return usdtUntilGraduation USDT remaining until graduation (0 if graduated)
    /// @return progressPercent Progress toward graduation (0-100, or 100+ if graduated)
    function getGraduationStatus(address tokenAddress) public view returns (
        bool isGraduated,
        uint256 usdtRaised,
        uint256 usdtUntilGraduation,
        uint256 progressPercent
    ) {
        isGraduated = liquidityAdded[tokenAddress];
        usdtRaised = totalUsdtRaised[tokenAddress];
        
        if (isGraduated || usdtRaised >= USDT_GRADUATION_THRESHOLD) {
            usdtUntilGraduation = 0;
            progressPercent = 100;
        } else {
            usdtUntilGraduation = USDT_GRADUATION_THRESHOLD - usdtRaised;
            progressPercent = (usdtRaised * 100) / USDT_GRADUATION_THRESHOLD;
        }
    }
    
    /// @notice Buy tokens directly with USDT using the bonding curve
    /// @param tokenAddress The address of the token to buy
    /// @param usdtAmount The amount of USDT to spend
    /// @return tokensReceived The number of tokens received
    function buyTokens(address tokenAddress, uint256 usdtAmount) external returns (uint256 tokensReceived) {
        require(usdtAmount > 0, "Amount must be greater than 0");
        require(!isTokenGraduated(tokenAddress), "Token has graduated - use normal swaps instead");
        
        uint256 currentUsdtRaised = totalUsdtRaised[tokenAddress];
        uint256 actualUsdtToSpend = usdtAmount;
        uint256 refundAmount = 0;
        
        // Check if this purchase would exceed the graduation threshold
        if (currentUsdtRaised + usdtAmount > USDT_GRADUATION_THRESHOLD) {
            // Calculate how much USDT we can actually accept
            actualUsdtToSpend = USDT_GRADUATION_THRESHOLD - currentUsdtRaised;
            refundAmount = usdtAmount - actualUsdtToSpend;
            require(actualUsdtToSpend > 0, "Already at graduation threshold");
        }
        
        // Calculate tokens to mint based on actual USDT to spend
        tokensReceived = calculateTokensToMint(tokenAddress, actualUsdtToSpend);
        require(tokensReceived > 0, "No tokens to mint");
        
        // Transfer USDT from user to this contract (full amount first)
        MockERC20(usdt).transferFrom(msg.sender, address(this), usdtAmount);
        
        // Refund excess USDT if needed
        if (refundAmount > 0) {
            MockERC20(usdt).transfer(msg.sender, refundAmount);
        }
        
        // Mint tokens to user
        MockERC20(tokenAddress).mint(msg.sender, tokensReceived);
        
        // Update tracking with actual amounts
        totalMinted[tokenAddress] += tokensReceived;
        totalUsdtRaised[tokenAddress] += actualUsdtToSpend;
        
        // Check if we should add liquidity (20K USDT raised and not already added)
        if (totalUsdtRaised[tokenAddress] >= USDT_GRADUATION_THRESHOLD && !liquidityAdded[tokenAddress]) {
            _addLiquidityToPool(tokenAddress);
            liquidityAdded[tokenAddress] = true;
            
            // Emit graduation event
            emit TokenGraduated(tokenAddress, totalMinted[tokenAddress], totalUsdtRaised[tokenAddress]);
        }
        
        return tokensReceived;
    }
    
    /// @notice Calculate how much USDT to return for selling tokens using the inverse bonding curve
    /// @param tokenAddress The token address
    /// @param tokenAmount The amount of tokens being sold (in wei)
    /// @return usdtToReturn The amount of USDT to return (in wei)
    function calculateUsdtToReturn(address tokenAddress, uint256 tokenAmount) public view returns (uint256 usdtToReturn) {
        uint256 currentTokensMinted = totalMinted[tokenAddress];
        
        // Can't sell more than minted via bonding curve
        require(tokenAmount <= currentTokensMinted, "Cannot sell more than total minted");
        
        // Get current virtual reserves state
        (uint256 currentVirtualUsdtNatural, uint256 currentVirtualTokensNatural) = _getCurrentVirtualReserves(tokenAddress);
        
        // Convert wei to natural units for calculation
        uint256 tokenAmountNatural = tokenAmount / 1e18;
        
        // Virtual state after selling tokens (natural units)
        // When selling, virtual tokens increase and virtual USDT decreases
        uint256 newVirtualTokensNatural = currentVirtualTokensNatural + tokenAmountNatural;
        uint256 newVirtualUsdtNatural = BONDING_CURVE_K / newVirtualTokensNatural;
        
        // USDT to return in natural units
        uint256 usdtToReturnNatural = currentVirtualUsdtNatural - newVirtualUsdtNatural;
        
        // Convert back to wei for return
        usdtToReturn = usdtToReturnNatural * 1e18;
        
        return usdtToReturn;
    }
    
    /// @notice Sell tokens back to the bonding curve for USDT
    /// @param tokenAddress The address of the token to sell
    /// @param tokenAmount The amount of tokens to sell
    /// @return usdtReceived The amount of USDT received
    function sellTokens(address tokenAddress, uint256 tokenAmount) external returns (uint256 usdtReceived) {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(!isTokenGraduated(tokenAddress), "Token has graduated - use normal swaps instead");
        require(MockERC20(tokenAddress).balanceOf(msg.sender) >= tokenAmount, "Insufficient token balance");
        
        // Can't sell more than what was minted via bonding curve
        require(tokenAmount <= totalMinted[tokenAddress], "Cannot sell more than total minted");
        
        // Calculate USDT to return using inverse bonding curve
        usdtReceived = calculateUsdtToReturn(tokenAddress, tokenAmount);
        require(usdtReceived > 0, "No USDT to return");
        
        // Make sure we have enough USDT in the contract
        require(MockERC20(usdt).balanceOf(address(this)) >= usdtReceived, "Insufficient USDT in contract");
        
        // Transfer tokens from user to this contract then burn them
        MockERC20(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
        MockERC20(tokenAddress).burn(address(this), tokenAmount);
        
        // Transfer USDT to user
        MockERC20(usdt).transfer(msg.sender, usdtReceived);
        
        // Update tracking
        totalMinted[tokenAddress] -= tokenAmount;
        totalUsdtRaised[tokenAddress] -= usdtReceived;
        
        return usdtReceived;
    }
    
    /// @notice Internal function to create pool and add liquidity using PositionManager
    /// @param tokenAddress The token address
    function _addLiquidityToPool(address tokenAddress) internal {
        // Create the pool key for graduation (not stored during token creation)
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
        
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3% fee
            tickSpacing: 60, // Standard tick spacing for 0.3% fee
            hooks: this // Use this hook contract
        });
        
        // Use all accumulated USDT for this token
        uint256 usdtAmount = totalUsdtRaised[tokenAddress];
        require(usdtAmount > 0, "No USDT to add as liquidity");
        
        // Calculate remaining tokens for liquidity (1B total - already minted)
        uint256 alreadyMinted = totalMinted[tokenAddress];
        require(alreadyMinted < TOTAL_TOKEN_SUPPLY, "Total supply exceeded");
        uint256 tokensForLiquidity = TOTAL_TOKEN_SUPPLY - alreadyMinted;
        
        // Mint tokens for liquidity to this contract
        MockERC20(tokenAddress).mint(address(this), tokensForLiquidity);
        
        // Get current bonding curve price (USDT per token in wei)
        uint256 usdtPerTokenWei = getCurrentBondingCurvePrice(tokenAddress);
        
        // Calculate sqrtPriceX96 using Uniswap V3 formula: sqrtPriceX96 = sqrt(price) × 2^96
        uint160 sqrtPriceX96;
        
        if (Currency.unwrap(key.currency0) == tokenAddress) {
            // token is currency0, USDT is currency1
            // price = currency1/currency0 = USDT/token 
            // Convert wei to actual price: actualPrice = usdtPerTokenWei / 1e18
            // sqrtPriceX96 = sqrt(actualPrice) × 2^96 = sqrt(usdtPerTokenWei / 1e18) × 2^96
            uint256 sqrtPrice = sqrt(usdtPerTokenWei); // sqrt of price in wei
            sqrtPriceX96 = uint160((sqrtPrice * (2**96)) / 1e9); // Divide by sqrt(1e18) = 1e9
        } else {
            // USDT is currency0, token is currency1  
            // price = currency1/currency0 = token/USDT = 1/actualPrice
            // actualPrice = usdtPerTokenWei / 1e18, so inversePrice = 1e18 / usdtPerTokenWei  
            // sqrtPriceX96 = sqrt(1e18 / usdtPerTokenWei) × 2^96
            uint256 sqrtInversePrice = sqrt((1e18 * 1e18) / usdtPerTokenWei); // sqrt of inverse price in wei
            sqrtPriceX96 = uint160((sqrtInversePrice * (2**96)) / 1e9); // Divide by sqrt(1e18) = 1e9
        }
        
        // Create the pool with the starting sqrt price
        poolManager.initialize(key, sqrtPriceX96);
        
        // Store the pool mappings now that pool is created
        PoolId poolId = key.toId();
        poolToToken[poolId] = tokenAddress;
        tokenToPoolKey[tokenAddress] = key;
        
        // Now get the tick for liquidity calculations
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
        require(totalUsdtRaised[tokenAddress] >= USDT_GRADUATION_THRESHOLD, "USDT threshold not met");
        require(!liquidityAdded[tokenAddress], "Liquidity already added");
        
        _addLiquidityToPool(tokenAddress);
        liquidityAdded[tokenAddress] = true;
        
        // Emit graduation event
        emit TokenGraduated(tokenAddress, totalMinted[tokenAddress], totalUsdtRaised[tokenAddress]);
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Get the token address for this pool
        PoolId poolId = key.toId();
        address tokenAddress = poolToToken[poolId];
        
        // If this is one of our bonding curve tokens, check graduation status
        if (tokenAddress != address(0)) {
            require(liquidityAdded[tokenAddress], "Token still in bonding curve phase - use buyTokens() instead of swaps");
        }
        
        // Allow swap to proceed normally for graduated tokens
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }





}
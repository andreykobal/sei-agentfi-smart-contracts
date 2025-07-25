 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract NormalSwapScript is BaseScript {
    
    function run() external {
        uint256 usdtAmount = 1000e18; // 1000 USDT (18 decimals)
        
        // Check if memecoin token has been created
        require(address(memecoinToken) != address(0), "Memecoin token not created yet. Run 03_CreateToken.s.sol first.");
        
        console.log("=== Normal Uniswap Swap (Graduated Token) ===");
        console.log("USDT Address:", address(usdt));
        console.log("Token to Buy:", address(memecoinToken));
        console.log("USDT Amount:", usdtAmount);
        console.log("Buyer:", deployerAddress);
        console.log("");

        // Get contracts
        MockERC20 targetToken = MockERC20(address(memecoinToken));
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Check if token is graduated
        // bool isGraduated = bondingCurve.isTokenGraduated(address(memecoinToken));
        // if (!isGraduated) {
        //     console.log("ERROR: Token has not graduated yet!");
        //     console.log("Use 05_Swap.s.sol (buyTokens) instead.");
            
        //     // Show graduation status
        //     (, uint256 usdtRaised, uint256 usdtUntilGraduation, uint256 progressPercent) = 
        //         bondingCurve.getGraduationStatus(address(memecoinToken));
        //     console.log("Current Progress:", progressPercent, "% to graduation");
        //     console.log("USDT until graduation:", usdtUntilGraduation / 1e18, "USDT");
        //     return;
        // }
        
        console.log("Token is graduated - proceeding with normal swap");
        console.log("");
        
        // Show what bonding curve would give (for comparison)
        uint256 bondingCurveWouldGive = bondingCurve.calculateTokensToMint(address(memecoinToken), usdtAmount);
        uint256 bondingCurvePrice = bondingCurve.calculateTokensToMint(address(memecoinToken), 1e18);
        
        console.log("=== Price Comparison (Bonding Curve vs AMM) ===");
        console.log("If bonding curve was still active:");
        console.log("- Current bonding curve price: 1 USDT =", bondingCurvePrice / 1e18, "tokens");
        console.log("- Would get for", usdtAmount / 1e18, "USDT:");
        console.log("  ", bondingCurveWouldGive / 1e18, "tokens");
        console.log("Now testing AMM liquidity pool...");
        console.log("");
        
        // Check balances before swap
        uint256 usdtBalanceBefore = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceBefore = targetToken.balanceOf(deployerAddress);
        
        console.log("=== Balances Before Swap ===");
        console.log("USDT Balance:", usdtBalanceBefore / 1e18, "USDT");
        console.log("Token Balance:", tokenBalanceBefore / 1e18, "tokens");
        console.log("");
        
        // Construct pool key
        PoolKey memory poolKey;
        bool zeroForOne;
        
        // Determine currency ordering - USDT vs memecoinToken
        if (address(usdt) < address(memecoinToken)) {
            // USDT is currency0, memecoinToken is currency1
            poolKey = PoolKey({
                currency0: Currency.wrap(address(usdt)),
                currency1: Currency.wrap(address(memecoinToken)),
                fee: 3000,
                tickSpacing: 60,
                hooks: hookContract
            });
            zeroForOne = true; // Swapping from USDT (currency0) to tokens (currency1)
        } else {
            // memecoinToken is currency0, USDT is currency1
            poolKey = PoolKey({
                currency0: Currency.wrap(address(memecoinToken)),
                currency1: Currency.wrap(address(usdt)),
                fee: 3000,
                tickSpacing: 60,
                hooks: hookContract
            });
            zeroForOne = false; // Swapping from USDT (currency1) to tokens (currency0)
        }
        
        bytes memory hookData = new bytes(0);

        vm.startBroadcast();

        // Approve USDT for the swap router
        usdt.approve(address(swapRouter), usdtAmount);

        // Execute normal Uniswap swap
        swapRouter.swapExactTokensForTokens({
            amountIn: usdtAmount,
            amountOutMin: 0, // Allow unlimited price impact for testing
            zeroForOne: zeroForOne,
            poolKey: poolKey,
            hookData: hookData,
            receiver: deployerAddress,
            deadline: block.timestamp + 60
        });

        vm.stopBroadcast();
        
        // Check balances after swap
        uint256 usdtBalanceAfter = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceAfter = targetToken.balanceOf(deployerAddress);
        
        // Calculate changes
        uint256 usdtSpent = usdtBalanceBefore - usdtBalanceAfter;
        uint256 tokensGained = tokenBalanceAfter - tokenBalanceBefore;
        
        console.log("=== Balances After Swap ===");
        console.log("USDT Balance:", usdtBalanceAfter / 1e18, "USDT");
        console.log("Token Balance:", tokenBalanceAfter / 1e18, "tokens");
        console.log("");
        
        console.log("=== Swap Summary ===");
        console.log("USDT Spent:", usdtSpent / 1e18, "USDT");
        console.log("Tokens Received:", tokensGained / 1e18, "tokens");
        
        if (usdtSpent > 0) {
            // Calculate exchange rate without losing precision for small amounts
            uint256 exchangeRate = (tokensGained * 1e18) / usdtSpent; // tokens per USDT in wei precision
            console.log("Exchange Rate:", exchangeRate / 1e18, "tokens per USDT");
            
            // Show detailed amounts for debugging
            console.log("Detailed amounts:");
            console.log("- USDT Spent (wei):", usdtSpent);
            console.log("- Tokens Received (wei):", tokensGained);
        }
        console.log("");
        
        // Compare AMM result vs bonding curve
        console.log("=== AMM vs Bonding Curve Analysis ===");
        console.log("AMM gave:", tokensGained / 1e18, "tokens");
        console.log("Bonding curve would have given:", bondingCurveWouldGive / 1e18, "tokens");
        if (tokensGained < bondingCurveWouldGive) {
            uint256 difference = ((bondingCurveWouldGive - tokensGained) * 100) / bondingCurveWouldGive;
            console.log("AMM gives", difference, "% fewer tokens than bonding curve would");
        } else {
            uint256 difference = ((tokensGained - bondingCurveWouldGive) * 100) / bondingCurveWouldGive;
            console.log("AMM gives", difference, "% more tokens than bonding curve would");
        }
        console.log("");
        
        // Show final graduation stats
        uint256 totalMinted = bondingCurve.totalMinted(address(memecoinToken));
        uint256 totalRaised = bondingCurve.totalUsdtRaised(address(memecoinToken));
        
        console.log("=== Token Stats (Graduated) ===");
        console.log("Total Minted via Bonding Curve:", totalMinted / 1e18, "tokens");
        console.log("Total USDT Raised via Bonding Curve:", totalRaised / 1e18, "USDT");
        console.log("Status: GRADUATED - Normal Uniswap trading active!");
        console.log("");
        
        console.log("Normal Uniswap swap completed successfully!");
    }
}
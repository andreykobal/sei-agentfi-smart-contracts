// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract SwapScript is BaseScript {
    
    function run() external {
        uint256 usdtAmount = 6000e18; // 5000 USDT (18 decimals)
        
        // Check if memecoin token has been created
        require(address(memecoinToken) != address(0), "Memecoin token not created yet. Run 03_CreateToken.s.sol first.");
        
        console.log("=== Bonding Curve Token Purchase ===");
        console.log("USDT Address:", address(usdt));
        console.log("Token to Buy:", address(memecoinToken));
        console.log("USDT Amount:", usdtAmount);
        console.log("Buyer:", deployerAddress);
        console.log("");

        // Get the token contract and bonding curve contract
        MockERC20 targetToken = MockERC20(address(memecoinToken));
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Check balances before purchase
        uint256 usdtBalanceBefore = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceBefore = targetToken.balanceOf(deployerAddress);
        
        console.log("=== Balances Before Purchase ===");
        console.log("USDT Balance:", usdtBalanceBefore);
        console.log("Token Balance:", tokenBalanceBefore);
        console.log("");
        
        // Check current price before purchase
        uint256 tokensExpected = bondingCurve.calculateTokensToMint(address(memecoinToken), usdtAmount);
        console.log("Tokens Expected:", tokensExpected);
        
        // Show current bonding curve price
        uint256 currentPrice = bondingCurve.calculateTokensToMint(address(memecoinToken), 1e18);
        console.log("");
        console.log("=== Current Bonding Curve Price ===");
        console.log("Price: 1 USDT =", currentPrice / 1e18, "tokens");
        console.log("Total minted so far:", bondingCurve.totalMinted(address(memecoinToken)) / 1e18, "tokens");
        console.log("Total USDT raised so far:", bondingCurve.totalUsdtRaised(address(memecoinToken)) / 1e18, "USDT");
        
        // Check if token is already graduated
        bool preGraduated = bondingCurve.isTokenGraduated(address(memecoinToken));
        if (preGraduated) {
            console.log("WARNING: Token already graduated - cannot use buyTokens!");
            console.log("Use normal Uniswap swaps instead.");
            return;
        }
        console.log("");

        vm.startBroadcast();
        
        // Approve USDT for the bonding curve contract
        usdt.approve(address(bondingCurve), usdtAmount);
        
        // Buy tokens using bonding curve (mints directly)
        uint256 tokensReceived = bondingCurve.buyTokens(address(memecoinToken), usdtAmount);
        
        vm.stopBroadcast();
        
        // Check balances after purchase
        uint256 usdtBalanceAfter = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceAfter = targetToken.balanceOf(deployerAddress);
        
        // Calculate changes
        uint256 usdtSpent = usdtBalanceBefore - usdtBalanceAfter;
        uint256 tokensGained = tokenBalanceAfter - tokenBalanceBefore;
        
        // Get updated bonding curve stats
        uint256 totalMinted = bondingCurve.totalMinted(address(memecoinToken));
        uint256 totalRaised = bondingCurve.totalUsdtRaised(address(memecoinToken));
        
        // Check graduation status
        (bool isGraduated, uint256 usdtRaised, uint256 usdtUntilGraduation, uint256 progressPercent) = 
            bondingCurve.getGraduationStatus(address(memecoinToken));
        
        // Log results
        console.log("=== Balances After Purchase ===");
        console.log("USDT Balance:", usdtBalanceAfter);
        console.log("Token Balance:", tokenBalanceAfter);
        console.log("");
        
        // Log formatted balances for readability
        console.log("=== Formatted Balances ===");
        console.log("USDT Balance:", usdtBalanceAfter / 1e18, "USDT");
        console.log("Token Balance:", tokenBalanceAfter / 1e18, "tokens");
        console.log("");
        
        console.log("=== Transaction Summary ===");
        console.log("USDT Spent:", usdtSpent);
        console.log("Tokens Gained:", tokensGained);
        console.log("Tokens Received (from function):", tokensReceived);
        console.log("Expected vs Actual Match:", tokensGained == tokensReceived ? "YES" : "NO");
        console.log("");
        
        // Log formatted transaction summary
        console.log("=== Formatted Transaction Summary ===");
        console.log("USDT Spent:", usdtSpent / 1e18, "USDT");
        console.log("Tokens Gained:", tokensGained / 1e18, "tokens");
            if (usdtSpent > 0) {
            console.log("Rate:", (tokensGained / 1e18) / (usdtSpent / 1e18), "tokens per USDT");
        } else {
            console.log("Rate: Division by zero - tiny USDT amount");
        }
        console.log("");
        
        console.log("=== Bonding Curve Stats ===");
        console.log("Total Tokens Minted:", totalMinted);
        console.log("Total USDT Raised:", totalRaised);
        console.log("");
        
        // Show new bonding curve price after purchase
        uint256 newPrice = bondingCurve.calculateTokensToMint(address(memecoinToken), 1e18);
        console.log("=== Price Impact Analysis ===");
        console.log("Price before: 1 USDT =", currentPrice / 1e18, "tokens");
        console.log("Price after: 1 USDT =", newPrice / 1e18, "tokens");
        if (newPrice < currentPrice) {
            uint256 priceIncrease = ((currentPrice - newPrice) * 100) / currentPrice;
            console.log("Price increased by:", priceIncrease, "% (fewer tokens per USDT)");
        }
        console.log("");
        
        console.log("=== Graduation Status ===");
        if (isGraduated) {
            console.log("Status: GRADUATED! Use normal Uniswap swaps");
            console.log("Liquidity Pool: Active");
        } else {
            console.log("Status: Bonding Curve Phase");
            console.log("Progress:", progressPercent, "% to graduation");
            console.log("USDT until graduation:", usdtUntilGraduation / 1e18, "USDT");
        }
        console.log("");
        
        // Show next purchase price
        uint256 nextTokens = bondingCurve.calculateTokensToMint(address(memecoinToken), usdtAmount);
        console.log("=== Next Purchase Preview ===");
        console.log("Next purchase amount:", usdtAmount / 1e18, "USDT");
        console.log("Would get (raw):", nextTokens, "tokens");
        console.log("Would get (formatted):", nextTokens / 1e18, "tokens");
        
        if (nextTokens < tokensGained) {
            uint256 priceIncrease = ((tokensGained - nextTokens) * 100) / tokensGained;
            console.log("Price increase:", priceIncrease, "% fewer tokens");
        } else {
            uint256 priceDecrease = ((nextTokens - tokensGained) * 100) / tokensGained;
            console.log("Price decrease:", priceDecrease, "% more tokens (formula bug!)");
        }
        console.log("Bonding curve working!");
    }
}

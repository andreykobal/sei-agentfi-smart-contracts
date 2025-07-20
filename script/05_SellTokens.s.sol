 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract SellTokensScript is BaseScript {
    
    function run() external {
        uint256 tokenAmountToSell = 100_000_000 * 1e18; // 100 million tokens
        
        // Check if memecoin token has been created
        require(address(memecoinToken) != address(0), "Memecoin token not created yet. Run 03_CreateToken.s.sol first.");
        
        console.log("=== Bonding Curve Token Sale ===");
        console.log("USDT Address:", address(usdt));
        console.log("Token to Sell:", address(memecoinToken));
        console.log("Token Amount to Sell:", tokenAmountToSell);
        console.log("Seller:", deployerAddress);
        console.log("");

        // Get the token contract and bonding curve contract
        MockERC20 targetToken = MockERC20(address(memecoinToken));
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Check if token is graduated
        bool isGraduated = bondingCurve.isTokenGraduated(address(memecoinToken));
        if (isGraduated) {
            console.log("ERROR: Token already graduated - cannot use sellTokens!");
            console.log("Use normal Uniswap swaps instead.");
            return;
        }
        
        // Check balances before sale
        uint256 usdtBalanceBefore = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceBefore = targetToken.balanceOf(deployerAddress);
        uint256 contractUsdtBalance = usdt.balanceOf(address(bondingCurve));
        
        console.log("=== Balances Before Sale ===");
        console.log("User USDT Balance:", usdtBalanceBefore / 1e18, "USDT");
        console.log("User Token Balance:", tokenBalanceBefore / 1e18, "tokens");
        console.log("Contract USDT Balance:", contractUsdtBalance / 1e18, "USDT");
        console.log("");
        
        // Check if user has enough tokens to sell
        if (tokenBalanceBefore < tokenAmountToSell) {
            console.log("ERROR: Insufficient token balance!");
            console.log("You have:", tokenBalanceBefore / 1e18, "tokens");
            console.log("Trying to sell:", tokenAmountToSell / 1e18, "tokens");
            console.log("Run 05_Swap.s.sol first to buy tokens.");
            return;
        }
        
        // Check current bonding curve stats
        uint256 totalMintedBefore = bondingCurve.totalMinted(address(memecoinToken));
        uint256 totalRaisedBefore = bondingCurve.totalUsdtRaised(address(memecoinToken));
        
        console.log("=== Current Bonding Curve Stats ===");
        console.log("Total Minted:", totalMintedBefore / 1e18, "tokens");
        console.log("Total USDT Raised:", totalRaisedBefore / 1e18, "USDT");
        console.log("");
        
        // Calculate expected USDT return
        uint256 expectedUsdtReturn = bondingCurve.calculateUsdtToReturn(address(memecoinToken), tokenAmountToSell);
        console.log("=== Expected Sale Results ===");
        console.log("Tokens to Sell:", tokenAmountToSell / 1e18, "tokens");
        console.log("Expected USDT Return:", expectedUsdtReturn / 1e18, "USDT");
        
        if (expectedUsdtReturn > 0) {
            uint256 pricePerToken = (expectedUsdtReturn * 1e18) / tokenAmountToSell;
            console.log("Effective Price:", pricePerToken / 1e18, "USDT per token");
        }
        console.log("");
        
        // Check if contract has enough USDT to pay
        if (contractUsdtBalance < expectedUsdtReturn) {
            console.log("ERROR: Contract has insufficient USDT!");
            console.log("Contract has:", contractUsdtBalance / 1e18, "USDT");
            console.log("Sale requires:", expectedUsdtReturn / 1e18, "USDT");
            return;
        }

        vm.startBroadcast();
        
        // Approve tokens for the bonding curve contract
        targetToken.approve(address(bondingCurve), tokenAmountToSell);
        
        // Sell tokens to bonding curve
        uint256 usdtReceived = bondingCurve.sellTokens(address(memecoinToken), tokenAmountToSell);
        
        vm.stopBroadcast();
        
        // Check balances after sale
        uint256 usdtBalanceAfter = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceAfter = targetToken.balanceOf(deployerAddress);
        uint256 contractUsdtBalanceAfter = usdt.balanceOf(address(bondingCurve));
        
        // Calculate changes
        uint256 usdtGained = usdtBalanceAfter - usdtBalanceBefore;
        uint256 tokensSold = tokenBalanceBefore - tokenBalanceAfter;
        uint256 contractUsdtSpent = contractUsdtBalance - contractUsdtBalanceAfter;
        
        // Get updated bonding curve stats
        uint256 totalMintedAfter = bondingCurve.totalMinted(address(memecoinToken));
        uint256 totalRaisedAfter = bondingCurve.totalUsdtRaised(address(memecoinToken));
        
        console.log("=== Balances After Sale ===");
        console.log("User USDT Balance:", usdtBalanceAfter / 1e18, "USDT");
        console.log("User Token Balance:", tokenBalanceAfter / 1e18, "tokens");
        console.log("Contract USDT Balance:", contractUsdtBalanceAfter / 1e18, "USDT");
        console.log("");
        
        console.log("=== Transaction Summary ===");
        console.log("Tokens Sold:", tokensSold / 1e18, "tokens");
        console.log("USDT Gained:", usdtGained / 1e18, "USDT");
        console.log("USDT Received (from function):", usdtReceived / 1e18, "USDT");
        console.log("Contract USDT Spent:", contractUsdtSpent / 1e18, "USDT");
        console.log("Expected vs Actual Match:", usdtGained == usdtReceived ? "YES" : "NO");
        console.log("Expected vs Received Match:", expectedUsdtReturn == usdtReceived ? "YES" : "NO");
        
        if (tokensSold > 0 && usdtGained > 0) {
            uint256 effectivePrice = (usdtGained * 1e18) / tokensSold;
            console.log("Effective Sale Price:", effectivePrice / 1e18, "USDT per token");
        }
        console.log("");
        
        console.log("=== Updated Bonding Curve Stats ===");
        console.log("Total Minted Before:", totalMintedBefore / 1e18, "tokens");
        console.log("Total Minted After:", totalMintedAfter / 1e18, "tokens");
        console.log("Tokens Burned:", (totalMintedBefore - totalMintedAfter) / 1e18, "tokens");
        console.log("");
        console.log("Total USDT Raised Before:", totalRaisedBefore / 1e18, "USDT");
        console.log("Total USDT Raised After:", totalRaisedAfter / 1e18, "USDT");
        console.log("USDT Reduction:", (totalRaisedBefore - totalRaisedAfter) / 1e18, "USDT");
        console.log("");
        
        // Check graduation status after sale
        (bool isGraduatedAfter, uint256 usdtRaised, uint256 usdtUntilGraduation, uint256 progressPercent) = 
            bondingCurve.getGraduationStatus(address(memecoinToken));
        
        console.log("=== Graduation Status After Sale ===");
        if (isGraduatedAfter) {
            console.log("Status: GRADUATED! Use normal Uniswap swaps");
        } else {
            console.log("Status: Bonding Curve Phase");
            console.log("Progress:", progressPercent, "% to graduation");
            console.log("USDT until graduation:", usdtUntilGraduation / 1e18, "USDT");
        }
        console.log("");
        
        // Show price impact analysis
        if (!isGraduatedAfter) {
            uint256 newPrice = bondingCurve.calculateTokensToMint(address(memecoinToken), 1e18);
            console.log("=== Price Impact Analysis ===");
            console.log("Current Price: 1 USDT =", newPrice / 1e18, "tokens");
            
            // Test next sell
            uint256 nextSellAmount = 10_000_000 * 1e18; // 10M tokens
            if (tokenBalanceAfter >= nextSellAmount) {
                uint256 nextUsdtReturn = bondingCurve.calculateUsdtToReturn(address(memecoinToken), nextSellAmount);
                console.log("Next 10M token sale would return:", nextUsdtReturn / 1e18, "USDT");
                
                uint256 nextEffectivePrice = (nextUsdtReturn * 1e18) / nextSellAmount;
                console.log("Next sale price:", nextEffectivePrice / 1e18, "USDT per token");
            }
        }
        
        console.log("Selling test completed!");
    }
}
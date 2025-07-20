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
    // Hardcoded second token address - update this as needed
    address constant OTHER_TOKEN = 0x9b3D7F849E1C6cFb07Eba7C14aC3556243Fc0C77; // Update this address as needed
    
    function run() external {
        uint256 usdtAmount = 1000e18; // 1000 USDT (18 decimals)
        
        console.log("=== Bonding Curve Token Purchase ===");
        console.log("USDT Address:", address(usdt));
        console.log("Token to Buy:", OTHER_TOKEN);
        console.log("USDT Amount:", usdtAmount);
        console.log("Buyer:", deployerAddress);
        console.log("");

        // Get the token contract and bonding curve contract
        MockERC20 targetToken = MockERC20(OTHER_TOKEN);
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Check balances before purchase
        uint256 usdtBalanceBefore = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceBefore = targetToken.balanceOf(deployerAddress);
        
        console.log("=== Balances Before Purchase ===");
        console.log("USDT Balance:", usdtBalanceBefore);
        console.log("Token Balance:", tokenBalanceBefore);
        console.log("");
        
        // Check current price before purchase
        uint256 tokensExpected = bondingCurve.calculateTokensToMint(OTHER_TOKEN, usdtAmount);
        console.log("Tokens Expected:", tokensExpected);
        console.log("");

        vm.startBroadcast();
        
        // Approve USDT for the bonding curve contract
        usdt.approve(address(bondingCurve), usdtAmount);
        
        // Buy tokens using bonding curve (mints directly)
        uint256 tokensReceived = bondingCurve.buyTokens(OTHER_TOKEN, usdtAmount);
        
        vm.stopBroadcast();
        
        // Check balances after purchase
        uint256 usdtBalanceAfter = usdt.balanceOf(deployerAddress);
        uint256 tokenBalanceAfter = targetToken.balanceOf(deployerAddress);
        
        // Calculate changes
        uint256 usdtSpent = usdtBalanceBefore - usdtBalanceAfter;
        uint256 tokensGained = tokenBalanceAfter - tokenBalanceBefore;
        
        // Get updated bonding curve stats
        uint256 totalMinted = bondingCurve.totalMinted(OTHER_TOKEN);
        uint256 totalRaised = bondingCurve.totalUsdtRaised(OTHER_TOKEN);
        
        // Log results
        console.log("=== Balances After Purchase ===");
        console.log("USDT Balance:", usdtBalanceAfter);
        console.log("Token Balance:", tokenBalanceAfter);
        console.log("");
        
        console.log("=== Transaction Summary ===");
        console.log("USDT Spent:", usdtSpent);
        console.log("Tokens Gained:", tokensGained);
        console.log("Tokens Received (from function):", tokensReceived);
        console.log("Expected vs Actual Match:", tokensGained == tokensReceived ? "YES" : "NO");
        console.log("");
        
        console.log("=== Bonding Curve Stats ===");
        console.log("Total Tokens Minted:", totalMinted);
        console.log("Total USDT Raised:", totalRaised);
        console.log("");
        
        // Show next purchase price
        uint256 nextTokens = bondingCurve.calculateTokensToMint(OTHER_TOKEN, usdtAmount);
        console.log("=== Next Purchase Preview ===");
        console.log("Next 100 USDT would get:", nextTokens, "tokens");
        
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

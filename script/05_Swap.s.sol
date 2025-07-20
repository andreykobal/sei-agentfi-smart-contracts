// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {BondingCurve} from "../src/BondingCurve.sol";

contract SwapScript is BaseScript {
    // Hardcoded second token address - update this as needed
    address constant OTHER_TOKEN = 0x532B02BD614Fd18aEE45603d02866cFb77575CB3; // Update this address as needed
    
    function run() external {
        uint256 usdtAmount = 100e18; // 100 USDT (18 decimals)
        
        console.log("=== Bonding Curve Token Purchase ===");
        console.log("USDT Address:", address(usdt));
        console.log("Token to Buy:", OTHER_TOKEN);
        console.log("USDT Amount:", usdtAmount);
        console.log("Buyer:", deployerAddress);
        console.log("");

        vm.startBroadcast();

        // Get the bonding curve contract (our hook)
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Check current price before purchase
        uint256 tokensBefore = bondingCurve.calculateTokensToMint(OTHER_TOKEN, usdtAmount);
        console.log("Tokens to receive:", tokensBefore);
        
        // Approve USDT for the bonding curve contract
        usdt.approve(address(bondingCurve), usdtAmount);
        
        // Buy tokens using bonding curve (mints directly)
        uint256 tokensReceived = bondingCurve.buyTokens(OTHER_TOKEN, usdtAmount);
        
        // Get updated stats
        uint256 totalMinted = bondingCurve.totalMinted(OTHER_TOKEN);
        uint256 totalRaised = bondingCurve.totalUsdtRaised(OTHER_TOKEN);
        
        vm.stopBroadcast();
        
        // Log results
        console.log("=== Purchase Complete ===");
        console.log("Tokens Received:", tokensReceived);
        console.log("Total Tokens Minted:", totalMinted);
        console.log("Total USDT Raised:", totalRaised);
        console.log("");
        
        // Show next purchase price
        uint256 nextTokens = bondingCurve.calculateTokensToMint(OTHER_TOKEN, usdtAmount);
        console.log("Next 100 USDT would get:", nextTokens, "tokens");
        console.log("Price increase due to bonding curve!");
    }
}

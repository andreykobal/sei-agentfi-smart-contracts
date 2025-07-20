  // SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/Script.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Script to create a new token for bonding curve trading
contract CreateToken is BaseScript {
    
    // Token parameters - modify these as needed
    string constant TOKEN_NAME = "Doge Moon";
    string constant TOKEN_SYMBOL = "DOGEM";
    uint256 constant INITIAL_SUPPLY = 1_000_000e18; // 1 million tokens to creator
    
    function run() external {
        console.log("=== Creating Token for Bonding Curve ===");
        console.log("Creator:", deployerAddress);
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Token Details:");
        console.log("- Name:", TOKEN_NAME);
        console.log("- Symbol:", TOKEN_SYMBOL);
        console.log("- Initial Supply:", INITIAL_SUPPLY);
        console.log("");

        vm.startBroadcast();

        // Get the bonding curve contract (our hook)
        BondingCurve bondingCurve = BondingCurve(address(hookContract));
        
        // Create the token (pool will be created later at graduation)
        address tokenAddress = bondingCurve.createToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            INITIAL_SUPPLY
        );

        vm.stopBroadcast();

        // Get token details
        MockERC20 newToken = MockERC20(tokenAddress);
        
        // Save token address to JSON
        saveTokenToJson(tokenAddress);
        
        // Log the results
        console.log("=== Token Created Successfully ===");
        console.log("Token Address:", tokenAddress);
        console.log("");
        console.log("Token Info:");
        console.log("- Name:", newToken.name());
        console.log("- Symbol:", newToken.symbol());
        console.log("- Decimals:", newToken.decimals());
        console.log("- Total Supply:", newToken.totalSupply());
        console.log("- Creator Balance:", newToken.balanceOf(deployerAddress));
        console.log("");
        console.log("Trading Info:");
        console.log("- Paired with USDT:", address(usdt));
        console.log("- Pool will be created at graduation with correct price");
        console.log("- No pool exists yet (tokens minted via bonding curve)");
        console.log("- Graduation threshold: 200M tokens");
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Token address automatically saved to deployments JSON");
        console.log("2. Run 05_Swap.s.sol to buy tokens using bonding curve");
        console.log("3. Token price will increase with each purchase!");
        console.log("4. At 200M tokens, pool will be created automatically!");
        console.log("");
        console.log("=== Bonding Curve Stats ===");
        console.log("Total Minted (via curve):", bondingCurve.totalMinted(tokenAddress));
        console.log("Total USDT Raised:", bondingCurve.totalUsdtRaised(tokenAddress));
        
        // Show example pricing
        uint256 exampleTokens100 = bondingCurve.calculateTokensToMint(tokenAddress, 100e18);
        uint256 exampleTokens1000 = bondingCurve.calculateTokensToMint(tokenAddress, 1000e18);
        console.log("");
        console.log("Example Pricing (current):");
        console.log("- 100 USDT would get:", exampleTokens100, "tokens");
        console.log("- 1000 USDT would get:", exampleTokens1000, "tokens");
    }

    function saveTokenToJson(address tokenAddress) internal {
        // Read existing deployment file
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        
        require(vm.exists(deploymentPath), string.concat("Deployment file not found: ", deploymentPath));
        
        string memory existingJson = vm.readFile(deploymentPath);
        
        // Create new JSON with memecoin token address added
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", vm.parseJsonUint(existingJson, ".chainId"));
        vm.serializeAddress(json, "permit2", vm.parseJsonAddress(existingJson, ".permit2"));
        vm.serializeAddress(json, "poolManager", vm.parseJsonAddress(existingJson, ".poolManager"));
        vm.serializeAddress(json, "positionManager", vm.parseJsonAddress(existingJson, ".positionManager"));
        vm.serializeAddress(json, "v4Router", vm.parseJsonAddress(existingJson, ".v4Router"));
        vm.serializeAddress(json, "tokenFactory", vm.parseJsonAddress(existingJson, ".tokenFactory"));
        vm.serializeAddress(json, "usdt", vm.parseJsonAddress(existingJson, ".usdt"));
        vm.serializeAddress(json, "hookContract", vm.parseJsonAddress(existingJson, ".hookContract"));
        string memory finalJson = vm.serializeAddress(json, "memecoinToken", tokenAddress);
        
        // Write updated file
        vm.writeFile(deploymentPath, finalJson);
        
        console.log("Memecoin token address saved to:", deploymentPath);
        console.log("");
    }
}
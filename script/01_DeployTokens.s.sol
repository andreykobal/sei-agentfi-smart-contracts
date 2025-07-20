// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TokenFactory} from "../src/TokenFactory.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Script to deploy USDT token using the TokenFactory
/// @dev This script deploys the TokenFactory and creates only USDT token
contract DeployTokens is Script {
    // Deployed contracts
    TokenFactory public tokenFactory;
    MockERC20 public usdt;

    // Token parameters
    address public owner;
    uint256 public constant USDT_SUPPLY = 1_000_000_000 * 1e18; // 1 billion USDT (18 decimals)

    function run() public {
        // Get deployer address
        owner = msg.sender;
        
        console.log("=== Deploying USDT Token using TokenFactory ===");
        console.log("Deployer:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy TokenFactory
        deployTokenFactory();

        // 2. Create USDT token (18 decimals)
        createUSDTToken();

        vm.stopBroadcast();

        // Save deployment addresses to JSON
        saveTokenDeploymentToJson();

        // Log all deployed addresses
        logTokenDeploymentSummary();
    }

    function deployTokenFactory() internal {
        console.log("1. Deploying TokenFactory...");
        
        tokenFactory = new TokenFactory();
        
        console.log("   TokenFactory deployed at:", address(tokenFactory));
        console.log("");
    }

    function createUSDTToken() internal {
        console.log("2. Creating USDT Token...");
        
        address usdtAddress = tokenFactory.createToken(
            "Tether USD",
            "USDT",
            18, // USDT using 18 decimals for this implementation
            USDT_SUPPLY
        );
        
        usdt = MockERC20(usdtAddress);
        
        console.log("   USDT created at:", address(usdt));
        console.log("   Name:", usdt.name());
        console.log("   Symbol:", usdt.symbol());
        console.log("   Decimals:", usdt.decimals());
        console.log("   Total Supply:", usdt.totalSupply());
        console.log("   Owner Balance:", usdt.balanceOf(owner));
        console.log("");
    }



    function saveTokenDeploymentToJson() internal {
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        
        // Read existing deployment file if it exists
        string memory existingJson = "";
        if (vm.exists(deploymentPath)) {
            existingJson = vm.readFile(deploymentPath);
        }
        
        // Create or update deployment data structure
        string memory json = "deployment";
        
        // If existing file exists, preserve existing data
        if (bytes(existingJson).length > 0) {
            try vm.parseJsonUint(existingJson, ".chainId") returns (uint256 chainId) {
                vm.serializeUint(json, "chainId", chainId);
            } catch {
                vm.serializeUint(json, "chainId", block.chainid);
            }
            
            try vm.parseJsonAddress(existingJson, ".permit2") returns (address permit2Addr) {
                vm.serializeAddress(json, "permit2", permit2Addr);
            } catch {}
            
            try vm.parseJsonAddress(existingJson, ".poolManager") returns (address poolManagerAddr) {
                vm.serializeAddress(json, "poolManager", poolManagerAddr);
            } catch {}
            
            try vm.parseJsonAddress(existingJson, ".positionManager") returns (address positionManagerAddr) {
                vm.serializeAddress(json, "positionManager", positionManagerAddr);
            } catch {}
            
            try vm.parseJsonAddress(existingJson, ".v4Router") returns (address v4RouterAddr) {
                vm.serializeAddress(json, "v4Router", v4RouterAddr);
            } catch {}
        } else {
            vm.serializeUint(json, "chainId", block.chainid);
        }
        
        // Add token data - only USDT, pair with native ETH
        vm.serializeAddress(json, "tokenFactory", address(tokenFactory));
        string memory finalJson = vm.serializeAddress(json, "usdt", address(usdt));
        
        // Write to file
        vm.writeFile(deploymentPath, finalJson);
        
        console.log("USDT address added to deployment file:", deploymentPath);
        console.log("");
    }

    function logTokenDeploymentSummary() internal view {
        console.log("=== Token Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", owner);
        console.log("");
        console.log("Factory Contract:");
        console.log("- TokenFactory:    ", address(tokenFactory));
        console.log("");
        console.log("Deployed Token:");
        console.log("- USDT:            ", address(usdt));
        console.log("  Name:            ", usdt.name());
        console.log("  Symbol:          ", usdt.symbol());
        console.log("  Decimals:        ", usdt.decimals());
        console.log("  Supply:          ", usdt.totalSupply());
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. USDT will be paired with native ETH for pool creation");
        console.log("2. Initialize pools with USDT/ETH pair using PoolManager");
        console.log("3. Add liquidity to the pools");
        console.log("4. Execute swaps between USDT and ETH");
        console.log("");
        console.log("=== Note ===");
        console.log("USDT address automatically saved to deployments/{chainId}.json");
        console.log("USDT uses 18 decimals with 1 billion initial supply minted to deployer");
        console.log("USDT will be paired with native ETH (address(0)) in pools");
    }

    /// @notice Helper function to get token deployment addresses for other scripts
    function getTokenAddresses() external view returns (
        address _tokenFactory,
        address _usdt
    ) {
        return (
            address(tokenFactory),
            address(usdt)
        );
    }
} 
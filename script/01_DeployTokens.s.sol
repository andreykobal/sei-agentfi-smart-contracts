// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TokenFactory} from "../src/TokenFactory.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Script to deploy tokens using the TokenFactory
/// @dev This script deploys the TokenFactory and creates USDT and TEST tokens
contract DeployTokens is Script {
    // Deployed contracts
    TokenFactory public tokenFactory;
    MockERC20 public usdt;
    MockERC20 public testToken;

    // Token parameters
    address public owner;
    uint256 public constant USDT_SUPPLY = 1_000_000_000 * 1e18; // 1 billion USDT (18 decimals)
    uint256 public constant TEST_SUPPLY = 1_000_000_000 * 1e18; // 1 billion TEST (18 decimals)

    function run() public {
        // Get deployer address
        owner = msg.sender;
        
        console.log("=== Deploying Tokens using TokenFactory ===");
        console.log("Deployer:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy TokenFactory
        deployTokenFactory();

        // 2. Create USDT token (6 decimals, like real USDT)
        createUSDTToken();

        // 3. Create TEST token (18 decimals)
        createTestToken();

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
            6, // USDT typically has 6 decimals
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

    function createTestToken() internal {
        console.log("3. Creating TEST Token...");
        
        address testAddress = tokenFactory.createToken(
            "Test Token",
            "TEST",
            18, // Standard 18 decimals
            TEST_SUPPLY
        );
        
        testToken = MockERC20(testAddress);
        
        console.log("   TEST created at:", address(testToken));
        console.log("   Name:", testToken.name());
        console.log("   Symbol:", testToken.symbol());
        console.log("   Decimals:", testToken.decimals());
        console.log("   Total Supply:", testToken.totalSupply());
        console.log("   Owner Balance:", testToken.balanceOf(owner));
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
        
        // Add token data
        vm.serializeAddress(json, "tokenFactory", address(tokenFactory));
        vm.serializeAddress(json, "token0", address(usdt)); // USDT as token0
        string memory finalJson = vm.serializeAddress(json, "token1", address(testToken)); // TEST as token1
        
        // Write to file
        vm.writeFile(deploymentPath, finalJson);
        
        console.log("Token addresses added to deployment file:", deploymentPath);
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
        console.log("Created Tokens:");
        console.log("- USDT:            ", address(usdt));
        console.log("  Name:            ", usdt.name());
        console.log("  Symbol:          ", usdt.symbol());
        console.log("  Decimals:        ", usdt.decimals());
        console.log("  Supply:          ", usdt.totalSupply());
        console.log("");
        console.log("- TEST:            ", address(testToken));
        console.log("  Name:            ", testToken.name());
        console.log("  Symbol:          ", testToken.symbol());
        console.log("  Decimals:        ", testToken.decimals());
        console.log("  Supply:          ", testToken.totalSupply());
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Use these token addresses in pool creation");
        console.log("2. Initialize pools with these tokens using PoolManager");
        console.log("3. Add liquidity to the pools");
        console.log("4. Execute swaps between USDT and TEST");
        console.log("");
        console.log("=== Note ===");
        console.log("All token addresses automatically saved to deployments/{chainId}.json");
        console.log("USDT uses 6 decimals (like real USDT), TEST uses 18 decimals");
        console.log("Both tokens have 1 billion initial supply minted to deployer");
        console.log("Token addresses are merged with existing infrastructure deployment");
    }

    /// @notice Helper function to get token deployment addresses for other scripts
    function getTokenAddresses() external view returns (
        address _tokenFactory,
        address _usdt,
        address _testToken
    ) {
        return (
            address(tokenFactory),
            address(usdt),
            address(testToken)
        );
    }
} 
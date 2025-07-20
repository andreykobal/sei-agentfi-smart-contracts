// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

// Import deployment artifacts
import {Permit2Deployer} from "hookmate/artifacts/Permit2.sol";
import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";
import {V4PositionManagerDeployer} from "hookmate/artifacts/V4PositionManager.sol";
import {V4RouterDeployer} from "hookmate/artifacts/V4Router.sol";

/// @notice Script to deploy the complete Uniswap v4 infrastructure
/// @dev This script deploys all core contracts needed for a functioning Uniswap v4 ecosystem
contract DeployUniswapV4Infrastructure is Script {
    // Deployed contract addresses
    IPermit2 public permit2;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IUniswapV4Router04 public v4Router;

    // Deployment parameters
    address public owner;
    uint256 public unsubscribeGasLimit = 300_000; // Default gas limit for position manager
    address public positionDescriptor; // Will be address(0) for now, can be set later
    address public wrappedNative; // Will be address(0) for native ETH, update for other chains

    function run() public {
        // Get deployer address
        owner = msg.sender;
        
        console.log("=== Deploying Uniswap v4 Infrastructure ===");
        console.log("Deployer:", owner);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy Permit2 (EIP-712 permit system)
        deployPermit2();

        // 2. Deploy PoolManager (Core contract that manages all pools)
        deployPoolManager();

        // 3. Deploy PositionManager (NFT-based liquidity position manager)
        deployPositionManager();

        // 4. Deploy V4Router (Router for swapping and liquidity operations)
        deployV4Router();

        vm.stopBroadcast();

        // Log all deployed addresses
        logDeploymentSummary();
    }

    function deployPermit2() internal {
        console.log("1. Deploying Permit2...");
        
        address permit2Address = Permit2Deployer.deploy();
        permit2 = IPermit2(permit2Address);
        
        console.log("   Permit2 deployed at:", address(permit2));
        console.log("");
    }

    function deployPoolManager() internal {
        console.log("2. Deploying PoolManager...");
        
        address poolManagerAddress = V4PoolManagerDeployer.deploy(owner);
        poolManager = IPoolManager(poolManagerAddress);
        
        console.log("   PoolManager deployed at:", address(poolManager));
        console.log("   Owner:", owner);
        console.log("");
    }

    function deployPositionManager() internal {
        console.log("3. Deploying PositionManager...");
        
        address positionManagerAddress = V4PositionManagerDeployer.deploy(
            address(poolManager),
            address(permit2),
            unsubscribeGasLimit,
            positionDescriptor, // address(0) for now
            wrappedNative // address(0) for native ETH
        );
        positionManager = IPositionManager(positionManagerAddress);
        
        console.log("   PositionManager deployed at:", address(positionManager));
        console.log("   PoolManager:", address(poolManager));
        console.log("   Permit2:", address(permit2));
        console.log("   Unsubscribe Gas Limit:", unsubscribeGasLimit);
        console.log("   Position Descriptor:", positionDescriptor);
        console.log("   Wrapped Native:", wrappedNative);
        console.log("");
    }

    function deployV4Router() internal {
        console.log("4. Deploying V4Router...");
        
        address v4RouterAddress = V4RouterDeployer.deploy(
            address(poolManager),
            address(permit2)
        );
        v4Router = IUniswapV4Router04(payable(v4RouterAddress));
        
        console.log("   V4Router deployed at:", address(v4Router));
        console.log("   PoolManager:", address(poolManager));
        console.log("   Permit2:", address(permit2));
        console.log("");
    }

    function logDeploymentSummary() internal view {
        console.log("=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", owner);
        console.log("");
        console.log("Core Contracts:");
        console.log("- Permit2:         ", address(permit2));
        console.log("- PoolManager:     ", address(poolManager));
        console.log("- PositionManager: ", address(positionManager));
        console.log("- V4Router:        ", address(v4Router));
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Update your environment with these addresses");
        console.log("2. Deploy any hooks you need");
        console.log("3. Initialize pools using the PoolManager");
        console.log("4. Add liquidity using the PositionManager");
        console.log("5. Execute swaps using the V4Router");
        console.log("");
        console.log("=== Configuration for scripts ===");
        console.log("Update script/base/BaseScript.sol with:");
        console.log("- PoolManager:", address(poolManager));
        console.log("- PositionManager:", address(positionManager));
        console.log("- V4Router:", address(v4Router));
    }

    /// @notice Helper function to get deployment addresses for other scripts
    function getDeployedAddresses() external view returns (
        address _permit2,
        address _poolManager,
        address _positionManager,
        address _v4Router
    ) {
        return (
            address(permit2),
            address(poolManager),
            address(positionManager),
            address(v4Router)
        );
    }
} 
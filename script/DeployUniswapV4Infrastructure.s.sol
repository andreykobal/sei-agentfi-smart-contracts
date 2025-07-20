// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {MockERC20} from "../src/MockERC20.sol";

// Import deployment artifacts
import {Permit2Deployer} from "hookmate/artifacts/Permit2.sol";
import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";
import {V4PositionManagerDeployer} from "hookmate/artifacts/V4PositionManager.sol";
import {V4RouterDeployer} from "hookmate/artifacts/V4Router.sol";
import {DeployHelper} from "hookmate/artifacts/DeployHelper.sol";

/// @notice Script to deploy the complete Uniswap v4 infrastructure
/// @dev This script deploys all core contracts needed for a functioning Uniswap v4 ecosystem
contract DeployUniswapV4Infrastructure is Script {
    // Deployed contract addresses
    IPermit2 public permit2;
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IUniswapV4Router04 public v4Router;
    MockERC20 public token0;
    MockERC20 public token1;

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

        // 5. Deploy Test Tokens (2 x 18 decimal tokens with 1B supply each)
        deployTestTokens();

        vm.stopBroadcast();

        // Save deployment addresses to JSON
        saveDeploymentToJson();

        // Log all deployed addresses
        logDeploymentSummary();
    }

    function deployPermit2() internal {
        console.log("1. Deploying Permit2...");
        
        // Use random salt to avoid collisions
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, "permit2"));
        bytes memory initcode = abi.encodePacked(Permit2Deployer.initcode());
        address permit2Address = DeployHelper.create2(initcode, salt);
        permit2 = IPermit2(permit2Address);
        
        console.log("   Permit2 deployed at:", address(permit2));
        console.log("   Salt used:", vm.toString(salt));
        console.log("");
    }

    function deployPoolManager() internal {
        console.log("2. Deploying PoolManager...");
        
        // Use random salt to avoid collisions
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, "poolmanager"));
        bytes memory args = abi.encode(owner);
        bytes memory initcode = abi.encodePacked(V4PoolManagerDeployer.initcode(), args);
        address poolManagerAddress = DeployHelper.create2(initcode, salt);
        poolManager = IPoolManager(poolManagerAddress);
        
        console.log("   PoolManager deployed at:", address(poolManager));
        console.log("   Owner:", owner);
        console.log("   Salt used:", vm.toString(salt));
        console.log("");
    }

    function deployPositionManager() internal {
        console.log("3. Deploying PositionManager...");
        
        // Use random salt to avoid collisions
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, "positionmanager"));
        bytes memory args = abi.encode(
            address(poolManager),
            address(permit2),
            unsubscribeGasLimit,
            positionDescriptor, // address(0) for now
            wrappedNative // address(0) for native ETH
        );
        bytes memory initcode = abi.encodePacked(V4PositionManagerDeployer.initcode(), args);
        address positionManagerAddress = DeployHelper.create2(initcode, salt);
        positionManager = IPositionManager(positionManagerAddress);
        
        console.log("   PositionManager deployed at:", address(positionManager));
        console.log("   PoolManager:", address(poolManager));
        console.log("   Permit2:", address(permit2));
        console.log("   Unsubscribe Gas Limit:", unsubscribeGasLimit);
        console.log("   Position Descriptor:", positionDescriptor);
        console.log("   Wrapped Native:", wrappedNative);
        console.log("   Salt used:", vm.toString(salt));
        console.log("");
    }

    function deployV4Router() internal {
        console.log("4. Deploying V4Router...");
        
        // Use regular CREATE for V4Router since it doesn't use CREATE2 in the original
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

    function deployTestTokens() internal {
        console.log("5. Deploying Test Tokens...");
        
        // Deploy Token0 - 1 billion supply with 18 decimals
        token0 = new MockERC20(
            "Test Token A",
            "TKA", 
            18,
            1_000_000_000 * 1e18, // 1 billion tokens
            owner
        );
        
        // Deploy Token1 - 1 billion supply with 18 decimals  
        token1 = new MockERC20(
            "Test Token B",
            "TKB",
            18, 
            1_000_000_000 * 1e18, // 1 billion tokens
            owner
        );
        
        console.log("   Token0 (TKA) deployed at:", address(token0));
        console.log("   Token1 (TKB) deployed at:", address(token1));
        console.log("   Initial supply: 1,000,000,000 tokens each");
        console.log("   Owner:", owner);
        console.log("");
    }

    function saveDeploymentToJson() internal {
        // Create deployment data structure
        string memory json = "deployment";
        
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "permit2", address(permit2));
        vm.serializeAddress(json, "poolManager", address(poolManager));
        vm.serializeAddress(json, "positionManager", address(positionManager));
        vm.serializeAddress(json, "v4Router", address(v4Router));
        vm.serializeAddress(json, "token0", address(token0));
        string memory finalJson = vm.serializeAddress(json, "token1", address(token1));
        
        // Create deployments directory if it doesn't exist
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        
        // Write to file
        vm.writeFile(deploymentPath, finalJson);
        
        console.log("Deployment addresses saved to:", deploymentPath);
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
        console.log("Test Tokens:");
        console.log("- Token0 (TKA):    ", address(token0));
        console.log("- Token1 (TKB):    ", address(token1));
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Deploy any hooks you need");
        console.log("2. Initialize pools using the PoolManager");
        console.log("3. Add liquidity using the PositionManager");
        console.log("4. Execute swaps using the V4Router");
        console.log("");
        console.log("=== Note ===");
        console.log("Used random salts for CREATE2 deployments to avoid collisions");
        console.log("All addresses automatically saved to deployments/{chainId}.json");
        console.log("BaseScript.sol will read these addresses automatically");
    }

    /// @notice Helper function to get deployment addresses for other scripts
    function getDeployedAddresses() external view returns (
        address _permit2,
        address _poolManager,
        address _positionManager,
        address _v4Router,
        address _token0,
        address _token1
    ) {
        return (
            address(permit2),
            address(poolManager),
            address(positionManager),
            address(v4Router),
            address(token0),
            address(token1)
        );
    }
} 
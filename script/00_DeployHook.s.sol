// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {StdConstants} from "forge-std/StdConstants.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {Counter} from "../src/Counter.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        console2.log("=== Deploying Counter Hook ===");
        console2.log("Deployer:", deployerAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        console2.log("Hook flags:");
        console2.log("- BEFORE_SWAP_FLAG: true");
        console2.log("- AFTER_SWAP_FLAG: true");
        console2.log("- BEFORE_ADD_LIQUIDITY_FLAG: true");
        console2.log("- BEFORE_REMOVE_LIQUIDITY_FLAG: true");
        console2.log("");

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        console2.log("Mining hook address with correct flags...");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(StdConstants.CREATE2_FACTORY, flags, type(Counter).creationCode, constructorArgs);

        console2.log("Found valid hook address:", hookAddress);
        console2.log("Salt used:", vm.toString(salt));
        console2.log("");

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        Counter counter = new Counter{salt: salt}(poolManager);
        vm.stopBroadcast();

        require(address(counter) == hookAddress, "DeployHookScript: Hook Address Mismatch");

        console2.log("=== Hook Deployed Successfully ===");
        console2.log("Hook Address:", address(counter));
        console2.log("PoolManager:", address(poolManager));
        console2.log("");

        // Save hook address to deployment JSON
        saveHookToJson(address(counter));

        console2.log("=== Next Steps ===");
        console2.log("1. Run 01_CreatePoolAndAddLiquidity.s.sol to create a pool with your hook");
        console2.log("2. The hook will be called on every swap and liquidity operation!");
    }

    function saveHookToJson(address hookAddress) internal {
        // Read existing deployment file
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        
        require(vm.exists(deploymentPath), string.concat("Deployment file not found: ", deploymentPath));
        
        string memory existingJson = vm.readFile(deploymentPath);
        
        // Parse existing addresses
        uint256 chainId = vm.parseJsonUint(existingJson, ".chainId");
        address permit2 = vm.parseJsonAddress(existingJson, ".permit2");
        address poolManagerAddr = vm.parseJsonAddress(existingJson, ".poolManager");
        address positionManagerAddr = vm.parseJsonAddress(existingJson, ".positionManager");
        address v4RouterAddr = vm.parseJsonAddress(existingJson, ".v4Router");
        address token0Addr = vm.parseJsonAddress(existingJson, ".token0");
        address token1Addr = vm.parseJsonAddress(existingJson, ".token1");

        // Create new JSON with hook address added
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", chainId);
        vm.serializeAddress(json, "permit2", permit2);
        vm.serializeAddress(json, "poolManager", poolManagerAddr);
        vm.serializeAddress(json, "positionManager", positionManagerAddr);
        vm.serializeAddress(json, "v4Router", v4RouterAddr);
        vm.serializeAddress(json, "token0", token0Addr);
        vm.serializeAddress(json, "token1", token1Addr);
        string memory finalJson = vm.serializeAddress(json, "hookContract", hookAddress);
        
        // Write updated file
        vm.writeFile(deploymentPath, finalJson);
        
        console2.log("Hook address saved to:", deploymentPath);
    }
}

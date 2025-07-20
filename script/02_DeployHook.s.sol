// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {StdConstants} from "forge-std/StdConstants.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {BaseScript} from "./base/BaseScript.sol";

import {BondingCurve} from "../src/BondingCurve.sol";

/// @notice Mines the address and deploys the BondingCurve.sol Hook contract
contract DeployHookScript is BaseScript {
    function run() public {
        console2.log("=== Deploying BondingCurve Hook ===");
        console2.log("Deployer:", deployerAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // hook contracts must have specific flags encoded in the address
        // These flags must match the getHookPermissions() in BondingCurve.sol
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG 
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        console2.log("Hook flags:");
        console2.log("- BEFORE_SWAP_FLAG: true");
        console2.log("- AFTER_SWAP_FLAG: false");
        console2.log("- BEFORE_ADD_LIQUIDITY_FLAG: true");
        console2.log("- BEFORE_REMOVE_LIQUIDITY_FLAG: true");
        console2.log("- BEFORE_SWAP_RETURNS_DELTA_FLAG: true");
        console2.log("");

        // Get TokenFactory, USDT, PositionManager, and Permit2 addresses from deployment file
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        string memory json = vm.readFile(deploymentPath);
        address tokenFactory = vm.parseJsonAddress(json, ".tokenFactory");
        address usdtAddress = vm.parseJsonAddress(json, ".usdt");
        address positionManagerAddress = vm.parseJsonAddress(json, ".positionManager");
        address permit2Address = vm.parseJsonAddress(json, ".permit2");
        
        console2.log("TokenFactory:", tokenFactory);
        console2.log("USDT Address:", usdtAddress);
        console2.log("PositionManager:", positionManagerAddress);
        console2.log("Permit2:", permit2Address);
        console2.log("");

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager, tokenFactory, usdtAddress, positionManagerAddress, permit2Address);
        console2.log("Mining hook address with correct flags...");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(StdConstants.CREATE2_FACTORY, flags, type(BondingCurve).creationCode, constructorArgs);

        console2.log("Found valid hook address:", hookAddress);
        console2.log("Salt used:", vm.toString(salt));
        console2.log("");

        // Deploy the hook using CREATE2
        vm.startBroadcast();
        BondingCurve bondingCurve = new BondingCurve{salt: salt}(poolManager, tokenFactory, usdtAddress, IPositionManager(positionManagerAddress), IPermit2(permit2Address));
        vm.stopBroadcast();

        require(address(bondingCurve) == hookAddress, "DeployHookScript: Hook Address Mismatch");

        console2.log("=== Hook Deployed Successfully ===");
        console2.log("Hook Address:", address(bondingCurve));
        console2.log("PoolManager:", address(poolManager));
        console2.log("");

        // Save hook address to deployment JSON
        saveHookToJson(address(bondingCurve));

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
        
        // Create new JSON with hook address added - serialize directly to avoid stack too deep
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", vm.parseJsonUint(existingJson, ".chainId"));
        vm.serializeAddress(json, "permit2", vm.parseJsonAddress(existingJson, ".permit2"));
        vm.serializeAddress(json, "poolManager", vm.parseJsonAddress(existingJson, ".poolManager"));
        vm.serializeAddress(json, "positionManager", vm.parseJsonAddress(existingJson, ".positionManager"));
        vm.serializeAddress(json, "v4Router", vm.parseJsonAddress(existingJson, ".v4Router"));
        vm.serializeAddress(json, "tokenFactory", vm.parseJsonAddress(existingJson, ".tokenFactory"));
        vm.serializeAddress(json, "usdt", vm.parseJsonAddress(existingJson, ".usdt"));
        string memory finalJson = vm.serializeAddress(json, "hookContract", hookAddress);
        
        // Write updated file
        vm.writeFile(deploymentPath, finalJson);
        
        console2.log("Hook address saved to:", deploymentPath);
    }
}

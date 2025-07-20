// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

/// @notice Shared configuration between scripts
contract BaseScript is Script {
    IPermit2 immutable permit2;
    IPoolManager immutable poolManager;
    IPositionManager immutable positionManager;
    IUniswapV4Router04 immutable swapRouter;
    address immutable deployerAddress;

    /////////////////////////////////////
    // --- Auto-loaded from JSON ---
    /////////////////////////////////////
    IERC20 immutable usdt;
    IHooks immutable hookContract;
    IERC20 immutable memecoinToken;
    /////////////////////////////////////

    constructor() {
        // Load deployment addresses from JSON file
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat("deployments/", chainIdStr, ".json");
        
        require(vm.exists(deploymentPath), string.concat("Deployment file not found: ", deploymentPath));
        
        string memory json = vm.readFile(deploymentPath);
        
        permit2 = IPermit2(vm.parseJsonAddress(json, ".permit2"));
        poolManager = IPoolManager(vm.parseJsonAddress(json, ".poolManager"));
        positionManager = IPositionManager(payable(vm.parseJsonAddress(json, ".positionManager")));
        swapRouter = IUniswapV4Router04(payable(vm.parseJsonAddress(json, ".v4Router")));
        usdt = IERC20(vm.parseJsonAddress(json, ".usdt"));
        
        // Hook contract is optional - default to address(0) if not deployed yet
        try vm.parseJsonAddress(json, ".hookContract") returns (address hookAddr) {
            hookContract = IHooks(hookAddr);
        } catch {
            hookContract = IHooks(address(0));
        }

        // Memecoin token is optional - default to address(0) if not created yet
        try vm.parseJsonAddress(json, ".memecoinToken") returns (address memecoinAddr) {
            memecoinToken = IERC20(memecoinAddr);
        } catch {
            memecoinToken = IERC20(address(0));
        }

        deployerAddress = getDeployer();

        vm.label(address(usdt), "USDT");

        vm.label(address(deployerAddress), "Deployer");
        vm.label(address(permit2), "Permit2");
        vm.label(address(poolManager), "PoolManager");
        vm.label(address(positionManager), "PositionManager");
        vm.label(address(swapRouter), "SwapRouter");
        
        if (address(hookContract) != address(0)) {
            vm.label(address(hookContract), "HookContract (BondingCurve)");
        } else {
            vm.label(address(hookContract), "HookContract (Not Deployed)");
        }

        if (address(memecoinToken) != address(0)) {
            vm.label(address(memecoinToken), "MemecoinToken");
        } else {
            vm.label(address(memecoinToken), "MemecoinToken (Not Created)");
        }
    }



    function getDeployer() public returns (address) {
        address[] memory wallets = vm.getWallets();

        require(wallets.length > 0, "No wallets found");

        return wallets[0];
    }
}
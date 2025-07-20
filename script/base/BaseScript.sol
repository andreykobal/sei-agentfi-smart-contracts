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
    IERC20 immutable token0;
    IERC20 immutable token1;
    IHooks immutable hookContract;
    /////////////////////////////////////

    Currency immutable currency0;
    Currency immutable currency1;

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
        token0 = IERC20(vm.parseJsonAddress(json, ".token0"));
        token1 = IERC20(vm.parseJsonAddress(json, ".token1"));
        
        // Hook contract is optional - default to address(0) if not deployed yet
        try vm.parseJsonAddress(json, ".hookContract") returns (address hookAddr) {
            hookContract = IHooks(hookAddr);
        } catch {
            hookContract = IHooks(address(0));
        }

        deployerAddress = getDeployer();

        (currency0, currency1) = getCurrencies();

        vm.label(address(token0), "Token0 (USDT)");
        vm.label(address(token1), "Token1 (TEST)");

        vm.label(address(deployerAddress), "Deployer");
        vm.label(address(permit2), "Permit2");
        vm.label(address(poolManager), "PoolManager");
        vm.label(address(positionManager), "PositionManager");
        vm.label(address(swapRouter), "SwapRouter");
        
        if (address(hookContract) != address(0)) {
            vm.label(address(hookContract), "HookContract (Counter)");
        } else {
            vm.label(address(hookContract), "HookContract (Not Deployed)");
        }
    }

    function getCurrencies() public view returns (Currency, Currency) {
        require(address(token0) != address(token1));

        if (token0 < token1) {
            return (Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        } else {
            return (Currency.wrap(address(token1)), Currency.wrap(address(token0)));
        }
    }

    function getDeployer() public returns (address) {
        address[] memory wallets = vm.getWallets();

        require(wallets.length > 0, "No wallets found");

        return wallets[0];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @title TokenFactory
/// @notice Factory contract for creating ERC20 tokens
/// @dev Anyone can use this factory to create tokens with specified parameters
contract TokenFactory {
    /// @notice Array to store all created token addresses
    address[] public createdTokens;

    /// @notice Mapping to check if a token was created by this factory
    mapping(address => bool) public isFactoryToken;

    /// @notice Create a new ERC20 token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals for the token
    /// @param initialSupply The initial supply to mint to the creator
    /// @param description A description of the token (not used in factory, passed through)
    /// @param image URL to the token's image/logo (not used in factory, passed through)
    /// @param website Official website URL (not used in factory, passed through)
    /// @param twitter Twitter handle or URL (not used in factory, passed through)
    /// @param telegram Telegram group/channel URL (not used in factory, passed through)
    /// @param discord Discord server URL (not used in factory, passed through)
    /// @return tokenAddress The address of the newly created token
    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        string memory description,
        string memory image,
        string memory website,
        string memory twitter,
        string memory telegram,
        string memory discord
    ) external returns (address tokenAddress) {
        // Deploy new MockERC20 token
        MockERC20 newToken = new MockERC20(
            name,
            symbol,
            decimals,
            initialSupply,
            msg.sender // Mint initial supply to the creator
        );

        tokenAddress = address(newToken);

        // Store token info
        createdTokens.push(tokenAddress);
        isFactoryToken[tokenAddress] = true;

        // Note: TokenCreated event is now emitted by the calling contract (BondingCurve)
        return tokenAddress;
    }

    /// @notice Get the total number of tokens created by this factory
    /// @return count The number of tokens created
    function getCreatedTokensCount() external view returns (uint256 count) {
        return createdTokens.length;
    }

    /// @notice Get all created token addresses
    /// @return tokens Array of all created token addresses
    function getAllCreatedTokens() external view returns (address[] memory tokens) {
        return createdTokens;
    }

    /// @notice Get token addresses created by a specific creator
    /// @param creator The address of the creator
    /// @return tokens Array of token addresses created by the specified creator
    function getTokensByCreator(address creator) external view returns (address[] memory tokens) {
        uint256 count = 0;
        
        // First pass: count tokens created by the creator
        for (uint256 i = 0; i < createdTokens.length; i++) {
            MockERC20 token = MockERC20(createdTokens[i]);
            // Check if the creator has the initial supply (simple way to identify creator)
            if (token.balanceOf(creator) > 0) {
                count++;
            }
        }

        // Second pass: populate the array
        tokens = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < createdTokens.length; i++) {
            MockERC20 token = MockERC20(createdTokens[i]);
            if (token.balanceOf(creator) > 0) {
                tokens[index] = createdTokens[i];
                index++;
            }
        }

        return tokens;
    }
} 
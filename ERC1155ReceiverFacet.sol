// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC1155Receiver } from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import { DiamondStorage } from '../libraries/DiamondStorage.sol';

/**
 * @title ERC1155ReceiverFacet
 * @notice Enables the Diamond to receive ERC1155 tokens
 * @dev L-06: Optional whitelist — when erc1155WhitelistEnabled is true,
 *      only tokens from acceptedTokenContracts are accepted.
 */
contract ERC1155ReceiverFacet is IERC1155Receiver {
    error TokenNotWhitelisted();

    /**
     * @notice Handle the receipt of a single ERC1155 token type
     */
    function onERC1155Received(
        address /* operator */,
        address /* from */,
        uint256 /* id */,
        uint256 /* value */,
        bytes calldata /* data */
    ) external view override returns (bytes4) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.erc1155WhitelistEnabled && !s.acceptedTokenContracts[msg.sender]) {
            revert TokenNotWhitelisted();
        }
        return this.onERC1155Received.selector;
    }

    /**
     * @notice Handle the receipt of multiple ERC1155 token types
     */
    function onERC1155BatchReceived(
        address /* operator */,
        address /* from */,
        uint256[] calldata /* ids */,
        uint256[] calldata /* values */,
        bytes calldata /* data */
    ) external view override returns (bytes4) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.erc1155WhitelistEnabled && !s.acceptedTokenContracts[msg.sender]) {
            revert TokenNotWhitelisted();
        }
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @notice Query if a contract implements an interface
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

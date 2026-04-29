// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { DiamondStorage } from '../libraries/DiamondStorage.sol';
import { OrderStatus } from '../libraries/OrderStatus.sol';

/**
 * @title AuSysViewFacet
 * @notice Read-only AuSys helpers split out to keep AuSysFacet deployable
 */
contract AuSysViewFacet {
    /**
     * @notice Get the payment token address
     */
    function getPayToken() external view returns (address) {
        return DiamondStorage.appStorage().payToken;
    }

    /**
     * @notice Check if an address has a role
     */
    function hasAuSysRole(bytes32 role, address account) external view returns (bool) {
        return DiamondStorage.appStorage().ausysRoles[role][account];
    }

    /**
     * @notice Get all currently allowed drivers
     */
    function getAllowedDrivers() external view returns (address[] memory) {
        return DiamondStorage.appStorage().driverRoleMembers;
    }

    /**
     * @notice Get an order by ID
     */
    function getAuSysOrder(bytes32 id) external view returns (DiamondStorage.AuSysOrder memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysOrder memory order = s.ausysOrders[id];
        if (
            order.id != bytes32(0) &&
            order.currentStatus == OrderStatus.AUSYS_CREATED &&
            order.expiresAt != 0 &&
            block.timestamp > order.expiresAt
        ) {
            order.currentStatus = OrderStatus.AUSYS_EXPIRED;
        }
        return order;
    }

    /**
     * @notice Return the EIP-712 domain separator for this contract
     */
    function domainSeparator() external view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256('Aurellion'),
                keccak256('1'),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Get all open P2P offers
     */
    function getOpenP2POffers() external view returns (bytes32[] memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        bytes32[] storage offerIds = s.openP2POfferIds;
        uint256 length = offerIds.length;
        bytes32[] memory tempResults = new bytes32[](length);
        uint256 resultCount = 0;

        for (uint256 i = 0; i < length; i++) {
            bytes32 orderId = offerIds[i];
            DiamondStorage.AuSysOrder storage order = s.ausysOrders[orderId];
            if (order.id == bytes32(0) || order.currentStatus != OrderStatus.AUSYS_CREATED) {
                continue;
            }

            if (order.expiresAt != 0 && block.timestamp > order.expiresAt) {
                continue;
            }

            tempResults[resultCount++] = orderId;
        }

        bytes32[] memory result = new bytes32[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = tempResults[i];
        }
        return result;
    }

    /**
     * @notice Get P2P offers created by a specific user
     */
    function getUserP2POffers(address user) external view returns (bytes32[] memory) {
        return DiamondStorage.appStorage().userP2POffers[user];
    }

    /**
     * @notice Get a journey by ID
     */
    function getJourney(bytes32 id) external view returns (DiamondStorage.AuSysJourney memory) {
        return DiamondStorage.appStorage().ausysJourneys[id];
    }

    /**
     * @notice Get count of active journeys assigned to a driver
     */
    function getDriverJourneyCount(address driver) external view returns (uint256) {
        return DiamondStorage.appStorage().driverToJourneyIds[driver].length;
    }

    /**
     * @notice Get all pending token destination orders for a buyer
     */
    function getPendingTokenDestinations(address buyer) external view returns (bytes32[] memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        uint256 totalOrders = s.ausysOrderIds.length;
        bytes32[] memory tempResults = new bytes32[](totalOrders);
        uint256 resultCount = 0;

        for (uint256 i = 0; i < totalOrders; i++) {
            bytes32 oid = s.ausysOrderIds[i];
            if (s.pendingTokenDestination[oid] && s.pendingTokenBuyer[oid] == buyer) {
                tempResults[resultCount++] = oid;
            }
        }

        bytes32[] memory result = new bytes32[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = tempResults[i];
        }
        return result;
    }
}

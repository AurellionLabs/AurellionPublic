// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IOwnership } from '../interfaces/IOwnership.sol';
import { LibDiamond } from '../libraries/LibDiamond.sol';
import { DiamondStorage } from '../libraries/DiamondStorage.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

/**
 * @title OwnershipFacet
 * @notice Ownership management with two-step transfer (C-01) and timelocked renounce (L-01)
 * @dev C-01: transferOwnership sets pendingOwner; acceptOwnership completes transfer.
 *      L-01: renounceOwnership requires two calls separated by RENOUNCE_DELAY.
 */
contract OwnershipFacet is IOwnership, Initializable {
    uint256 public constant RENOUNCE_DELAY = 2 days;

    function initialize(address _owner) public initializer {
        LibDiamond.setContractOwner(_owner);
    }

    /// @notice Returns the address of the current owner.
    function owner() public view override returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @notice Step 1: Nominate a new owner. Ownership does NOT transfer until accepted.
    function transferOwnership(address _newOwner) public override {
        LibDiamond.enforceIsContractOwner();
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        s.pendingOwner = _newOwner;
        emit OwnershipTransferStarted(LibDiamond.contractOwner(), _newOwner);
    }

    /// @notice Step 2: Pending owner accepts and becomes the new owner.
    function acceptOwnership() public override {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        require(msg.sender == s.pendingOwner, 'Not pending owner');
        delete s.pendingOwner;
        LibDiamond.setContractOwner(msg.sender);
    }

    /// @notice Two-step renounce: first call schedules, second call (after delay) executes.
    function renounceOwnership() public override {
        LibDiamond.enforceIsContractOwner();
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.pendingRenounceTimestamp == 0) {
            // Step 1: Schedule
            s.pendingRenounceTimestamp = block.timestamp + RENOUNCE_DELAY;
        } else {
            // Step 2: Execute (after delay)
            require(block.timestamp >= s.pendingRenounceTimestamp, 'Renounce delay not elapsed');
            s.pendingRenounceTimestamp = 0;
            LibDiamond.setContractOwner(address(0));
        }
    }

    /// @notice Cancel a pending renounce.
    function cancelRenounceOwnership() public override {
        LibDiamond.enforceIsContractOwner();
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        s.pendingRenounceTimestamp = 0;
    }
}

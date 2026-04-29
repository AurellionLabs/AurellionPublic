// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IOwnership
 * @notice Interface for OwnershipFacet
 */
interface IOwnership {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event OwnershipTransferStarted(
        address indexed previousOwner,
        address indexed newOwner
    );

    function owner() external view returns (address owner_);

    function transferOwnership(address _newOwner) external;

    function acceptOwnership() external;

    function renounceOwnership() external;

    function cancelRenounceOwnership() external;
}


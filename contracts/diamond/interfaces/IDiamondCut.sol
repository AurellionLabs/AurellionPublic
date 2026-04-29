// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDiamondCut
 * @notice Interface for Diamond CutFacet
 * @dev Required facet for all diamonds per EIP-2535
 */
interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    event DiamondCut(
        FacetCut[] _diamondCut,
        address _init,
        bytes _calldata
    );

    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}


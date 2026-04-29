// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDiamondLoupe
 * @notice Interface for Diamond LoupeFacet
 * @dev Recommended facet for inspecting diamond state
 */
interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
        uint16[] selectorIndices;
        string[] facetURI;
    }

    function facets() external view returns (Facet[] memory facets_);

    function facetFunctionSelectors(address _facet)
        external
        view
        returns (bytes4[] memory selectors_);

    function facetAddresses()
        external
        view
        returns (address[] memory facetAddresses_);

    function facetAddress(bytes4 _functionSelector)
        external
        view
        returns (address facetAddress_);

    function selectorToFacetAndPosition(bytes4 _selector)
        external
        view
        returns (address facetAddress_, uint16 selectorPosition_);
}


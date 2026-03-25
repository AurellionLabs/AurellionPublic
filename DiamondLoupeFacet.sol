// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IDiamondLoupe } from '../interfaces/IDiamondLoupe.sol';
import { LibDiamond } from '../libraries/LibDiamond.sol';

/**
 * @title DiamondLoupeFacet
 * @notice Recommended facet for inspecting diamond state
 * @dev Implements EIP-2535 Diamond Loupe interface
 */
contract DiamondLoupeFacet is IDiamondLoupe {
    /// @notice Gets all facets and their selectors.
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new Facet[](numFacets);
        for (uint256 i = 0; i < numFacets; i++) {
            address facetAddr = ds.facetAddresses[i];
            facets_[i] = Facet({
                facetAddress: facetAddr,
                functionSelectors: ds.facetFunctionSelectors[facetAddr],
                selectorIndices: new uint16[](0),
                facetURI: new string[](0)
            });
        }
    }

    /// @notice Gets all the function selectors supported by a specific facet.
    function facetFunctionSelectors(address _facetAddress)
        external
        view
        override
        returns (bytes4[] memory)
    {
        return LibDiamond.facetFunctionSelectors(_facetAddress);
    }

    /// @notice Gets all the facet addresses used by a diamond.
    function facetAddresses() external view override returns (address[] memory) {
        return LibDiamond.facetAddresses();
    }

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    function facetAddress(bytes4 _selector) external view override returns (address) {
        return LibDiamond.facetAddress(_selector);
    }

    /// @notice Gets the facet and selector position for a given selector.
    function selectorToFacetAndPosition(bytes4 _selector)
        external
        view
        override
        returns (address facetAddr_, uint16 selectorPos_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddr_ = ds.selectorToFacetAndPosition[_selector].facetAddr;
        selectorPos_ = ds.selectorToFacetAndPosition[_selector].selectorPos;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on EIP-2535 Diamonds reference implementation
// https://github.com/mudgen/diamond-1
// https://eips.ethereum.org/EIPS/eip-2535

import { IDiamondCut } from './interfaces/IDiamondCut.sol';
import { DiamondCutFacet } from './facets/DiamondCutFacet.sol';
import { LibDiamond } from './libraries/LibDiamond.sol';

/**
 * @title Diamond
 * @notice EIP-2535 Diamond Proxy Contract
 * @dev The Diamond is a proxy contract that delegates calls to facets.
 */
contract Diamond {
    uint256 internal constant DEFAULT_DIAMOND_CUT_TIMELOCK = 0;

    /**
     * @notice Diamond constructor
     * @param _contractOwner The address that will own the Diamond
     * @param _diamondCutFacet The address of the DiamondCutFacet
     */
    constructor(address _contractOwner, address _diamondCutFacet) {
        LibDiamond.setContractOwner(_contractOwner);
        LibDiamond.diamondStorage().diamondCutTimelock = DEFAULT_DIAMOND_CUT_TIMELOCK;
        
        // Add DiamondCutFacet
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = IDiamondCut.diamondCut.selector;
        selectors[1] = DiamondCutFacet.scheduleDiamondCut.selector;
        selectors[2] = DiamondCutFacet.cancelDiamondCut.selector;
        selectors[3] = DiamondCutFacet.getDiamondCutTimelock.selector;
        selectors[4] = DiamondCutFacet.getPendingDiamondCut.selector;
        selectors[5] = DiamondCutFacet.scheduleDiamondCutTimelockChange.selector;
        selectors[6] = DiamondCutFacet.executeDiamondCutTimelockChange.selector;
        selectors[7] = DiamondCutFacet.cancelDiamondCutTimelockChange.selector;
        selectors[8] = DiamondCutFacet.getPendingDiamondCutTimelockChange.selector;
        
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: _diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });
        
        // NOTE: Constructor diamondCut intentionally bypasses the timelock.
        // This is the correct bootstrap pattern — the timelock is not yet
        // initialized and would reject legitimate deployment cuts.
        LibDiamond.diamondCut(cut, address(0), '');
    }

    /**
     * @notice Fallback function that delegates calls to facets
     */
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddr;
        require(facet != address(0), 'Diamond: Function does not exist');
        
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

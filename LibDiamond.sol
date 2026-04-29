// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on EIP-2535 Diamonds reference implementation
// https://github.com/mudgen/diamond-1

import { IDiamondCut } from '../interfaces/IDiamondCut.sol';

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256('diamond.standard.diamond.storage');

    struct FacetAndPosition {
        address facetAddr;
        uint16 selectorPos;
    }

    struct DiamondStorage {
        mapping(bytes4 => FacetAndPosition) selectorToFacetAndPosition;
        mapping(address => bytes4[]) facetFunctionSelectors;
        address[] facetAddresses;
        address contractOwner;
        uint256 diamondCutTimelock;
        bytes32 pendingDiamondCutHash;
        uint256 pendingDiamondCutEta;
        uint256 pendingDiamondCutDelay;
        uint256 pendingDiamondCutDelayEta;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address prevOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(prevOwner, _newOwner);
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(
            msg.sender == diamondStorage().contractOwner,
            'LibDiamond: Must be contract owner'
        );
    }

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        for (uint256 i; i < _diamondCut.length; i++) {
            bytes4[] memory _functionSelectors = _diamondCut[i].functionSelectors;
            address _facetAddress = _diamondCut[i].facetAddress;
            uint8 _action = uint8(_diamondCut[i].action);

            if (_action == uint8(IDiamondCut.FacetCutAction.Add)) {
                addFacet(_functionSelectors, _facetAddress);
            } else if (_action == uint8(IDiamondCut.FacetCutAction.Replace)) {
                replaceFacet(_functionSelectors, _facetAddress);
            } else if (_action == uint8(IDiamondCut.FacetCutAction.Remove)) {
                removeFacet(_functionSelectors);
            }
        }

        initializeDiamondCut(_init, _calldata);
    }

    function addFacet(bytes4[] memory _functionSelectors, address _facetAddress) internal {
        require(
            _functionSelectors.length > 0,
            'LibDiamond: No selectors provided'
        );
        require(
            _facetAddress != address(0),
            'LibDiamond: Add facet address is zero'
        );
        DiamondStorage storage ds = diamondStorage();
        uint16 nextSelectorPosition = uint16(
            ds.facetFunctionSelectors[_facetAddress].length
        );
        // H-02: Only add facet address if not already tracked
        if (ds.facetFunctionSelectors[_facetAddress].length == 0) {
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddr;

            require(
                oldFacetAddress == address(0),
                'LibDiamond: Selector already exists'
            );
            // add the selector
            ds.selectorToFacetAndPosition[selector] = FacetAndPosition({
                facetAddr: _facetAddress,
                selectorPos: nextSelectorPosition
            });
            // add the selector to the facet
            ds.facetFunctionSelectors[_facetAddress].push(selector);
            nextSelectorPosition++;
        }
    }

    function replaceFacet(bytes4[] memory _functionSelectors, address _facetAddress) internal {
        require(
            _functionSelectors.length > 0,
            'LibDiamond: No selectors provided'
        );
        require(
            _facetAddress != address(0),
            'LibDiamond: Replace facet address is zero'
        );
        DiamondStorage storage ds = diamondStorage();
        // H-01: Track new facet in facetAddresses if first time
        if (ds.facetFunctionSelectors[_facetAddress].length == 0) {
            ds.facetAddresses.push(_facetAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddr;

            require(
                oldFacetAddress != address(0),
                'LibDiamond: Selector not found'
            );
            require(
                oldFacetAddress != _facetAddress,
                'LibDiamond: Replace facet address is same as old facet address'
            );
            // remove the selector from the old facet
            removeSelectorFromFacet(ds, oldFacetAddress, selector);
            // add the selector to the new facet
            uint16 nextSelectorPosition = uint16(ds.facetFunctionSelectors[_facetAddress].length);
            ds.selectorToFacetAndPosition[selector] = FacetAndPosition({
                facetAddr: _facetAddress,
                selectorPos: nextSelectorPosition
            });
            ds.facetFunctionSelectors[_facetAddress].push(selector);
        }
    }

    function removeFacet(bytes4[] memory _functionSelectors) internal {
        require(
            _functionSelectors.length > 0,
            'LibDiamond: No selectors provided'
        );
        DiamondStorage storage ds = diamondStorage();
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address facetAddr = ds.selectorToFacetAndPosition[selector].facetAddr;

            require(
                facetAddr != address(0),
                'LibDiamond: Selector not found'
            );
            // remove the selector
            delete ds.selectorToFacetAndPosition[selector];
            // remove the selector from the facet
            removeSelectorFromFacet(ds, facetAddr, selector);
        }
    }

    function removeSelectorFromFacet(
        DiamondStorage storage ds,
        address _facetAddress,
        bytes4 _selector
    ) private {
        bytes4[] storage selectorsForFacet = ds.facetFunctionSelectors[_facetAddress];
        uint256 lastSelectorIndex = selectorsForFacet.length - 1;
        for (uint256 i; i < selectorsForFacet.length; i++) {
            if (selectorsForFacet[i] == _selector) {
                if (i != lastSelectorIndex) {
                    bytes4 movedSelector = selectorsForFacet[lastSelectorIndex];
                    selectorsForFacet[i] = movedSelector;
                    ds.selectorToFacetAndPosition[movedSelector].selectorPos = uint16(i);
                }
                selectorsForFacet.pop();
                break;
            }
        }
        // if no more selectors for the facet, remove the facet
        if (selectorsForFacet.length == 0) {
            // remove the facet from the facetAddresses array
            for (uint256 i; i < ds.facetAddresses.length; i++) {
                if (ds.facetAddresses[i] == _facetAddress) {
                    ds.facetAddresses[i] = ds.facetAddresses[ds.facetAddresses.length - 1];
                    ds.facetAddresses.pop();
                    break;
                }
            }
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(
                _calldata.length == 0,
                'LibDiamond: _calldata has data but _init is address(0)'
            );
        } else {
            require(
                _calldata.length > 0,
                'LibDiamond: _calldata is empty but _init is not address(0)'
            );
            (bool success, ) = _init.delegatecall(_calldata);
            require(
                success,
                'LibDiamond: _init function failed'
            );
        }
    }

    function facetAddress(bytes4 _selector) internal view returns (address facetAddr_) {
        facetAddr_ = diamondStorage().selectorToFacetAndPosition[_selector].facetAddr;
    }

    function facetFunctionSelectors(address _facetAddr) internal view returns (bytes4[] memory funcSelectors_) {
        funcSelectors_ = diamondStorage().facetFunctionSelectors[_facetAddr];
    }

    function facetAddresses() internal view returns (address[] memory facetAddrs_) {
        facetAddrs_ = diamondStorage().facetAddresses;
    }

    function selectorPosition(bytes4 _selector) internal view returns (uint16 selPos_) {
        selPos_ = diamondStorage().selectorToFacetAndPosition[_selector].selectorPos;
    }

    function selectors() internal view returns (bytes4[] memory selrs_) {
        DiamondStorage storage ds = diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        uint256 totalSelectors = 0;
        for (uint256 i; i < numFacets; i++) {
            totalSelectors += ds.facetFunctionSelectors[ds.facetAddresses[i]].length;
        }
        selrs_ = new bytes4[](totalSelectors);
        uint256 index = 0;
        for (uint256 i; i < numFacets; i++) {
            address facetAddr = ds.facetAddresses[i];
            bytes4[] memory funcs = ds.facetFunctionSelectors[facetAddr];
            for (uint256 j; j < funcs.length; j++) {
                selrs_[index] = funcs[j];
                index++;
            }
        }
    }
}

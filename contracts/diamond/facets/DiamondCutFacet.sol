// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IDiamondCut } from '../interfaces/IDiamondCut.sol';
import { LibDiamond } from '../libraries/LibDiamond.sol';

/**
 * @title DiamondCutFacet
 * @notice Required facet for managing facet additions, replacements, and removals
 * @dev Implements EIP-2535 Diamond Cut interface
 */
contract DiamondCutFacet is IDiamondCut {
    error PendingDiamondCutExists();
    error DiamondCutNotScheduled();
    error DiamondCutTimelockActive(uint256 readyAt);
    error DiamondCutMismatch();
    error InvalidTimelockDelay();
    error TimelockChangeNotScheduled();

    event DiamondCutScheduled(bytes32 indexed cutHash, uint256 executeAfter, uint256 delay);
    event DiamondCutCanceled(bytes32 indexed cutHash);
    event DiamondCutExecuted(bytes32 indexed cutHash);
    event DiamondCutTimelockChangeScheduled(uint256 newDelay, uint256 executeAfter);
    event DiamondCutTimelockChangeCanceled(uint256 pendingDelay);
    event DiamondCutTimelockUpdated(uint256 oldDelay, uint256 newDelay);

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         an initialization function.
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    function diamondCut(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override onlyOwner {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes32 cutHash = _diamondCutHash(_diamondCut, _init, _calldata);

        if (ds.diamondCutTimelock > 0) {
            if (ds.pendingDiamondCutEta == 0) revert DiamondCutNotScheduled();
            if (ds.pendingDiamondCutHash != cutHash) revert DiamondCutMismatch();
            if (block.timestamp < ds.pendingDiamondCutEta) {
                revert DiamondCutTimelockActive(ds.pendingDiamondCutEta);
            }
        }

        delete ds.pendingDiamondCutHash;
        delete ds.pendingDiamondCutEta;
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
        emit DiamondCutExecuted(cutHash);
    }

    function scheduleDiamondCut(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external onlyOwner returns (bytes32 cutHash, uint256 executeAfter) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.pendingDiamondCutEta != 0) revert PendingDiamondCutExists();

        cutHash = _diamondCutHash(_diamondCut, _init, _calldata);
        executeAfter = block.timestamp + ds.diamondCutTimelock;

        ds.pendingDiamondCutHash = cutHash;
        ds.pendingDiamondCutEta = executeAfter;

        emit DiamondCutScheduled(cutHash, executeAfter, ds.diamondCutTimelock);
    }

    function cancelDiamondCut() external onlyOwner {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.pendingDiamondCutEta == 0) revert DiamondCutNotScheduled();

        bytes32 cutHash = ds.pendingDiamondCutHash;
        delete ds.pendingDiamondCutHash;
        delete ds.pendingDiamondCutEta;

        emit DiamondCutCanceled(cutHash);
    }

    function getDiamondCutTimelock() external view returns (uint256) {
        return LibDiamond.diamondStorage().diamondCutTimelock;
    }

    function getPendingDiamondCut() external view returns (bytes32 cutHash, uint256 executeAfter) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (ds.pendingDiamondCutHash, ds.pendingDiamondCutEta);
    }

    function scheduleDiamondCutTimelockChange(uint256 newDelay) external onlyOwner returns (uint256 executeAfter) {
        if (newDelay < 1 hours || newDelay > 30 days) revert InvalidTimelockDelay();

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.pendingDiamondCutDelayEta != 0) revert PendingDiamondCutExists();

        executeAfter = block.timestamp + ds.diamondCutTimelock;
        ds.pendingDiamondCutDelay = newDelay;
        ds.pendingDiamondCutDelayEta = executeAfter;

        emit DiamondCutTimelockChangeScheduled(newDelay, executeAfter);
    }

    function executeDiamondCutTimelockChange() external onlyOwner {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.pendingDiamondCutDelayEta == 0) revert TimelockChangeNotScheduled();
        if (block.timestamp < ds.pendingDiamondCutDelayEta) {
            revert DiamondCutTimelockActive(ds.pendingDiamondCutDelayEta);
        }

        uint256 oldDelay = ds.diamondCutTimelock;
        uint256 newDelay = ds.pendingDiamondCutDelay;

        delete ds.pendingDiamondCutDelay;
        delete ds.pendingDiamondCutDelayEta;
        ds.diamondCutTimelock = newDelay;

        emit DiamondCutTimelockUpdated(oldDelay, newDelay);
    }

    function cancelDiamondCutTimelockChange() external onlyOwner {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.pendingDiamondCutDelayEta == 0) revert TimelockChangeNotScheduled();

        uint256 pendingDelay = ds.pendingDiamondCutDelay;
        delete ds.pendingDiamondCutDelay;
        delete ds.pendingDiamondCutDelayEta;

        emit DiamondCutTimelockChangeCanceled(pendingDelay);
    }

    function getPendingDiamondCutTimelockChange() external view returns (uint256 pendingDelay, uint256 executeAfter) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (ds.pendingDiamondCutDelay, ds.pendingDiamondCutDelayEta);
    }

    function _diamondCutHash(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_diamondCut, _init, _calldata));
    }
}

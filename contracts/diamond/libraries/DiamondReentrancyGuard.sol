// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondStorage } from './DiamondStorage.sol';

/**
 * @title DiamondReentrancyGuard
 * @notice Namespaced reentrancy guard that uses AppStorage instead of OZ slot-0
 * @dev M-05: All facets share a single reentrancy status in AppStorage,
 *      ensuring cross-facet reentrancy protection within the Diamond proxy.
 *      The reentrancyStatus field must be initialized to 1 (_NOT_ENTERED) via
 *      a diamondCut init function before first use.
 */
abstract contract DiamondReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.reentrancyStatus == _ENTERED) revert ReentrancyGuardReentrantCall();
        s.reentrancyStatus = _ENTERED;
        _;
        s.reentrancyStatus = _NOT_ENTERED;
    }
}

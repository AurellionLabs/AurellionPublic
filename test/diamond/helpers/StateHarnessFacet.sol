// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LibDiamond } from "contracts/diamond/libraries/LibDiamond.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";

contract StateHarnessFacet {
    function selectorPosition(bytes4 selector) external view returns (uint16) {
        return LibDiamond.selectorPosition(selector);
    }

    function selectors() external view returns (bytes4[] memory) {
        return LibDiamond.selectors();
    }

    function clearNodeCustodyIndex(bytes32 nodeHash, uint256 tokenId) external {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        delete s.nodeHasCustodyToken[nodeHash][tokenId];
        delete s.nodeCustodyTokenIds[nodeHash];
    }
}

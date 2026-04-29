// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondTestBase } from "./helpers/DiamondTestBase.sol";
import { StateHarnessFacet } from "./helpers/StateHarnessFacet.sol";
import { IDiamondCut } from "contracts/diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "contracts/diamond/interfaces/IDiamondLoupe.sol";
import { DiamondCutFacet } from "contracts/diamond/facets/DiamondCutFacet.sol";
import { NodesFacet } from "contracts/diamond/facets/NodesFacet.sol";

interface IDiamondStateHarness {
    function selectorPosition(bytes4 selector) external view returns (uint16);
}

contract AuditHighTest is DiamondTestBase {
    IDiamondLoupe internal loupe;

    function setUp() public override {
        super.setUp();
        loupe = IDiamondLoupe(address(diamond));
        _installStateHarness();
    }

    function test_H01_replaceFacet_addsNewFacetAddress() public {
        NodesFacet newNodesFacet = new NodesFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = NodesFacet.registerNode.selector;

        _diamondReplace(address(newNodesFacet), selectors);

        address[] memory facetAddrs = loupe.facetAddresses();
        bool found;
        for (uint256 i = 0; i < facetAddrs.length; i++) {
            if (facetAddrs[i] == address(newNodesFacet)) {
                found = true;
                break;
            }
        }
        assertTrue(found, "new facet missing from loupe");
    }

    function test_H01_replaceFacet_removesOldFacetWhenEmpty() public {
        NodesFacet newNodesFacet = new NodesFacet();
        address oldFacet = address(nodesFacet);
        bytes4[] memory oldSelectors = loupe.facetFunctionSelectors(oldFacet);

        _diamondReplace(address(newNodesFacet), oldSelectors);

        address[] memory facetAddrs = loupe.facetAddresses();
        for (uint256 i = 0; i < facetAddrs.length; i++) {
            assertTrue(facetAddrs[i] != oldFacet, "old facet should be removed");
        }
    }

    function test_LDD02_selectorPositionsStayConsistentAfterSwapAndPopRemoval() public {
        NodesFacet newNodesFacet = new NodesFacet();
        bytes4 selectorA = NodesFacet.registerNode.selector;
        bytes4 selectorB = NodesFacet.updateNode.selector;

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = selectorA;
        selectors[1] = selectorB;
        _diamondReplace(address(newNodesFacet), selectors);

        IDiamondStateHarness state = IDiamondStateHarness(address(diamond));
        assertEq(state.selectorPosition(selectorA), 0, "selector A position wrong before remove");
        assertEq(state.selectorPosition(selectorB), 1, "selector B position wrong before remove");

        bytes4[] memory removeA = new bytes4[](1);
        removeA[0] = selectorA;
        _diamondRemove(removeA);

        assertEq(state.selectorPosition(selectorB), 0, "moved selector position not updated");

        bytes4[] memory removeB = new bytes4[](1);
        removeB[0] = selectorB;
        _diamondRemove(removeB);

        assertEq(loupe.facetAddress(selectorB), address(0), "selector B still installed");
    }

    function test_LDD01_replaceFacet_sameFacetReverts() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = NodesFacet.registerNode.selector;

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(nodesFacet),
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.startPrank(owner);
        DiamondCutFacet(address(diamond)).scheduleDiamondCut(cut, address(0), "");
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        vm.expectRevert("LibDiamond: Replace facet address is same as old facet address");
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        vm.stopPrank();
    }

    function _installStateHarness() internal {
        StateHarnessFacet harness = new StateHarnessFacet();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = StateHarnessFacet.selectorPosition.selector;
        selectors[1] = StateHarnessFacet.clearNodeCustodyIndex.selector;

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(harness),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.startPrank(owner);
        DiamondCutFacet(address(diamond)).scheduleDiamondCut(cut, address(0), "");
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        vm.stopPrank();
    }

    function _diamondReplace(address facetAddress, bytes4[] memory selectors) internal {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facetAddress,
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.startPrank(owner);
        DiamondCutFacet(address(diamond)).scheduleDiamondCut(cut, address(0), "");
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        vm.stopPrank();
    }

    function _diamondRemove(bytes4[] memory selectors) internal {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(0),
            action: IDiamondCut.FacetCutAction.Remove,
            functionSelectors: selectors
        });

        vm.startPrank(owner);
        DiamondCutFacet(address(diamond)).scheduleDiamondCut(cut, address(0), "");
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        vm.stopPrank();
    }
}

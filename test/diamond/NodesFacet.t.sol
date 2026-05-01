// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondTestBase } from "./helpers/DiamondTestBase.sol";
import { StateHarnessFacet } from "./helpers/StateHarnessFacet.sol";
import { IDiamondCut } from "contracts/diamond/interfaces/IDiamondCut.sol";
import { DiamondCutFacet } from "contracts/diamond/facets/DiamondCutFacet.sol";
import { NodesFacet } from "contracts/diamond/facets/NodesFacet.sol";
import { AssetsFacet } from "contracts/diamond/facets/AssetsFacet.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IStateHarness {
    function clearNodeCustodyIndex(bytes32 nodeHash, uint256 tokenId) external;
}

contract NodesFacetTest is DiamondTestBase {
    NodesFacet internal nodes;
    AssetsFacet internal assets;

    function setUp() public override {
        super.setUp();
        nodes = NodesFacet(address(diamond));
        assets = AssetsFacet(address(diamond));

        vm.startPrank(owner);
        assets.addSupportedClass("COMMODITY");
        vm.stopPrank();

        _installStateHarness();
    }

    function test_updateNodeOwner_migratesIndexedCustody() public {
        bytes32 nodeHash = _registerTestNode(user1);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Gold Bar", "COMMODITY");

        vm.prank(user1);
        (, uint256 tokenId) = assets.nodeMintForNode(user3, assetDef, 100, "COMMODITY", "", nodeHash);

        vm.prank(user1);
        nodes.updateNodeOwner(user2, nodeHash);

        assertEq(assets.getCustodyInfo(tokenId, user1), 0, "old owner custody not migrated");
        assertEq(assets.getCustodyInfo(tokenId, user2), 100, "new owner custody missing");

        (address currentOwner,,,,,,,,,) = nodes.getNode(nodeHash);
        assertEq(currentOwner, user2, "node owner not updated");
    }

    function test_backfillAndRepair_legacyOwnershipTransferCanBeRecovered() public {
        bytes32 nodeHash = _registerTestNode(user1);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Silver Bar", "COMMODITY");

        vm.prank(user1);
        (, uint256 tokenId) = assets.nodeMintForNode(user3, assetDef, 80, "COMMODITY", "", nodeHash);

        IStateHarness(address(diamond)).clearNodeCustodyIndex(nodeHash, tokenId);

        vm.prank(user1);
        nodes.updateNodeOwner(user2, nodeHash);

        assertEq(assets.getCustodyInfo(tokenId, user1), 80, "legacy state should remain unmigrated");
        assertEq(assets.getCustodyInfo(tokenId, user2), 0, "new owner should not yet have custody");

        vm.prank(owner);
        nodes.backfillNodeCustodyTokens(nodeHash, _singleToken(tokenId));

        vm.prank(owner);
        nodes.repairNodeCustodianBalances(nodeHash, user1, _singleToken(tokenId));

        assertEq(assets.getCustodyInfo(tokenId, user1), 0, "repair did not debit previous owner");
        assertEq(assets.getCustodyInfo(tokenId, user2), 80, "repair did not credit current owner");
    }

    function test_depositAndWithdraw_reconcileNodeInventoryAndTrackedSellable() public {
        bytes32 nodeHash = _registerTestNode(user1);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Copper Bar", "COMMODITY");

        vm.prank(user1);
        (, uint256 tokenId) = assets.nodeMintForNode(user1, assetDef, 100, "COMMODITY", "", nodeHash);

        vm.prank(user1);
        IERC1155(address(diamond)).setApprovalForAll(address(diamond), true);

        vm.prank(user1);
        nodes.depositTokensToNode(nodeHash, tokenId, 100);

        (bytes32[] memory trackedNodes,) = assets.getOwnerNodeSellableBalances(user1, tokenId);
        assertEq(trackedNodes.length, 0, "deposit should prune zero sellable node");
        assertEq(nodes.getNodeTokenBalance(nodeHash, tokenId), 100, "node inventory not credited");
        assertEq(assets.balanceOf(address(diamond), tokenId), 100, "diamond should hold deposited inventory");

        vm.prank(user1);
        nodes.withdrawTokensFromNode(nodeHash, tokenId, 40);

        assertEq(nodes.getNodeTokenBalance(nodeHash, tokenId), 60, "node inventory not debited");
        assertEq(assets.balanceOf(user1, tokenId), 40, "withdrawn balance missing");
        assertEq(assets.getNodeSellableAmount(user1, tokenId, nodeHash), 40, "sellable not restored");
    }

    function test_updateNodeCapacity_setsSummedCapacity() public {
        bytes32 nodeHash = _registerTestNode(user1);
        uint256[] memory quantities = new uint256[](3);
        quantities[0] = 10;
        quantities[1] = 20;
        quantities[2] = 30;

        vm.prank(user1);
        nodes.updateNodeCapacity(nodeHash, quantities);

        (, , uint256 capacity, , , , , , , ) = nodes.getNode(nodeHash);
        assertEq(capacity, 60, "node capacity not updated to sum");
    }

    function test_updateNodeCapacity_revertsOnOverflow() public {
        bytes32 nodeHash = _registerTestNode(user1);
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = type(uint256).max;
        quantities[1] = 1;

        vm.prank(user1);
        nodes.updateNode(nodeHash, "LOGISTICS", 77);

        vm.expectRevert("Capacity overflow");
        vm.prank(user1);
        nodes.updateNodeCapacity(nodeHash, quantities);

        (, , uint256 capacity, , , , , , , ) = nodes.getNode(nodeHash);
        assertEq(capacity, 77, "capacity changed after overflow revert");
    }

    function test_verifyTokenAccounting_returnsTrueForExactMatchWithSortedUniqueHashes() public {
        (uint256 tokenId, bytes32 lowerNode, bytes32 higherNode) = _createSplitNodeInventory();
        bytes32[] memory nodeHashes = new bytes32[](2);
        nodeHashes[0] = lowerNode;
        nodeHashes[1] = higherNode;

        (uint256 diamondBalance, uint256 sumNodeBalances, bool isBalanced) =
            nodes.verifyTokenAccounting(tokenId, nodeHashes);

        assertEq(diamondBalance, 100, "diamond balance mismatch");
        assertEq(sumNodeBalances, 100, "node sum mismatch");
        assertTrue(isBalanced, "exactly matched accounting should be balanced");
    }

    function test_verifyTokenAccounting_revertsForDuplicateNodeHashes() public {
        (uint256 tokenId, bytes32 lowerNode,) = _createSplitNodeInventory();
        bytes32[] memory nodeHashes = new bytes32[](2);
        nodeHashes[0] = lowerNode;
        nodeHashes[1] = lowerNode;

        vm.expectRevert("Node hashes must be strictly ascending");
        nodes.verifyTokenAccounting(tokenId, nodeHashes);
    }

    function test_verifyTokenAccounting_revertsForUnsortedNodeHashes() public {
        (uint256 tokenId, bytes32 lowerNode, bytes32 higherNode) = _createSplitNodeInventory();
        bytes32[] memory nodeHashes = new bytes32[](2);
        nodeHashes[0] = higherNode;
        nodeHashes[1] = lowerNode;

        vm.expectRevert("Node hashes must be strictly ascending");
        nodes.verifyTokenAccounting(tokenId, nodeHashes);
    }

    function test_verifyTokenAccounting_returnsFalseForPartialNodeSet() public {
        (uint256 tokenId, bytes32 lowerNode,) = _createSplitNodeInventory();
        bytes32[] memory nodeHashes = new bytes32[](1);
        nodeHashes[0] = lowerNode;
        uint256 expectedPartialSum = nodes.getNodeTokenBalance(lowerNode, tokenId);

        (uint256 diamondBalance, uint256 sumNodeBalances, bool isBalanced) =
            nodes.verifyTokenAccounting(tokenId, nodeHashes);

        assertEq(diamondBalance, 100, "diamond balance mismatch");
        assertEq(sumNodeBalances, expectedPartialSum, "partial node sum mismatch");
        assertFalse(isBalanced, "partial node set should not be balanced");
    }

    function test_verifyTokenAccounting_emptyHashesIsTrueOnlyForZeroDiamondBalance() public {
        bytes32[] memory nodeHashes = new bytes32[](0);
        (uint256 diamondBalance, uint256 sumNodeBalances, bool isBalanced) =
            nodes.verifyTokenAccounting(123456, nodeHashes);

        assertEq(diamondBalance, 0, "diamond balance should be zero");
        assertEq(sumNodeBalances, 0, "node sum should be zero");
        assertTrue(isBalanced, "zero balances should be balanced");
    }

    function test_verifyTokenAccounting_emptyHashesIsFalseForNonZeroDiamondBalance() public {
        (uint256 tokenId,,) = _createSplitNodeInventory();
        bytes32[] memory nodeHashes = new bytes32[](0);

        (uint256 diamondBalance, uint256 sumNodeBalances, bool isBalanced) =
            nodes.verifyTokenAccounting(tokenId, nodeHashes);

        assertEq(diamondBalance, 100, "diamond balance mismatch");
        assertEq(sumNodeBalances, 0, "empty node sum should be zero");
        assertFalse(isBalanced, "non-zero diamond balance should not be balanced");
    }

    function _installStateHarness() internal {
        StateHarnessFacet harness = new StateHarnessFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = StateHarnessFacet.clearNodeCustodyIndex.selector;

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

    function _singleToken(uint256 tokenId) internal pure returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
    }

    function _createSplitNodeInventory() internal returns (uint256 tokenId, bytes32 lowerNode, bytes32 higherNode) {
        bytes32 user1Node = _registerTestNode(user1);
        bytes32 user2Node = _registerTestNode(user2);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Audit Gold", "COMMODITY");

        vm.prank(user1);
        (, tokenId) = assets.nodeMintForNode(user1, assetDef, 60, "COMMODITY", "", user1Node);
        vm.prank(user2);
        assets.nodeMintForNode(user2, assetDef, 40, "COMMODITY", "", user2Node);

        vm.prank(user1);
        IERC1155(address(diamond)).setApprovalForAll(address(diamond), true);
        vm.prank(user2);
        IERC1155(address(diamond)).setApprovalForAll(address(diamond), true);

        vm.prank(user1);
        nodes.depositTokensToNode(user1Node, tokenId, 60);
        vm.prank(user2);
        nodes.depositTokensToNode(user2Node, tokenId, 40);

        if (user1Node < user2Node) {
            return (tokenId, user1Node, user2Node);
        }

        return (tokenId, user2Node, user1Node);
    }
}

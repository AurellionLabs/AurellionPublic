// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondTestBase } from "./helpers/DiamondTestBase.sol";
import { AssetsFacet } from "contracts/diamond/facets/AssetsFacet.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";

contract AssetsFacetTest is DiamondTestBase {
    AssetsFacet internal assets;

    function setUp() public override {
        super.setUp();
        assets = AssetsFacet(address(diamond));

        vm.startPrank(owner);
        assets.addSupportedClass("COMMODITY");
        vm.stopPrank();
    }

    function test_redeem_debitsOnlyNamedCustodian() public {
        bytes32 nodeA = _registerTestNode(user1);
        bytes32 nodeB = _registerTestNode(user2);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Gold Bar", "COMMODITY");

        vm.prank(user1);
        (, uint256 tokenId) = assets.nodeMintForNode(user3, assetDef, 50, "COMMODITY", "", nodeA);

        vm.prank(user2);
        assets.nodeMintForNode(user3, assetDef, 75, "COMMODITY", "", nodeB);

        vm.prank(user3);
        assets.redeem(tokenId, 50, user1);

        assertEq(assets.balanceOf(user3, tokenId), 75, "holder balance wrong after redeem");
        assertEq(assets.getCustodyInfo(tokenId, user1), 0, "custody A not released");
        assertEq(assets.getCustodyInfo(tokenId, user2), 75, "custody B should remain");
        assertEq(assets.getNodeCustodyInfo(tokenId, nodeA), 0, "node A custody not released");
        assertEq(assets.getNodeCustodyInfo(tokenId, nodeB), 75, "node B custody should remain");
        assertEq(assets.getNodeSellableAmount(user3, tokenId, nodeA), 0, "node A sellable not consumed");
        assertEq(assets.getNodeSellableAmount(user3, tokenId, nodeB), 75, "node B sellable should remain");

        (bytes32[] memory nodes, uint256[] memory amounts) = assets.getOwnerNodeSellableBalances(user3, tokenId);
        assertEq(nodes.length, 1, "zeroed node should be removed from tracked nodes");
        assertEq(nodes[0], nodeB, "wrong tracked node remains");
        assertEq(amounts[0], 75, "remaining tracked amount wrong");
    }

    function test_safeTransfer_removesZeroedTrackedNode() public {
        bytes32 firstNode = _registerTestNode(user1);
        bytes32 secondNode = _registerTestNode(user1);
        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Gold Bar", "COMMODITY");

        vm.prank(user1);
        (, uint256 tokenId) = assets.nodeMintForNode(user1, assetDef, 40, "COMMODITY", "", firstNode);

        vm.prank(user1);
        assets.nodeMintForNode(user1, assetDef, 60, "COMMODITY", "", secondNode);

        vm.prank(user1);
        assets.safeTransferFrom(user1, user2, tokenId, 40, "");

        (bytes32[] memory ownerNodes, uint256[] memory ownerAmounts) = assets.getOwnerNodeSellableBalances(user1, tokenId);
        assertEq(ownerNodes.length, 1, "first node should be pruned after full transfer");
        assertEq(ownerNodes[0], secondNode, "second node should remain tracked");
        assertEq(ownerAmounts[0], 60, "remaining sellable wrong");
    }
}

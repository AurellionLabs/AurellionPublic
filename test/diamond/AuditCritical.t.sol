// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondTestBase } from "./helpers/DiamondTestBase.sol";
import { OwnershipFacet } from "contracts/diamond/facets/OwnershipFacet.sol";
import { AssetsFacet } from "contracts/diamond/facets/AssetsFacet.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";

contract AuditCriticalTest is DiamondTestBase {
    OwnershipFacet internal ownership;
    AssetsFacet internal assets;

    function setUp() public override {
        super.setUp();
        ownership = OwnershipFacet(address(diamond));
        assets = AssetsFacet(address(diamond));
    }

    function test_C01_twoStepOwnership() public {
        vm.prank(owner);
        ownership.transferOwnership(user1);

        assertEq(ownership.owner(), owner, "owner changed too early");

        vm.prank(user1);
        ownership.acceptOwnership();

        assertEq(ownership.owner(), user1, "pending owner did not accept");
    }

    function test_C02_mintBatch_requiresNodeHash() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 100;
        amounts[0] = 5;

        vm.prank(owner);
        vm.expectRevert(AssetsFacet.NodeHashRequired.selector);
        assets.mintBatch(user1, ids, amounts, bytes32(0), "");
    }

    function test_C02_mintBatch_requiresValidNode() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 100;
        amounts[0] = 5;

        vm.prank(owner);
        vm.expectRevert(AssetsFacet.InvalidNode.selector);
        assets.mintBatch(user1, ids, amounts, bytes32(uint256(1)), "");
    }

    function test_C02_mintBatch_withNodeCreditsSellableButNotCustody() public {
        bytes32 nodeHash = _registerTestNode(user1);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 50;
        amounts[1] = 75;

        vm.prank(owner);
        assets.mintBatch(user1, ids, amounts, nodeHash, "");

        assertEq(assets.balanceOf(user1, 100), 50, "balance not minted");
        assertEq(assets.balanceOf(user1, 101), 75, "batch balance not minted");
        assertEq(assets.getNodeSellableAmount(user1, 100, nodeHash), 50, "sellable not credited");
        assertEq(assets.getNodeSellableAmount(user1, 101, nodeHash), 75, "batch sellable not credited");
        assertEq(assets.getCustodyInfo(100, user1), 0, "mintBatch should not create custody");
        assertEq(assets.getTotalCustodyAmount(100), 0, "mintBatch should not change global custody");
    }

    function test_ASF04_addAsset_isOwnerOnly() public {
        vm.prank(owner);
        assets.addAssetClass("METAL");

        string[] memory attributes = new string[](1);
        attributes[0] = "99.99";

        vm.prank(user1);
        vm.expectRevert("LibDiamond: Must be contract owner");
        assets.addAsset("Gold", "METAL", attributes);
    }
}

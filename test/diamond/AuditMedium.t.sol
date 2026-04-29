// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondTestBase } from "./helpers/DiamondTestBase.sol";
import { AuSysFacet } from "contracts/diamond/facets/AuSysFacet.sol";
import { AuSysViewFacet } from "contracts/diamond/facets/AuSysViewFacet.sol";
import { AssetsFacet } from "contracts/diamond/facets/AssetsFacet.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";
import { OrderStatus } from "contracts/diamond/libraries/OrderStatus.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract AuditMediumTest is DiamondTestBase {
    AuSysFacet internal ausys;
    AuSysViewFacet internal ausysView;
    AssetsFacet internal assets;

    bytes32 internal sellerNode;
    uint256 internal tokenId;

    event AuSysOrderStatusUpdated(bytes32 indexed orderId, uint8 newStatus);

    function setUp() public override {
        super.setUp();
        ausys = AuSysFacet(address(diamond));
        ausysView = AuSysViewFacet(address(diamond));
        assets = AssetsFacet(address(diamond));

        vm.startPrank(owner);
        assets.addSupportedClass("METAL");
        vm.stopPrank();

        sellerNode = _registerTestNode(user2);

        DiamondStorage.AssetDefinition memory assetDef = _createAssetDefinition("Gold", "METAL");
        vm.prank(user2);
        (, tokenId) = assets.nodeMintForNode(user2, assetDef, 100, "METAL", "", sellerNode);

        vm.prank(user2);
        IERC1155(address(diamond)).setApprovalForAll(address(diamond), true);
    }

    function test_M02_pruneExpiredOffers_marksExpiredAndRemovesFromView() public {
        bytes32 orderId = _createSellerOffer(block.timestamp + 1 hours, 5);

        vm.warp(block.timestamp + 2 hours);

        vm.expectEmit(true, false, false, true);
        emit AuSysOrderStatusUpdated(orderId, OrderStatus.AUSYS_EXPIRED);
        ausys.pruneExpiredOffers(10);

        DiamondStorage.AuSysOrder memory order = ausysView.getAuSysOrder(orderId);
        assertEq(order.currentStatus, OrderStatus.AUSYS_EXPIRED, "offer not marked expired");
        assertEq(ausysView.getOpenP2POffers().length, 0, "expired offer still visible");
    }

    function test_M02_cancelExpiredOffer_restoresEscrowAndSellable() public {
        uint256 initialBalance = assets.balanceOf(user2, tokenId);
        uint256 initialSellable = assets.getNodeSellableAmount(user2, tokenId, sellerNode);
        bytes32 orderId = _createSellerOffer(block.timestamp + 1 hours, 5);

        assertEq(assets.balanceOf(user2, tokenId), initialBalance - 5, "tokens not escrowed");
        assertEq(
            assets.getNodeSellableAmount(user2, tokenId, sellerNode),
            initialSellable - 5,
            "sellable not debited"
        );

        vm.warp(block.timestamp + 2 hours);
        ausys.pruneExpiredOffers(10);

        vm.prank(user2);
        ausys.cancelP2POffer(orderId);

        DiamondStorage.AuSysOrder memory order = ausysView.getAuSysOrder(orderId);
        assertEq(order.currentStatus, OrderStatus.AUSYS_CANCELED, "expired offer not cancelable");
        assertEq(assets.balanceOf(user2, tokenId), initialBalance, "escrow not refunded");
        assertEq(
            assets.getNodeSellableAmount(user2, tokenId, sellerNode),
            initialSellable,
            "sellable not restored"
        );
        assertEq(ausysView.getOpenP2POffers().length, 0, "canceled offer still open");
        assertEq(ausysView.getUserP2POffers(user2).length, 0, "user offer index not cleaned");
    }

    function _createSellerOffer(uint256 expiresAt, uint256 quantity) internal returns (bytes32) {
        bytes32[] memory journeyIds;
        address[] memory orderNodes;
        DiamondStorage.ParcelData memory parcelData = _createParcelData(
            "40.7128",
            "-74.0060",
            "34.0522",
            "-118.2437",
            "NYC",
            "LA"
        );

        DiamondStorage.AuSysOrder memory order = DiamondStorage.AuSysOrder({
            id: bytes32(0),
            token: address(diamond),
            tokenId: tokenId,
            tokenQuantity: quantity,
            price: 50 ether,
            txFee: 0,
            buyer: address(0),
            seller: user2,
            journeyIds: journeyIds,
            nodes: orderNodes,
            locationData: parcelData,
            currentStatus: 0,
            contractualAgreement: bytes32(0),
            isSellerInitiated: true,
            targetCounterparty: address(0),
            expiresAt: expiresAt,
            snapshotTreasuryBps: 0,
            snapshotNodeBps: 0,
            sellerNode: sellerNode
        });

        vm.prank(user2);
        return ausys.createAuSysOrder(order);
    }
}

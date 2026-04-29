// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Diamond } from "contracts/diamond/Diamond.sol";
import { IDiamondCut } from "contracts/diamond/interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "contracts/diamond/interfaces/IDiamondLoupe.sol";
import { DiamondCutFacet } from "contracts/diamond/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "contracts/diamond/facets/DiamondLoupeFacet.sol";
import { OwnershipFacet } from "contracts/diamond/facets/OwnershipFacet.sol";
import { NodesFacet } from "contracts/diamond/facets/NodesFacet.sol";
import { AssetsFacet } from "contracts/diamond/facets/AssetsFacet.sol";
import { AuSysFacet } from "contracts/diamond/facets/AuSysFacet.sol";
import { AuSysAdminFacet } from "contracts/diamond/facets/AuSysAdminFacet.sol";
import { AuSysViewFacet } from "contracts/diamond/facets/AuSysViewFacet.sol";
import { ERC1155ReceiverFacet } from "contracts/diamond/facets/ERC1155ReceiverFacet.sol";
import { DiamondStorage } from "contracts/diamond/libraries/DiamondStorage.sol";
import { ERC20Mock } from "./ERC20Mock.sol";

abstract contract DiamondTestBase is Test {
    Diamond public diamond;

    DiamondCutFacet public diamondCutFacet;
    DiamondLoupeFacet public diamondLoupeFacet;
    OwnershipFacet public ownershipFacet;
    NodesFacet public nodesFacet;
    AssetsFacet public assetsFacet;
    AuSysFacet public auSysFacet;
    AuSysAdminFacet public auSysAdminFacet;
    AuSysViewFacet public auSysViewFacet;
    ERC1155ReceiverFacet public erc1155ReceiverFacet;

    ERC20Mock public payToken;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public admin;
    address public driver1;
    address public nodeOperator;

    function setUp() public virtual {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        admin = makeAddr("admin");
        driver1 = makeAddr("driver1");
        nodeOperator = makeAddr("nodeOperator");

        payToken = new ERC20Mock("Pay Token", "PAY", 18);
        payToken.mint(owner, 1_000_000 ether);
        payToken.mint(user1, 100_000 ether);
        payToken.mint(user2, 100_000 ether);
        payToken.mint(user3, 100_000 ether);
        payToken.mint(admin, 100_000 ether);
        payToken.mint(driver1, 100_000 ether);

        vm.startPrank(owner);
        _deployDiamond();
        _installFacets();
        _initializeSystem();
        vm.stopPrank();
    }

    function _deployDiamond() internal {
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        nodesFacet = new NodesFacet();
        assetsFacet = new AssetsFacet();
        auSysFacet = new AuSysFacet();
        auSysAdminFacet = new AuSysAdminFacet();
        auSysViewFacet = new AuSysViewFacet();
        erc1155ReceiverFacet = new ERC1155ReceiverFacet();

        diamond = new Diamond(owner, address(diamondCutFacet));
    }

    function _installFacets() internal {
        _addFacet(address(diamondLoupeFacet), _diamondLoupeSelectors());
        _addFacet(address(ownershipFacet), _ownershipSelectors());
        _addFacet(address(nodesFacet), _nodesSelectors());
        _addFacet(address(assetsFacet), _assetsSelectors());
        _addFacet(address(erc1155ReceiverFacet), _erc1155ReceiverSelectors());
        _addFacet(address(auSysFacet), _auSysSelectors());
        _addFacet(address(auSysAdminFacet), _auSysAdminSelectors());
        _addFacet(address(auSysViewFacet), _auSysViewSelectors());
    }

    function _initializeSystem() internal {
        _initReentrancyGuard();
        AuSysAdminFacet(address(diamond)).setPayToken(address(payToken));
        AuSysAdminFacet(address(diamond)).initAuSysFees();
        NodesFacet(address(diamond)).setAuraAssetAddress(address(diamond));
        NodesFacet(address(diamond)).setNodeRegistrar(nodeOperator, true);
        NodesFacet(address(diamond)).setNodeRegistrar(user1, true);
        NodesFacet(address(diamond)).setNodeRegistrar(user2, true);
        NodesFacet(address(diamond)).setNodeRegistrar(user3, true);
    }

    function _addFacet(address facetAddress, bytes4[] memory selectors) internal {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facetAddress,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        DiamondCutFacet(address(diamond)).scheduleDiamondCut(cut, address(0), "");
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
    }

    function _initReentrancyGuard() internal {
        ReentrancyInit initContract = new ReentrancyInit();
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](0);
        DiamondCutFacet(address(diamond)).scheduleDiamondCut(
            cut,
            address(initContract),
            abi.encodeWithSelector(ReentrancyInit.init.selector)
        );
        vm.warp(block.timestamp + DiamondCutFacet(address(diamond)).getDiamondCutTimelock());
        IDiamondCut(address(diamond)).diamondCut(
            cut,
            address(initContract),
            abi.encodeWithSelector(ReentrancyInit.init.selector)
        );
    }

    function _registerTestNode(address nodeOwner) internal returns (bytes32) {
        vm.startPrank(nodeOwner);
        bytes32 nodeHash = NodesFacet(address(diamond)).registerNode(
            "LOGISTICS",
            1000,
            bytes32(0),
            "Test Warehouse",
            "40.7128",
            "-74.0060"
        );
        vm.stopPrank();
        return nodeHash;
    }

    function _createAssetDefinition(
        string memory name,
        string memory assetClass
    ) internal pure returns (DiamondStorage.AssetDefinition memory) {
        DiamondStorage.Attribute[] memory attrs = new DiamondStorage.Attribute[](1);
        attrs[0] = DiamondStorage.Attribute({
            name: "weight",
            values: new string[](1),
            description: "Weight in kg"
        });
        attrs[0].values[0] = "100";

        return DiamondStorage.AssetDefinition({ name: name, assetClass: assetClass, attributes: attrs });
    }

    function _createParcelData(
        string memory startLat,
        string memory startLng,
        string memory endLat,
        string memory endLng,
        string memory startName,
        string memory endName
    ) internal pure returns (DiamondStorage.ParcelData memory) {
        return DiamondStorage.ParcelData({
            startLocation: DiamondStorage.Location({ lat: startLat, lng: startLng }),
            endLocation: DiamondStorage.Location({ lat: endLat, lng: endLng }),
            startName: startName,
            endName: endName
        });
    }

    function _diamondLoupeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = bytes4(keccak256("supportsInterface(bytes4)"));
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = OwnershipFacet.owner.selector;
        selectors[1] = OwnershipFacet.transferOwnership.selector;
        selectors[2] = OwnershipFacet.acceptOwnership.selector;
        selectors[3] = OwnershipFacet.renounceOwnership.selector;
        selectors[4] = OwnershipFacet.cancelRenounceOwnership.selector;
    }

    function _nodesSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](18);
        selectors[0] = NodesFacet.initialize.selector;
        selectors[1] = NodesFacet.registerNode.selector;
        selectors[2] = NodesFacet.updateNode.selector;
        selectors[3] = NodesFacet.updateNodeOwner.selector;
        selectors[4] = NodesFacet.getNode.selector;
        selectors[5] = NodesFacet.getOwnerNodes.selector;
        selectors[6] = NodesFacet.getNodeStatus.selector;
        selectors[7] = NodesFacet.setNodeRegistrar.selector;
        selectors[8] = NodesFacet.setAuraAssetAddress.selector;
        selectors[9] = NodesFacet.getNodeTokenBalance.selector;
        selectors[10] = NodesFacet.depositTokensToNode.selector;
        selectors[11] = NodesFacet.withdrawTokensFromNode.selector;
        selectors[12] = NodesFacet.transferTokensBetweenNodes.selector;
        selectors[13] = NodesFacet.creditNodeTokens.selector;
        selectors[14] = NodesFacet.debitNodeTokens.selector;
        selectors[15] = NodesFacet.verifyTokenAccounting.selector;
        selectors[16] = NodesFacet.backfillNodeCustodyTokens.selector;
        selectors[17] = NodesFacet.repairNodeCustodianBalances.selector;
    }

    function _assetsSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](30);
        selectors[0] = AssetsFacet.balanceOf.selector;
        selectors[1] = AssetsFacet.balanceOfBatch.selector;
        selectors[2] = AssetsFacet.setApprovalForAll.selector;
        selectors[3] = AssetsFacet.isApprovedForAll.selector;
        selectors[4] = AssetsFacet.safeTransferFrom.selector;
        selectors[5] = AssetsFacet.safeBatchTransferFrom.selector;
        selectors[6] = AssetsFacet.uri.selector;
        selectors[7] = AssetsFacet.setURI.selector;
        selectors[8] = AssetsFacet.totalSupply.selector;
        selectors[9] = AssetsFacet.exists.selector;
        selectors[10] = AssetsFacet.nodeMint.selector;
        selectors[11] = AssetsFacet.nodeMintForNode.selector;
        selectors[12] = AssetsFacet.lookupHash.selector;
        selectors[13] = AssetsFacet.redeem.selector;
        selectors[14] = AssetsFacet.redeemFromNode.selector;
        selectors[15] = AssetsFacet.getCustodyInfo.selector;
        selectors[16] = AssetsFacet.getNodeCustodyInfo.selector;
        selectors[17] = AssetsFacet.getNodeSellableAmount.selector;
        selectors[18] = AssetsFacet.getOwnerNodeSellableBalances.selector;
        selectors[19] = AssetsFacet.getTotalCustodyAmount.selector;
        selectors[20] = AssetsFacet.isInCustody.selector;
        selectors[21] = AssetsFacet.mintBatch.selector;
        selectors[22] = AssetsFacet.addSupportedAsset.selector;
        selectors[23] = AssetsFacet.removeSupportedAsset.selector;
        selectors[24] = AssetsFacet.addSupportedClass.selector;
        selectors[25] = AssetsFacet.removeSupportedClass.selector;
        selectors[26] = AssetsFacet.getSupportedClasses.selector;
        selectors[27] = AssetsFacet.getSupportedAssets.selector;
        selectors[28] = AssetsFacet.addAsset.selector;
        selectors[29] = AssetsFacet.addAssetClass.selector;
    }

    function _erc1155ReceiverSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ERC1155ReceiverFacet.onERC1155Received.selector;
        selectors[1] = ERC1155ReceiverFacet.onERC1155BatchReceived.selector;
    }

    function _auSysSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](12);
        selectors[0] = AuSysFacet.createAuSysOrder.selector;
        selectors[1] = AuSysFacet.acceptP2POffer.selector;
        selectors[2] = AuSysFacet.acceptP2POfferWithPickupNode.selector;
        selectors[3] = AuSysFacet.cancelP2POffer.selector;
        selectors[4] = AuSysFacet.pruneExpiredOffers.selector;
        selectors[5] = AuSysFacet.createJourney.selector;
        selectors[6] = AuSysFacet.createOrderJourney.selector;
        selectors[7] = AuSysFacet.assignDriverToJourney.selector;
        selectors[8] = AuSysFacet.packageSign.selector;
        selectors[9] = AuSysFacet.handOn.selector;
        selectors[10] = AuSysFacet.handOff.selector;
        selectors[11] = AuSysFacet.selectTokenDestination.selector;
    }

    function _auSysAdminSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](15);
        selectors[0] = AuSysAdminFacet.setPayToken.selector;
        selectors[1] = AuSysAdminFacet.initAuSysFees.selector;
        selectors[2] = AuSysAdminFacet.setTreasuryFeeBps.selector;
        selectors[3] = AuSysAdminFacet.setNodeFeeBps.selector;
        selectors[4] = AuSysAdminFacet.claimTreasuryFees.selector;
        selectors[5] = AuSysAdminFacet.getTreasuryAccrued.selector;
        selectors[6] = AuSysAdminFacet.setAuSysAdmin.selector;
        selectors[7] = AuSysAdminFacet.revokeAuSysAdmin.selector;
        selectors[8] = AuSysAdminFacet.setDriver.selector;
        selectors[9] = AuSysAdminFacet.setDispatcher.selector;
        selectors[10] = AuSysAdminFacet.setTrustedP2PSigner.selector;
        selectors[11] = AuSysAdminFacet.adminRecoverEscrow.selector;
        selectors[12] = AuSysAdminFacet.correctOrderTokenQuantity.selector;
        selectors[13] = AuSysAdminFacet.emergencyCancelJourney.selector;
        selectors[14] = AuSysAdminFacet.setERC1155WhitelistEnabled.selector;
    }

    function _auSysViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = AuSysViewFacet.getPayToken.selector;
        selectors[1] = AuSysViewFacet.hasAuSysRole.selector;
        selectors[2] = AuSysViewFacet.getAllowedDrivers.selector;
        selectors[3] = AuSysViewFacet.getAuSysOrder.selector;
        selectors[4] = AuSysViewFacet.domainSeparator.selector;
        selectors[5] = AuSysViewFacet.getOpenP2POffers.selector;
        selectors[6] = AuSysViewFacet.getUserP2POffers.selector;
        selectors[7] = AuSysViewFacet.getJourney.selector;
        selectors[8] = AuSysViewFacet.getDriverJourneyCount.selector;
        selectors[9] = AuSysViewFacet.getPendingTokenDestinations.selector;
    }
}

contract ReentrancyInit {
    function init() external {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        s.reentrancyStatus = 1;
    }
}

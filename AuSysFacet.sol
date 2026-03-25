// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { DiamondStorage } from '../libraries/DiamondStorage.sol';
import { LibDiamond } from '../libraries/LibDiamond.sol';
import { OrderStatus } from '../libraries/OrderStatus.sol';
import { IERC1155 } from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { DiamondReentrancyGuard } from '../libraries/DiamondReentrancyGuard.sol';

/**
 * @title AuSysFacet
 * @notice Logistics and delivery management system mirroring AuSys.sol
 * @dev Handles orders, journeys, driver management, and package signatures
 */
contract AuSysFacet is DiamondReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_JOURNEYS_PER_ORDER = 10;
    uint256 public constant MAX_NODES_PER_ORDER = 20;
    uint256 public constant MAX_DRIVER_JOURNEYS = 10;

    error ArrayLimitExceeded();
    error ContractPaused();
    error RecoveryTooEarly();
    error FeeBpsTooHigh();
    error NothingToClaim();

    // ============================================================================
    // EVENTS (from AuSys.sol)
    // ============================================================================

    event TreasuryFeeAccrued(bytes32 indexed orderId, uint256 amount);
    event TreasuryFeeClaimed(address indexed to, uint256 amount);
    event TreasuryFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event NodeFeeBpsUpdated(uint16 oldBps, uint16 newBps);

    event AuSysAdminSet(address indexed admin);
    event AuSysAdminRevoked(address indexed admin);
    event EmitSig(address indexed user, bytes32 indexed id);
    event AuSysOrderSettled(bytes32 indexed orderId);
    event AuSysOrderStatusUpdated(bytes32 indexed orderId, uint8 newStatus);
    event FundsEscrowed(address indexed from, uint256 amount);
    event FundsRefunded(address indexed to, uint256 amount);
    event SellerPaid(address indexed seller, uint256 amount);
    event NodeFeeDistributed(address indexed node, uint256 amount);
    event AuSysOrderCreated(
        bytes32 indexed orderId,
        address indexed buyer,
        address indexed seller,
        address token,
        uint256 tokenId,
        uint256 tokenQuantity,
        uint256 price,
        uint256 txFee,
        uint8 currentStatus,
        address[] nodes
    );

    // Verbose journey events with full context for indexing
    event JourneyCreated(
        bytes32 indexed journeyId,
        address indexed sender,
        address indexed receiver,
        address driver,
        uint256 bounty,
        uint256 ETA,
        bytes32 orderId,
        string startLat,
        string startLng,
        string endLat,
        string endLng,
        string startName,
        string endName
    );

    event DriverAssigned(
        bytes32 indexed journeyId,
        address indexed driver,
        address sender,
        address receiver,
        uint256 bounty,
        uint256 ETA,
        string startLat,
        string startLng,
        string endLat,
        string endLng,
        string startName,
        string endName
    );

    event AuSysJourneyStatusUpdated(
        bytes32 indexed journeyId,
        uint8 indexed newStatus,
        address sender,
        address receiver,
        address driver,
        uint256 bounty,
        uint256 ETA,
        uint256 journeyStart,
        uint256 journeyEnd,
        string startLat,
        string startLng,
        string endLat,
        string endLng,
        string startName,
        string endName
    );

    event JourneyCanceled(
        bytes32 indexed journeyId,
        address indexed sender,
        address receiver,
        address driver,
        uint256 refundedAmount,
        uint256 bounty,
        string startLat,
        string startLng,
        string endLat,
        string endLng,
        string startName,
        string endName
    );

    // P2P Events
    event P2POfferCreated(
        bytes32 indexed orderId,
        address indexed creator,
        bool isSellerInitiated,
        address token,
        uint256 tokenId,
        uint256 tokenQuantity,
        uint256 price,
        address targetCounterparty,
        uint256 expiresAt
    );
    event P2POfferAccepted(bytes32 indexed orderId, address indexed acceptor, bool isSellerInitiated);
    event P2POfferCanceled(bytes32 indexed orderId, address indexed creator);

    // Token destination events
    event TokenDestinationPending(bytes32 indexed orderId, address indexed buyer, uint256 tokenId, uint256 quantity);
    event TokenDestinationSelected(bytes32 indexed orderId, address destination, bytes32 nodeId, bool burned);

    // ============================================================================
    // ERRORS (from AuSys.sol)
    // ============================================================================

    error NotJourneyParticipant();
    error JourneyNotInProgress();
    error JourneyNotPending();
    error JourneyIncomplete();
    error JourneyNotFound();
    error JourneyAlreadyAssigned();
    error AlreadySettled();
    error DriverNotSigned();
    error SenderNotSigned();
    error ReceiverNotSigned();
    error DuplicateJourneyRoleAddress();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidETA();
    error QuantityExceedsRequested();
    error InvalidNode();
    error OrderNotFound();
    error InvalidOrderStatus();
    error InvalidJourneyRoute();
    error RewardAlreadyPaid();
    error DriverMaxAssignment();
    error InvalidCaller();
    error PayTokenNotSet();
    // P2P errors
    error OfferNotFound();
    error OfferNotOpen();
    error OfferExpired();
    error NotTargetCounterparty();
    error CannotAcceptOwnOffer();
    error OnlyCreatorCanCancel();
    // Token destination errors
    error NoPendingDestination();
    error NotNodeOwner();
    error NodeRequired();
    // Signature / replay-protection errors
    error InvalidSignature();
    error NonceAlreadyUsed();
    error SignatureExpired();
    error TrustedSignerNotSet();
    error CallerMustBeBuyer();
    error CallerMustBeSeller();
    error ExceedsNodeSellableAmount();

    // ============================================================================
    // CONSTANTS (RBAC roles from AuSys.sol)
    // ============================================================================

    bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
    bytes32 public constant DRIVER_ROLE = keccak256('DRIVER_ROLE');
    bytes32 public constant DISPATCHER_ROLE = keccak256('DISPATCHER_ROLE');

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    modifier whenNotPaused() {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.paused) revert ContractPaused();
        _;
    }

    modifier customerDriverCheck(bytes32 id) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[id];
        if (!(msg.sender == J.sender || msg.sender == J.driver || msg.sender == J.receiver)) {
            revert NotJourneyParticipant();
        }
        _;
    }

    modifier isInProgress(bytes32 id) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.ausysJourneys[id].currentStatus != 1) revert JourneyNotInProgress(); // 1 = InTransit
        _;
    }

    modifier isPending(bytes32 id) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.ausysJourneys[id].currentStatus != 0) revert JourneyNotPending(); // 0 = Pending
        _;
    }

    modifier isCompleted(bytes32 id) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        if (s.ausysJourneys[id].currentStatus != 2) revert JourneyIncomplete(); // 2 = Delivered
        _;
    }

    // ============================================================================
    // ORDER MANAGEMENT (from AuSys.sol)
    // ============================================================================

    /**
     * @notice Create an order (from AuSys.orderCreation)
     * @dev Supports P2P: if isSellerInitiated=true, seller escrows tokens; else buyer escrows payment
     *      For P2P offers, set buyer/seller to msg.sender and counterparty to address(0) or target
     */
    function createAuSysOrder(
        DiamondStorage.AuSysOrder memory order
    ) external nonReentrant whenNotPaused returns (bytes32) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (order.token == address(0)) {
            revert InvalidAddress();
        }
        if (order.price == 0) revert InvalidAmount();
        if (order.tokenQuantity == 0) revert InvalidAmount();
        if (s.payToken == address(0)) revert PayTokenNotSet();

        // P2P mode: one side can be address(0) initially (will be filled on accept)
        bool isP2POffer = order.isSellerInitiated 
            ? (order.buyer == address(0) || order.buyer == order.targetCounterparty)
            : (order.seller == address(0)|| order.seller == order.targetCounterparty);

        // For non-P2P (direct orders), both parties must be set and different
        if (!isP2POffer) {
            if (order.buyer == address(0) || order.seller == address(0)) {
                revert InvalidAddress();
            }
            if (order.buyer == order.seller) revert InvalidAddress();
        }

        bytes32 id = _getHashedOrderId(s, msg.sender);

        // Treasury fee always applies. Node fee only if intermediate nodes are present.
        uint256 treasuryFee = (order.price * s.treasuryFeeBps) / 10000;
        uint256 nodeFee = order.nodes.length > 0 ? (order.price * s.nodeFeeBps) / 10000 : 0;
        uint256 txFee = treasuryFee + nodeFee;

        // Store order
        DiamondStorage.AuSysOrder storage newOrder = s.ausysOrders[id];
        newOrder.id = id;
        newOrder.token = order.token;
        newOrder.tokenId = order.tokenId;
        newOrder.tokenQuantity = order.tokenQuantity;
        newOrder.price = order.price;
        newOrder.txFee = txFee;
        newOrder.buyer = order.buyer;
        newOrder.seller = order.seller;
        newOrder.locationData = order.locationData;
        newOrder.currentStatus = OrderStatus.AUSYS_CREATED;
        newOrder.contractualAgreement = order.contractualAgreement;
        // P2P fields
        newOrder.isSellerInitiated = order.isSellerInitiated;
        newOrder.targetCounterparty = order.targetCounterparty;
        newOrder.expiresAt = order.expiresAt;
        // H-04: Snapshot fee rates at creation time
        newOrder.snapshotTreasuryBps = s.treasuryFeeBps;
        newOrder.snapshotNodeBps = s.nodeFeeBps;
        // Source node — must be set by caller so debit targets the correct node
        newOrder.sellerNode = order.sellerNode;

        if (order.nodes.length > MAX_NODES_PER_ORDER) revert ArrayLimitExceeded();
        uint256 nodeCount = order.nodes.length;
        for (uint256 i = 0; i < nodeCount; i++) {
            newOrder.nodes.push(order.nodes[i]);
        }


        s.ausysOrderIds.push(id);

        // Escrow based on who initiated
        if (order.isSellerInitiated) {
            // Seller-initiated P2P: escrow tokens from seller
            if (order.seller == address(0)) revert InvalidAddress();
            if (order.seller != msg.sender) revert CallerMustBeSeller();
            if (order.token == address(this)) {
                _debitOwnerSellableForEscrow(
                    s,
                    id,
                    msg.sender,
                    order.tokenId,
                    order.tokenQuantity,
                    order.sellerNode  // pin to the seller's chosen node
                );
            }
            IERC1155(order.token).safeTransferFrom(
                msg.sender,
                address(this),
                order.tokenId,
                order.tokenQuantity,
                ''
            );
            s.ausysOrderTokenEscrowed[id] = true;
            // Track as open P2P offer
            if (isP2POffer) {
                s.openP2POfferIds.push(id);
                s.userP2POffers[order.seller].push(id);
            }
        } else {
            // Buyer-initiated: escrow payment from buyer (original behavior)
            if (order.buyer == address(0)) revert InvalidAddress();
            if (order.buyer != msg.sender) revert CallerMustBeBuyer();
            IERC20(s.payToken).safeTransferFrom(msg.sender, address(this), order.price + txFee);
            emit FundsEscrowed(order.buyer, order.price + txFee);
            // Track as open P2P offer
            if (isP2POffer) {
                s.openP2POfferIds.push(id);
                s.userP2POffers[order.buyer].push(id);
            }
        }

        emit AuSysOrderCreated(
            id,
            order.buyer,
            order.seller,
            order.token,
            order.tokenId,
            order.tokenQuantity,
            order.price,
            txFee,
            0,
            order.nodes
        );

        // Emit P2P-specific event if this is a P2P offer
        if (isP2POffer) {
            address creator = order.isSellerInitiated ? order.seller : order.buyer;
            emit P2POfferCreated(
                id,
                creator,
                order.isSellerInitiated,
                order.token,
                order.tokenId,
                order.tokenQuantity,
                order.price,
                order.targetCounterparty,
                order.expiresAt
            );
        }

        return id;
    }

    // ============================================================================
    // P2P OFFER MANAGEMENT
    // ============================================================================

    /**
     * @notice Accept a P2P offer
     * @dev Counterparty escrows their side and order moves to Processing.
     *      msg.sender is the authorization — no additional signature needed.
     * @param orderId The order/offer to accept
     */
    function acceptP2POffer(
        bytes32 orderId
    ) external nonReentrant whenNotPaused {
        _acceptP2POffer(orderId, bytes32(0), false);
    }

    /**
     * @notice Accept a buyer-initiated P2P offer with an explicit fulfillment node
     * @dev Persists pickup metadata (start location/name) from the selected node.
     * @param orderId The order/offer to accept
     * @param pickupNodeRef Selected node hash owned by the accepting seller
     */
    function acceptP2POfferWithPickupNode(
        bytes32 orderId,
        bytes32 pickupNodeRef
    ) external nonReentrant whenNotPaused {
        if (pickupNodeRef == bytes32(0)) revert NodeRequired();
        _acceptP2POffer(orderId, pickupNodeRef, true);
    }

    function _acceptP2POffer(
        bytes32 orderId,
        bytes32 pickupNodeRef,
        bool enforcePickupNode
    ) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysOrder storage order = s.ausysOrders[orderId];

        // ── CHECKS ───────────────────────────────────────────────────────────
        // Validate offer exists
        if (order.id == bytes32(0)) revert OfferNotFound();

        // Validate offer is still open
        if (order.currentStatus != OrderStatus.AUSYS_CREATED) revert OfferNotOpen();

        if (order.expiresAt != 0 && block.timestamp > order.expiresAt) {
            order.currentStatus = OrderStatus.AUSYS_EXPIRED;
            revert OfferExpired();
        }

        // Validate caller is allowed counterparty
        if (order.targetCounterparty != address(0) && msg.sender != order.targetCounterparty) {
            revert NotTargetCounterparty();
        }

        // Cannot accept own offer
        address creator = order.isSellerInitiated ? order.seller : order.buyer;
        if (msg.sender == creator) revert CannotAcceptOwnOffer();

        // ── EFFECTS ──────────────────────────────────────────────────────────
        // Update status to Processing
        order.currentStatus = OrderStatus.AUSYS_PROCESSING;

        // Remove from open offers list
        _removeFromOpenOffers(s, orderId);

        // L-08: Remove from creator's userP2POffers
        address offerCreator = order.isSellerInitiated ? order.seller : order.buyer;
        _removeFromUserOffers(s, offerCreator, orderId);

        if (order.isSellerInitiated) {
            // Seller created offer — buyer (msg.sender) accepts
            order.buyer = msg.sender;
        } else {
            // Buyer created offer — seller (msg.sender) accepts
            if (!enforcePickupNode) revert NodeRequired();
            _persistSelectedPickupNode(s, order, pickupNodeRef);
            order.seller = msg.sender;
            order.sellerNode = pickupNodeRef;  // record which node the seller fulfils from
        }

        // ── INTERACTIONS ─────────────────────────────────────────────────────
        if (order.isSellerInitiated) {
            uint256 totalPayment = order.price + order.txFee;
            IERC20(s.payToken).safeTransferFrom(msg.sender, address(this), totalPayment);
            emit FundsEscrowed(msg.sender, totalPayment);
        } else {
            IERC1155(order.token).safeTransferFrom(
                msg.sender,
                address(this),
                order.tokenId,
                order.tokenQuantity,
                ''
            );
            if (order.token == address(this)) {
                _debitOwnerSellableForEscrow(
                    s,
                    orderId,
                    msg.sender,
                    order.tokenId,
                    order.tokenQuantity,
                    pickupNodeRef  // pin debit to the seller's chosen node
                );
            }
        }

        emit P2POfferAccepted(orderId, msg.sender, order.isSellerInitiated);
        emit AuSysOrderStatusUpdated(orderId, 1);
    }

    function _persistSelectedPickupNode(
        DiamondStorage.AppStorage storage s,
        DiamondStorage.AuSysOrder storage order,
        bytes32 pickupNodeRef
    ) internal {
        DiamondStorage.Node storage pickupNode = s.nodes[pickupNodeRef];
        if (pickupNode.owner != msg.sender) revert NotNodeOwner();
        if (!pickupNode.active || !pickupNode.validNode) revert InvalidNode();
        if (
            bytes(pickupNode.addressName).length == 0 ||
            bytes(pickupNode.lat).length == 0 ||
            bytes(pickupNode.lng).length == 0
        ) revert NodeRequired();

        order.locationData.startLocation.lat = pickupNode.lat;
        order.locationData.startLocation.lng = pickupNode.lng;
        order.locationData.startName = pickupNode.addressName;
    }

    /**
     * @notice Cancel a P2P offer (only creator, only if not yet accepted)
     * @param orderId The order/offer to cancel
     */
    function cancelP2POffer(bytes32 orderId) external nonReentrant whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysOrder storage order = s.ausysOrders[orderId];

        // Validate offer exists
        if (order.id == bytes32(0)) revert OfferNotFound();
        
        // Validate offer is still open (status 0)
        if (order.currentStatus != OrderStatus.AUSYS_CREATED) revert OfferNotOpen();
        
        // Only creator can cancel
        address creator = order.isSellerInitiated ? order.seller : order.buyer;
        if (msg.sender != creator) revert OnlyCreatorCanCancel();

        // Refund escrowed assets
        if (order.isSellerInitiated) {
            // Refund tokens to seller
            IERC1155(order.token).safeTransferFrom(
                address(this),
                order.seller,
                order.tokenId,
                order.tokenQuantity,
                ''
            );
            if (order.token == address(this)) {
                _restoreEscrowedOwnerSellable(
                    s,
                    orderId,
                    order.seller,
                    order.tokenId
                );
            }
        } else {
            // Refund payment to buyer
            uint256 totalRefund = order.price + order.txFee;
            IERC20(s.payToken).safeTransfer(order.buyer, totalRefund);
            emit FundsRefunded(order.buyer, totalRefund);
        }

        // Update status to Canceled
        order.currentStatus = OrderStatus.AUSYS_CANCELED;

        // M-01: Clear escrow flag
        delete s.ausysOrderTokenEscrowed[orderId];

        // Remove from open offers list
        _removeFromOpenOffers(s, orderId);

        // L-08: Remove from creator's userP2POffers
        _removeFromUserOffers(s, creator, orderId);

        emit P2POfferCanceled(orderId, creator);
        emit AuSysOrderStatusUpdated(orderId, 3);
    }

    /**
     * @notice M-02: Permissionless cleanup of expired offers from the open list
     * @param maxIterations Maximum number of entries to scan (gas limit safety)
     */
    function pruneExpiredOffers(uint256 maxIterations) external {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        uint256 length = s.openP2POfferIds.length;
        uint256 i = 0;
        uint256 iterations = 0;
        while (i < length && iterations < maxIterations) {
            bytes32 id = s.openP2POfferIds[i];
            DiamondStorage.AuSysOrder storage order = s.ausysOrders[id];
            if (order.expiresAt != 0 && block.timestamp > order.expiresAt) {
                order.currentStatus = OrderStatus.AUSYS_EXPIRED;
                s.openP2POfferIds[i] = s.openP2POfferIds[length - 1];
                s.openP2POfferIds.pop();
                length--;
                // don't increment i — swapped element needs checking
            } else {
                i++;
            }
            iterations++;
        }
    }

    // ============================================================================
    // TRUSTED SIGNER & EIP-712
    // ============================================================================

    /**
     * @notice Set the trusted off-chain signer address (reserved for future EIP-712 flow).
     * @dev IMPORTANT: This signer is stored but NOT yet enforced in acceptP2POffer.
     *      acceptP2POffer currently relies solely on msg.sender authorization.
     *      Full EIP-712 signature verification is planned for a future upgrade.
     *      Auditors: this field is intentionally inert in v1 — see roadmap docs.
     * @param signer The address to designate as trusted signer for future enforcement
     */
    /**
     * @dev Remove an order from the open P2P offers list
     * @notice M-06: Read directly from storage — avoids copying full array to memory
     */
    function _removeFromOpenOffers(DiamondStorage.AppStorage storage s, bytes32 orderId) internal {
        uint256 length = s.openP2POfferIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (s.openP2POfferIds[i] == orderId) {
                s.openP2POfferIds[i] = s.openP2POfferIds[length - 1];
                s.openP2POfferIds.pop();
                return;
            }
        }
    }

    /**
     * @dev L-08: Remove an order from a user's P2P offers list (swap-and-pop)
     */
    function _removeFromUserOffers(DiamondStorage.AppStorage storage s, address user, bytes32 orderId) internal {
        bytes32[] storage offers = s.userP2POffers[user];
        uint256 length = offers.length;
        for (uint256 i = 0; i < length; i++) {
            if (offers[i] == orderId) {
                offers[i] = offers[length - 1];
                offers.pop();
                return;
            }
        }
    }

    /**
     * @dev Remove a journey from driver's active list (swap-and-pop)
     */
    function _removeDriverJourney(DiamondStorage.AppStorage storage s, address driver, bytes32 journeyId) internal {
        bytes32[] storage journeys = s.driverToJourneyIds[driver];
        uint256 length = journeys.length;
        
        for (uint256 i = 0; i < length; i++) {
            if (journeys[i] == journeyId) {
                journeys[i] = journeys[length - 1];
                journeys.pop();
                break;
            }
        }
    }

    // ============================================================================
    // JOURNEY MANAGEMENT (from AuSys.sol)
    // ============================================================================

    /**
     * @notice Create a standalone journey (from AuSys.journeyCreation)
     */
    function createJourney(
        address sender,
        address receiver,
        DiamondStorage.ParcelData memory _data,
        uint256 bounty,
        uint256 ETA
    ) external nonReentrant whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (msg.sender != receiver) revert CallerMustBeBuyer();
        if (sender == address(0) || receiver == address(0)) revert InvalidAddress();
        if (sender == receiver) revert DuplicateJourneyRoleAddress();
        if (bounty == 0) revert InvalidAmount();
        if (ETA <= block.timestamp) revert InvalidETA();
        if (s.payToken == address(0)) revert PayTokenNotSet();

        bytes32 journeyId = _getHashedJourneyId(s);

        DiamondStorage.AuSysJourney storage journey = s.ausysJourneys[journeyId];
        journey.parcelData = _data;
        journey.journeyId = journeyId;
        journey.currentStatus = OrderStatus.JOURNEY_PENDING;
        journey.sender = sender;
        journey.receiver = receiver;
        journey.driver = address(0);
        journey.journeyStart = 0;
        journey.journeyEnd = 0;
        journey.bounty = bounty;
        journey.ETA = ETA;

        // Escrow bounty from receiver
        IERC20(s.payToken).safeTransferFrom(msg.sender, address(this), bounty);
        emit FundsEscrowed(receiver, bounty);
        emit JourneyCreated(
            journeyId,
            sender,
            receiver,
            address(0), // driver not assigned yet
            bounty,
            ETA,
            bytes32(0), // no linked order for standalone journey
            _data.startLocation.lat,
            _data.startLocation.lng,
            _data.endLocation.lat,
            _data.endLocation.lng,
            _data.startName,
            _data.endName
        );
    }

    /**
     * @notice Create a journey linked to an order (from AuSys.orderJourneyCreation)
     */
    function createOrderJourney(
        bytes32 orderId,
        address sender,
        address receiver,
        DiamondStorage.ParcelData memory _data,
        uint256 bounty,
        uint256 ETA,
        uint256 tokenQuantity,
        uint256 assetId
    ) external nonReentrant whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysOrder storage O = s.ausysOrders[orderId];

        if (O.id == bytes32(0)) revert OrderNotFound();

        // Validate receiver is valid node or buyer
        bool isValidNode = _isValidNode(s, receiver);
        bool isBuyer = receiver == O.buyer;
        if (!isValidNode && !isBuyer) revert InvalidNode();

        if (msg.sender != O.buyer) revert CallerMustBeBuyer();
        if (O.currentStatus != OrderStatus.AUSYS_CREATED && O.currentStatus != OrderStatus.AUSYS_PROCESSING) {
            revert InvalidOrderStatus();
        }
        if (O.expiresAt != 0 && block.timestamp > O.expiresAt) revert OfferExpired();
        if (sender != O.seller) revert InvalidJourneyRoute();
        if (sender == address(0) || receiver == address(0)) revert InvalidAddress();
        if (sender == receiver) revert DuplicateJourneyRoleAddress();
        if (ETA <= block.timestamp) revert InvalidETA();
        if (bounty == 0) revert InvalidAmount();
        if (tokenQuantity == 0) revert InvalidAmount();
        if (tokenQuantity != O.tokenQuantity) revert QuantityExceedsRequested();
        if (assetId != O.tokenId) revert InvalidAmount();
        if (s.payToken == address(0)) revert PayTokenNotSet();

        bytes32 journeyId = _getHashedJourneyId(s);

        DiamondStorage.AuSysJourney storage journey = s.ausysJourneys[journeyId];
        journey.parcelData = _data;
        journey.journeyId = journeyId;
        journey.currentStatus = OrderStatus.JOURNEY_PENDING;
        journey.sender = sender;
        journey.receiver = receiver;
        journey.driver = address(0);
        journey.journeyStart = 0;
        journey.journeyEnd = 0;
        journey.bounty = bounty;
        journey.ETA = ETA;

        // Escrow bounty from buyer
        IERC20(s.payToken).safeTransferFrom(msg.sender, address(this), bounty);
        emit FundsEscrowed(O.buyer, bounty);

        if (O.journeyIds.length >= MAX_JOURNEYS_PER_ORDER) revert ArrayLimitExceeded();
        O.journeyIds.push(journeyId);
        s.journeyToAusysOrderId[journeyId] = orderId;

        emit JourneyCreated(
            journeyId,
            sender,
            receiver,
            address(0), // driver not assigned yet
            bounty,
            ETA,
            orderId,
            _data.startLocation.lat,
            _data.startLocation.lng,
            _data.endLocation.lat,
            _data.endLocation.lng,
            _data.startName,
            _data.endName
        );
    }

    // ============================================================================
    // DRIVER ASSIGNMENT (from AuSys.sol)
    // ============================================================================

    /**
     * @notice Assign a driver to a journey (from AuSys.assignDriverToJourneyId)
     */
    function assignDriverToJourney(address driver, bytes32 journeyId) external whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[journeyId];

        if (J.journeyId == bytes32(0)) revert JourneyNotFound();

        // Require driver to be registered
        if (!s.ausysRoles[DRIVER_ROLE][driver]) revert InvalidCaller();
        if (driver == J.sender || driver == J.receiver || J.sender == J.receiver) {
            revert DuplicateJourneyRoleAddress();
        }

        // Only driver, dispatcher, or journey sender can assign
        bool callerAuthorized = (
            msg.sender == driver ||
            s.ausysRoles[DISPATCHER_ROLE][msg.sender] ||
            msg.sender == J.sender
        );
        if (!callerAuthorized) revert InvalidCaller();
        if (J.currentStatus != OrderStatus.JOURNEY_PENDING) revert JourneyNotPending();
        if (J.driver != address(0)) revert JourneyAlreadyAssigned();

        if (s.driverToJourneyIds[driver].length >= MAX_DRIVER_JOURNEYS) revert DriverMaxAssignment();

        s.driverToJourneyIds[driver].push(journeyId);
        J.driver = driver;

        emit DriverAssigned(
            journeyId,
            driver,
            J.sender,
            J.receiver,
            J.bounty,
            J.ETA,
            J.parcelData.startLocation.lat,
            J.parcelData.startLocation.lng,
            J.parcelData.endLocation.lat,
            J.parcelData.endLocation.lng,
            J.parcelData.startName,
            J.parcelData.endName
        );
    }

    // ============================================================================
    // SIGNATURE SYSTEM (from AuSys.sol)
    // ============================================================================

    /**
     * @notice Sign for package pickup/delivery (from AuSys.packageSign)
     */
    function packageSign(bytes32 id) external customerDriverCheck(id) whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[id];

        if (msg.sender == J.sender) {
            s.customerHandOff[J.sender][id] = true;
            emit EmitSig(J.sender, id);
        } else if (msg.sender == J.receiver) {
            s.customerHandOff[J.receiver][id] = true;
            emit EmitSig(J.receiver, id);
        } else if (msg.sender == J.driver) {
            // Driver signs for current phase based on journey status
            if (J.currentStatus == OrderStatus.JOURNEY_PENDING) {
                s.driverPickupSigned[J.driver][id] = true;
            } else if (J.currentStatus == OrderStatus.JOURNEY_IN_TRANSIT) {
                s.driverDeliverySigned[J.driver][id] = true;
            } else {
                // Journey is in a terminal state (Delivered/Canceled) — signing is meaningless
                revert JourneyNotInProgress();
            }
            emit EmitSig(J.driver, id);
        }
    }

    /**
     * @notice Hand on - pickup confirmation (from AuSys.handOn)
     * @dev Requires driver and sender signatures. Transitions to InTransit.
     */
    function handOn(bytes32 id) external customerDriverCheck(id) isPending(id) nonReentrant whenNotPaused returns (bool) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[id];

        if (!s.driverPickupSigned[J.driver][id]) revert DriverNotSigned();
        if (!s.customerHandOff[J.sender][id]) revert SenderNotSigned();

        J.journeyStart = block.timestamp;
        s.customerHandOff[J.sender][id] = false;
        J.currentStatus = OrderStatus.JOURNEY_IN_TRANSIT;

        emit AuSysJourneyStatusUpdated(
            id,
            1, // InTransit
            J.sender,
            J.receiver,
            J.driver,
            J.bounty,
            J.ETA,
            J.journeyStart,
            J.journeyEnd,
            J.parcelData.startLocation.lat,
            J.parcelData.startLocation.lng,
            J.parcelData.endLocation.lat,
            J.parcelData.endLocation.lng,
            J.parcelData.startName,
            J.parcelData.endName
        );

        // Update linked order status if exists
        bytes32 orderId = s.journeyToAusysOrderId[id];
        if (orderId != bytes32(0)) {
            DiamondStorage.AuSysOrder storage O = s.ausysOrders[orderId];
        if (O.currentStatus == OrderStatus.AUSYS_CREATED) {
            O.currentStatus = OrderStatus.AUSYS_PROCESSING;
            emit AuSysOrderStatusUpdated(orderId, OrderStatus.AUSYS_PROCESSING);
        }

            // Transfer tokens from seller to escrow if this is first journey
            // Skip if seller-initiated P2P (tokens already escrowed at offer creation)
            if (J.sender == O.seller && !O.isSellerInitiated && !s.ausysOrderTokenEscrowed[orderId]) {
                if (O.token == address(this)) {
                    _debitOwnerSellableForEscrow(
                        s,
                        orderId,
                        O.seller,
                        O.tokenId,
                        O.tokenQuantity,
                        O.sellerNode  // pin to seller's recorded node
                    );
                }
                IERC1155(O.token).safeTransferFrom(
                    O.seller,
                    address(this),
                    O.tokenId,
                    O.tokenQuantity,
                    ''
                );
                s.ausysOrderTokenEscrowed[orderId] = true;
            }
        }

        return true;
    }

    /**
     * @notice Hand off - delivery confirmation (from AuSys.handOff)
     * @dev Requires driver delivery signature and receiver signature. 
     *      Pays driver bounty and settles order if final delivery.
     */
    function handOff(bytes32 id) external isInProgress(id) customerDriverCheck(id) nonReentrant whenNotPaused returns (bool) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[id];
        bytes32 orderId = s.journeyToAusysOrderId[id];

        if (orderId != bytes32(0)) {
            DiamondStorage.AuSysOrder storage O = s.ausysOrders[orderId];
        if (O.currentStatus == OrderStatus.AUSYS_SETTLED) revert AlreadySettled();
        }

        if (!s.driverDeliverySigned[J.driver][id]) revert DriverNotSigned();
        if (!s.customerHandOff[J.receiver][id]) revert ReceiverNotSigned();

        J.currentStatus = OrderStatus.JOURNEY_DELIVERED;
        J.journeyEnd = block.timestamp;

        // Remove journey from driver's active list (swap-and-pop)
        _removeDriverJourney(s, J.driver, id);

        emit AuSysJourneyStatusUpdated(
            id,
            OrderStatus.JOURNEY_DELIVERED,
            J.sender,
            J.receiver,
            J.driver,
            J.bounty,
            J.ETA,
            J.journeyStart,
            J.journeyEnd,
            J.parcelData.startLocation.lat,
            J.parcelData.startLocation.lng,
            J.parcelData.endLocation.lat,
            J.parcelData.endLocation.lng,
            J.parcelData.startName,
            J.parcelData.endName
        );

        // Pay driver bounty.
        // NOTE: State (JOURNEY_DELIVERED, journeyEnd, driver removal) is fully updated above
        // before any external calls below. Reentrancy is additionally guarded by nonReentrant.
        _generateReward(s, id);

        // Settle order if this is final delivery to buyer
        if (orderId != bytes32(0)) {
            DiamondStorage.AuSysOrder storage O = s.ausysOrders[orderId];
            if (J.receiver == O.buyer) {
                _settleOrder(s, orderId, O);
            }
        }

        return true;
    }

    // ============================================================================
    // INTERNAL HELPERS
    // ============================================================================

    /// @dev IDs are unique (counter + prevrandao + sender + timestamp) but NOT secret.
    /// Validators have weak influence over prevrandao post-merge.
    /// Do not use these IDs where unpredictability is required.
    function _getHashedJourneyId(DiamondStorage.AppStorage storage s) internal returns (bytes32) {
        return keccak256(abi.encodePacked(++s.ausysJourneyIdCounter, block.prevrandao, msg.sender, block.timestamp));
    }

    /// @dev IDs are unique (counter + prevrandao + creator + timestamp) but NOT secret.
    /// Validators have weak influence over prevrandao post-merge.
    /// Do not use these IDs where unpredictability is required.
    function _getHashedOrderId(DiamondStorage.AppStorage storage s, address creator) internal returns (bytes32) {
        return keccak256(abi.encodePacked(++s.ausysOrderIdCounter, block.prevrandao, creator, block.timestamp));
    }

    function _isValidNode(DiamondStorage.AppStorage storage s, address nodeOwner) internal view returns (bool) {
        bytes32[] storage ownerNodes = s.ownerNodes[nodeOwner];
        uint256 nodeCount = ownerNodes.length;
        for (uint256 i = 0; i < nodeCount; i++) {
            // Cache node to avoid repeated SLOAD (saves ~3000 gas per iteration)
            DiamondStorage.Node storage nodeData = s.nodes[ownerNodes[i]];
            if (nodeData.active && nodeData.validNode) {
                return true;
            }
        }
        return false;
    }

    function _generateReward(DiamondStorage.AppStorage storage s, bytes32 id) internal {
        if (s.journeyRewardPaid[id]) revert RewardAlreadyPaid();
        s.journeyRewardPaid[id] = true;

        DiamondStorage.AuSysJourney storage J = s.ausysJourneys[id];
        IERC20(s.payToken).safeTransfer(J.driver, J.bounty);
    }

    function _settleOrder(
        DiamondStorage.AppStorage storage s,
        bytes32 orderId,
        DiamondStorage.AuSysOrder storage O
    ) internal {
        O.currentStatus = OrderStatus.AUSYS_SETTLED;
        emit AuSysOrderStatusUpdated(orderId, OrderStatus.AUSYS_SETTLED);

        // Hold tokens in escrow — buyer chooses destination via selectTokenDestination
        // NOTE: seller's node custody was already released at escrow creation
        // (_debitOwnerSellableForEscrow) — no custody change needed here.
        s.pendingTokenDestination[orderId] = true;
        s.pendingTokenBuyer[orderId] = O.buyer;
        s.ausysOrderSettledAt[orderId] = block.timestamp;
        emit TokenDestinationPending(orderId, O.buyer, O.tokenId, O.tokenQuantity);

        // Pay seller
        IERC20(s.payToken).safeTransfer(O.seller, O.price);
        emit SellerPaid(O.seller, O.price);

        // ── FEE DISTRIBUTION ────────────────────────────────────────────────
        // H-04: Use snapshot fees from order creation (fallback to current for legacy orders)
        uint16 tBps = O.snapshotTreasuryBps > 0 ? O.snapshotTreasuryBps : s.treasuryFeeBps;
        uint256 treasuryPortion = (O.price * tBps) / 10000;
        if (treasuryPortion > 0) {
            s.treasuryAccrued += treasuryPortion;
            emit TreasuryFeeAccrued(orderId, treasuryPortion);
        }

        // Node fee: only distributed when intermediate nodes were part of the order
        if (O.nodes.length > 0) {
            uint256 nodePortion = O.txFee > treasuryPortion ? O.txFee - treasuryPortion : 0;
            if (nodePortion > 0) {
                uint256 nodeCount = O.nodes.length;
                uint256 nodeReward = nodePortion / nodeCount;
                uint256 remainder = nodePortion % nodeCount;
                for (uint256 i = 0; i < nodeCount; i++) {
                    uint256 amount = nodeReward + (i == 0 ? remainder : 0);
                    IERC20(s.payToken).safeTransfer(O.nodes[i], amount);
                    emit NodeFeeDistributed(O.nodes[i], amount);
                }
            }
        }

        emit AuSysOrderSettled(orderId);
    }

    // ============================================================================
    // TOKEN DESTINATION SELECTION
    // ============================================================================

    /**
     * @notice Buyer selects where settled tokens go: burn or send to owned node
     * @param orderId The settled order with pending token destination
     * @param nodeId The node to send tokens to (ignored if burn=true)
     * @param burn If true, tokens are sent to dead address
     */
    function selectTokenDestination(
        bytes32 orderId,
        bytes32 nodeId,
        bool burn
    ) external nonReentrant whenNotPaused {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.AuSysOrder storage O = s.ausysOrders[orderId];

        if (!s.pendingTokenDestination[orderId]) revert NoPendingDestination();
        if (msg.sender != s.pendingTokenBuyer[orderId]) revert InvalidCaller();

        s.pendingTokenDestination[orderId] = false;
        delete s.pendingTokenBuyer[orderId];

        if (burn) {
            IERC1155(O.token).safeTransferFrom(address(this), address(0xdead), O.tokenId, O.tokenQuantity, '');
            // Seller custody was already released at settlement (_settleOrder).
            // Only the global tokenCustodyAmount needs to drop now — token is destroyed.
            if (O.token == address(this)) {
                uint256 tId = O.tokenId;
                uint256 qty = O.tokenQuantity;
                s.tokenCustodyAmount[tId] = s.tokenCustodyAmount[tId] >= qty
                    ? s.tokenCustodyAmount[tId] - qty
                    : 0;
            }
            emit TokenDestinationSelected(orderId, address(0xdead), bytes32(0), true);
        } else {
            if (nodeId == bytes32(0)) revert NodeRequired();
            DiamondStorage.Node storage node = s.nodes[nodeId];
            if (!node.active || !node.validNode) revert InvalidNode();
            if (node.owner != msg.sender) revert NotNodeOwner();
            if (O.token == address(this)) {
                _creditOwnerNodeSellable(s, node.owner, O.tokenId, nodeId, O.tokenQuantity);
                // Seller custody was already released at settlement (_settleOrder).
                // Just attribute custody to the buyer's chosen node.
                _attributeCustodyToNode(s, node.owner, O.tokenId, nodeId, O.tokenQuantity);
            }
            IERC1155(O.token).safeTransferFrom(address(this), node.owner, O.tokenId, O.tokenQuantity, '');
            emit TokenDestinationSelected(orderId, node.owner, nodeId, false);
        }
    }

    /**
     * @notice Release custody attributed to the seller's nodes using the per-order escrow snapshot.
     * @dev    Called from selectTokenDestination. The escrow snapshot records exactly which nodes
     *         contributed to the escrow and how much, so we can precisely decrement
     *         tokenNodeCustodyAmounts per node without guessing.
     * @param  decrementTotal  If true (burn path) also decrement the global tokenCustodyAmount.
     *                         If false (send-to-node path) custody is transferred, not released,
     *                         so the global total is unchanged.
     */
    function _releaseCustodyFromEscrowSnapshot(
        DiamondStorage.AppStorage storage s,
        bytes32 orderId,
        address seller,
        uint256 tokenId,
        uint256 quantity,
        bool decrementTotal
    ) internal {
        // Seller wallet-level custody
        if (s.tokenCustodianAmounts[tokenId][seller] >= quantity) {
            s.tokenCustodianAmounts[tokenId][seller] -= quantity;
        } else {
            s.tokenCustodianAmounts[tokenId][seller] = 0;
        }

        // Per-node custody using the escrow snapshot (populated by _debitOwnerSellableForEscrow)
        bytes32[] storage escrowNodes = s.ausysOrderEscrowNodes[orderId];
        uint256 nodeCount = escrowNodes.length;
        for (uint256 i = 0; i < nodeCount; i++) {
            bytes32 nodeHash = escrowNodes[i];
            uint256 debit = s.ausysOrderEscrowNodeDebits[orderId][nodeHash];
            if (debit == 0) continue;
            if (s.tokenNodeCustodyAmounts[tokenId][nodeHash] >= debit) {
                s.tokenNodeCustodyAmounts[tokenId][nodeHash] -= debit;
            } else {
                s.tokenNodeCustodyAmounts[tokenId][nodeHash] = 0;
            }
        }

        // Global total — only decrement on burn (custody destroyed, not transferred)
        if (decrementTotal) {
            if (s.tokenCustodyAmount[tokenId] >= quantity) {
                s.tokenCustodyAmount[tokenId] -= quantity;
            } else {
                s.tokenCustodyAmount[tokenId] = 0;
            }
        }
    }

    /**
     * @notice Attribute custody to a buyer's node after P2P settlement.
     * @dev    Mirrors what _nodeMintInternal does at mint time: credits both the wallet-level
     *         custodian map and the per-node custody map. This keeps the custody ledger accurate
     *         for secondary holders who want to redeem from their own node later.
     */
    function _attributeCustodyToNode(
        DiamondStorage.AppStorage storage s,
        address nodeOwner,
        uint256 tokenId,
        bytes32 nodeHash,
        uint256 quantity
    ) internal {
        s.tokenCustodianAmounts[tokenId][nodeOwner] += quantity;
        s.tokenNodeCustodyAmounts[tokenId][nodeHash] += quantity;
        // tokenCustodyAmount (global total) is unchanged: custody transferred, not created.
    }

    function _creditOwnerNodeSellable(
        DiamondStorage.AppStorage storage s,
        address owner,
        uint256 tokenId,
        bytes32 nodeHash,
        uint256 amount
    ) internal {
        if (owner == address(0) || nodeHash == bytes32(0) || amount == 0) return;

        if (!s.ownerTokenHasSellableNode[owner][tokenId][nodeHash]) {
            s.ownerTokenHasSellableNode[owner][tokenId][nodeHash] = true;
            s.ownerTokenSellableNodes[owner][tokenId].push(nodeHash);
        }

        s.ownerNodeSellableAmounts[owner][tokenId][nodeHash] += amount;
    }

    function _debitOwnerSellableForEscrow(
        DiamondStorage.AppStorage storage s,
        bytes32 orderId,
        address owner,
        uint256 tokenId,
        uint256 amount,
        bytes32 pinNode  // if non-zero, debit ONLY this node (no cross-node spill)
    ) internal {
        uint256 remaining = amount;

        if (pinNode != bytes32(0)) {
            // Pinned mode: debit exclusively from the seller's specified node.
            // Prevents silently draining a different node when the operator has multiple.
            uint256 nodeAmount = s.ownerNodeSellableAmounts[owner][tokenId][pinNode];
            if (nodeAmount < amount) revert ExceedsNodeSellableAmount();
            s.ownerNodeSellableAmounts[owner][tokenId][pinNode] -= amount;
            remaining = 0;

            if (!s.ausysOrderEscrowNodeSeen[orderId][pinNode]) {
                s.ausysOrderEscrowNodeSeen[orderId][pinNode] = true;
                s.ausysOrderEscrowNodes[orderId].push(pinNode);
            }
            s.ausysOrderEscrowNodeDebits[orderId][pinNode] += amount;
        } else {
            // Legacy/fallback: spread across tracked nodes in registration order.
            // Only used for non-node (external token) orders or legacy callers.
            bytes32[] storage trackedNodes = s.ownerTokenSellableNodes[owner][tokenId];
            for (uint256 i = 0; i < trackedNodes.length && remaining > 0; i++) {
                bytes32 nodeHash = trackedNodes[i];
                uint256 nodeAmount = s.ownerNodeSellableAmounts[owner][tokenId][nodeHash];
                if (nodeAmount == 0) continue;

                uint256 debited = nodeAmount > remaining ? remaining : nodeAmount;
                s.ownerNodeSellableAmounts[owner][tokenId][nodeHash] -= debited;
                remaining -= debited;

                if (!s.ausysOrderEscrowNodeSeen[orderId][nodeHash]) {
                    s.ausysOrderEscrowNodeSeen[orderId][nodeHash] = true;
                    s.ausysOrderEscrowNodes[orderId].push(nodeHash);
                }
                s.ausysOrderEscrowNodeDebits[orderId][nodeHash] += debited;
            }
            if (remaining > 0) revert ExceedsNodeSellableAmount();
        }

        // Node custody drops at escrow creation — the physical asset is now committed
        // to a buyer and is no longer freely available on the node.
        // decrementTotal=false: ERC1155 still exists (locked in Diamond), global
        // tokenCustodyAmount only drops if/when the buyer burns the token later.
        _releaseCustodyFromEscrowSnapshot(s, orderId, owner, tokenId, amount, false);
    }

    function _restoreEscrowedOwnerSellable(
        DiamondStorage.AppStorage storage s,
        bytes32 orderId,
        address owner,
        uint256 tokenId
    ) internal {
        bytes32[] storage escrowNodes = s.ausysOrderEscrowNodes[orderId];
        uint256 nodeCount = escrowNodes.length;

        for (uint256 i = 0; i < nodeCount; i++) {
            bytes32 nodeHash = escrowNodes[i];
            uint256 amount = s.ausysOrderEscrowNodeDebits[orderId][nodeHash];
            if (amount == 0) continue;
            // Restore sellable balance
            _creditOwnerNodeSellable(s, owner, tokenId, nodeHash, amount);
            // Restore node custody — was decremented at escrow creation, must unwind on cancel
            _attributeCustodyToNode(s, owner, tokenId, nodeHash, amount);
            s.ausysOrderEscrowNodeDebits[orderId][nodeHash] = 0;
        }
    }

    event OrderQuantityCorrected(bytes32 indexed orderId, uint256 oldQuantity, uint256 newQuantity);
}
// sellerNode pin retrigger

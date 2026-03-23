// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CLOBLib } from './CLOBLib.sol';

/**
 * @title DiamondStorage
 * @notice Library to access Diamond AppStorage at a specific storage slot
 * @dev Production-ready storage with gas-optimized CLOB structures
 *      Aligned with legacy contracts: AuraAsset, Aurum, AuSys, RWYVault, OrderBridge
 */
library DiamondStorage {
    bytes32 constant APP_STORAGE_POSITION = keccak256('diamond.app.storage');

    // ============================================================================
    // RBAC ROLE CONSTANTS (from AuSys.sol)
    // ============================================================================
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant DRIVER_ROLE = keccak256("DRIVER_ROLE");
    bytes32 constant DISPATCHER_ROLE = keccak256("DISPATCHER_ROLE");
    bytes32 constant NODE_REGISTRAR_ROLE = keccak256("NODE_REGISTRAR_ROLE");

    struct AppStorage {
        // ======= OWNERSHIP =======
        address owner;
        address pendingOwner;
        bool initialized;

        // ======= NODES =======
        mapping(bytes32 => Node) nodes;
        mapping(address => bytes32[]) ownerNodes;
        address[] nodeList;
        uint256 totalNodes;
        mapping(bytes32 => mapping(uint256 => NodeAsset)) nodeAssets;
        mapping(bytes32 => uint256[]) nodeAssetIds;
        mapping(bytes32 => uint256) totalNodeAssets;
        // Node admin system (from AurumNodeManager)
        mapping(address => bool) nodeAdmins;
        // Allowed node registrars
        mapping(address => bool) nodeRegistrars;
        address[] nodeRegistrarList;
        mapping(address => uint256) nodeRegistrarIndex;

        // ======= ASSETS (LEGACY) =======
        mapping(uint256 => Asset) assets;
        mapping(bytes32 => uint256) assetByHash;
        uint256 totalAssets;
        mapping(string => bool) supportedClasses;
        string[] classList;

        // ======= ERC1155 STORAGE (from AuraAsset.sol) =======
        // Core ERC1155 balances and approvals
        mapping(uint256 => mapping(address => uint256)) erc1155Balances;
        mapping(address => mapping(address => bool)) erc1155OperatorApprovals;
        string erc1155URI;
        // ERC1155Supply tracking
        mapping(uint256 => uint256) erc1155TotalSupply;
        mapping(uint256 => bool) erc1155Exists;
        
        // ======= AURA ASSET REGISTRY (from AuraAsset.sol) =======
        // Supported assets with full metadata
        mapping(string => AssetDefinition) nameToSupportedAssets;
        mapping(string => uint256) nameToSupportedAssetIndex;
        string[] supportedAssetNames;
        // Supported classes with tombstoning
        mapping(string => string) nameToSupportedClass;
        mapping(string => uint256) nameToSupportedClassIndex;
        string[] supportedClassNames;
        // Hash tracking for IPFS/metadata
        mapping(bytes32 => string) hashToClass;
        mapping(bytes32 => bool) isClassActive;
        mapping(bytes32 => uint256) hashToTokenID;
        bytes32[] ipfsID;
        // Custody tracking (physical asset custody)
        mapping(uint256 => address) tokenCustodian; // DEPRECATED: single-custodian model removed
        mapping(uint256 => uint256) tokenCustodyAmount; // Total custody amount across all custodians

        // ======= ORDERS =======
        mapping(bytes32 => Order) orders;
        address[] orderList;
        uint256 totalOrders;

        // ======= STAKING (DEPRECATED - use RWYStorage for RWY staking) =======
        mapping(address => Stake) stakes;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;

        // ======= OPERATORS (for RWY Staking) =======
        mapping(address => bool) approvedOperators;
        mapping(address => uint256) operatorReputation;
        mapping(address => uint256) operatorSuccessfulOps;
        mapping(address => uint256) operatorTotalValueProcessed;

        // ======= TOKEN ADDRESSES =======
        address auraAssetAddress;

        // ======= NODE TOKEN INVENTORY =======
        // Internal accounting: nodeHash => tokenId => balance
        // Tracks how many tokens each node "owns" within the Diamond
        mapping(bytes32 => mapping(uint256 => uint256)) nodeTokenBalances;
        // Track all token IDs a node has ever held (for enumeration)
        mapping(bytes32 => uint256[]) nodeTokenIds;
        // Quick lookup: does node have this token ID in their list?
        mapping(bytes32 => mapping(uint256 => bool)) nodeHasToken;

        // ======= BRIDGE (from OrderBridge.sol) =======
        address clobAddress;
        address ausysAddress;
        address quoteTokenAddress;
        mapping(bytes32 => UnifiedOrder) unifiedOrders;
        bytes32[] unifiedOrderIds;
        uint256 totalUnifiedOrders;
        address feeRecipient;
        uint256 protocolFeePercentage;
        uint256 bountyPercentage;
        mapping(bytes32 => Journey) journeys;
        mapping(bytes32 => bytes32[]) orderJourneys;
        mapping(bytes32 => uint256) totalJourneys;
        // Bridge lookup mappings (from OrderBridge.sol)
        mapping(bytes32 => bytes32) clobTradeToUnifiedOrder;
        mapping(bytes32 => bytes32) clobOrderToUnifiedOrder;
        mapping(address => bytes32[]) buyerUnifiedOrders;
        mapping(address => bytes32[]) sellerUnifiedOrders;

        // ======= AUSYS (from AuSys.sol) =======
        // Payment token for bounties/settlements
        address payToken;
        // AuSys Orders
        mapping(bytes32 => AuSysOrder) ausysOrders;
        bytes32[] ausysOrderIds;
        uint256 ausysOrderIdCounter;
        // AuSys Journeys
        mapping(bytes32 => AuSysJourney) ausysJourneys;
        uint256 ausysJourneyIdCounter;
        mapping(bytes32 => bytes32) journeyToAusysOrderId;
        mapping(address => bytes32[]) driverToJourneyIds;
        // Signature tracking
        mapping(address => mapping(bytes32 => bool)) customerHandOff;
        mapping(address => mapping(bytes32 => bool)) driverPickupSigned;
        mapping(address => mapping(bytes32 => bool)) driverDeliverySigned;
        mapping(bytes32 => bool) journeyRewardPaid;
        // RBAC for AuSys
        mapping(bytes32 => mapping(address => bool)) ausysRoles;
        mapping(address => uint256) driverRoleIndex;
        address[] driverRoleMembers;
        // P2P offer tracking
        bytes32[] openP2POfferIds;                    // Track open (unaccepted) P2P offers
        mapping(address => bytes32[]) userP2POffers;  // Track P2P offers by creator

        // ======= CLOB LOGISTICS (from IAuraCLOB) =======
        // Driver management
        mapping(address => DriverInfo) clobDrivers;
        address[] clobDriverList;
        // Logistics orders
        mapping(bytes32 => LogisticsOrder) clobLogisticsOrders;
        bytes32[] clobLogisticsOrderIds;

        // ======= CLOB =======
        mapping(bytes32 => Market) markets;
        bytes32[] marketIds;
        uint256 totalMarkets;
        mapping(bytes32 => CLOBOrder) clobOrders;
        bytes32[] clobOrderIds;
        uint256 totalCLOBOrders;
        mapping(bytes32 => Trade) trades;
        bytes32[] tradeIds;
        uint256 totalTrades;
        mapping(bytes32 => LiquidityPool) pools;
        bytes32[] poolIds;
        uint256 totalPools;
        mapping(bytes32 => mapping(uint256 => bytes32[])) bidOrders;
        mapping(bytes32 => mapping(uint256 => bytes32[])) askOrders;
        mapping(bytes32 => uint256[]) bidPrices;
        mapping(bytes32 => uint256[]) askPrices;

        // ======= CLOB V2 - PRODUCTION READY =======
        // Packed orders for gas efficiency (3 slots instead of 10)
        mapping(bytes32 => PackedOrder) packedOrders;
        uint256 orderNonce;  // Global nonce for unique order IDs
        
        // Red-Black Trees for O(log n) price level management
        // Flattened structure for Diamond storage compatibility
        // marketId => tree metadata
        mapping(bytes32 => RBTreeMeta) bidTreeMeta;
        mapping(bytes32 => RBTreeMeta) askTreeMeta;
        // marketId => price => node data
        mapping(bytes32 => mapping(uint256 => RBNode)) bidTreeNodes;
        mapping(bytes32 => mapping(uint256 => RBNode)) askTreeNodes;
        
        // Price level FIFO queues: marketId => price => PriceLevel
        mapping(bytes32 => mapping(uint256 => PriceLevel)) bidLevels;
        mapping(bytes32 => mapping(uint256 => PriceLevel)) askLevels;
        
        // Order queue nodes for FIFO within price levels
        mapping(bytes32 => OrderQueueNode) orderQueue;
        
        // MEV Protection: Commit-Reveal
        mapping(bytes32 => CommittedOrder) committedOrders;
        uint8 minRevealDelay;  // Minimum blocks between commit and reveal
        uint256 commitmentThreshold;  // Order size threshold requiring commit-reveal
        
        // Circuit Breakers
        mapping(bytes32 => CircuitBreaker) circuitBreakers;
        uint256 defaultPriceChangeThreshold;  // Default: 1000 = 10%
        uint256 defaultCooldownPeriod;  // Default: 5 minutes
        
        // Emergency Recovery
        mapping(bytes32 => EmergencyAction) pendingEmergencyActions;
        uint256 emergencyTimelock;  // Default: 48 hours
        mapping(address => uint256) userEmergencyWithdrawals;
        
        // Fee configuration (basis points, 100 = 1%)
        uint16 takerFeeBps;
        uint16 makerFeeBps;
        uint16 lpFeeBps;
        
        // Rate limiting
        mapping(address => RateLimit) userRateLimits;
        uint256 maxOrdersPerBlock;
        uint256 maxVolumePerBlock;

        // ======= VERSIONING =======
        uint256 version;
        string versionString;

        // ======= PAUSE =======
        bool paused;
        uint256 pauseStartTime;

        // ======= NODE SUPPORTING DOCUMENTS =======
        // nodeHash => document index => SupportingDocument
        mapping(bytes32 => mapping(uint256 => SupportingDocument)) nodeSupportingDocuments;
        // nodeHash => array of document indices
        mapping(bytes32 => uint256[]) nodeSupportingDocumentIds;
        // nodeHash => total documents count
        mapping(bytes32 => uint256) totalNodeSupportingDocuments;

        // ======= MULTI-CUSTODIAN TRACKING =======
        // Per-custodian amounts: tokenId => custodian address => amount in custody
        // Multiple nodes can mint the same tokenId; each tracks their own custody
        mapping(uint256 => mapping(address => uint256)) tokenCustodianAmounts;

        // Per-node custody: tokenId => nodeHash => amount in custody at this specific node
        // Needed because multiple nodes can share the same owner wallet
        mapping(uint256 => mapping(bytes32 => uint256)) tokenNodeCustodyAmounts;

        // ======= OWNER-NODE SELLABLE ALLOCATION =======
        // Wallet-held, node-attributed sellable amounts: owner => tokenId => nodeHash => amount
        // This preserves a canonical split for holders with balances linked to multiple nodes.
        mapping(address => mapping(uint256 => mapping(bytes32 => uint256))) ownerNodeSellableAmounts;
        // Enumerates node hashes that have ever had sellable allocation for a given owner/token.
        mapping(address => mapping(uint256 => bytes32[])) ownerTokenSellableNodes;
        mapping(address => mapping(uint256 => mapping(bytes32 => bool))) ownerTokenHasSellableNode;
        // Tracks how much sellable allocation was debited per order escrow, by node.
        // Used to restore attribution on seller-offer cancellation refunds.
        mapping(bytes32 => mapping(bytes32 => uint256)) ausysOrderEscrowNodeDebits;
        mapping(bytes32 => bytes32[]) ausysOrderEscrowNodes;
        mapping(bytes32 => mapping(bytes32 => bool)) ausysOrderEscrowNodeSeen;

        // ======= TOKEN DESTINATION ESCROW =======
        mapping(bytes32 => bool) pendingTokenDestination;
        mapping(bytes32 => address) pendingTokenBuyer;
        mapping(bytes32 => uint256) ausysOrderSettledAt;
        mapping(bytes32 => bool) ausysOrderTokenEscrowed;

        // ======= AUSYS SECURITY =======
        // Nonce-based replay protection for P2P offer acceptance
        mapping(address => mapping(uint256 => bool)) ausysUsedNonces;
        // Trusted off-chain signer that authorises P2P offer acceptance (EIP-712)
        address trustedP2PSigner;

        // ======= TREASURY =======
        // Accrued protocol fees claimable by owner (pull pattern)
        uint256 treasuryAccrued;
        // Fee rates in basis points (100 bps = 1%). Defaults set during init.
        uint16 treasuryFeeBps; // default 10 = 0.1% — always charged
        uint16 nodeFeeBps;     // default 10 = 0.1% — only charged when intermediate nodes present

        // ======= AUDIT 2026-03-10 ADDITIONS =======
        // M-05: Namespaced reentrancy guard (replaces OZ slot-0 guard)
        uint256 reentrancyStatus; // 1 = not entered, 2 = entered

        // L-03: Node registrar cap
        uint256 maxNodesPerRegistrar; // 0 = unlimited (default)

        // L-01: Renounce ownership timelock
        uint256 pendingRenounceTimestamp; // 0 = no pending renounce

        // L-06: ERC1155 receiver token whitelist
        mapping(address => bool) acceptedTokenContracts;
        bool erc1155WhitelistEnabled;

        // ======= RESERVED =======
        uint256[46] __reserved1;
        mapping(bytes32 => uint256) __reserved2;
    }
    
    // ============================================================================
    // PRODUCTION CLOB STRUCTS
    // ============================================================================
    
    /// @notice Gas-optimized order storage (3 slots instead of 10)
    struct PackedOrder {
        // Slot 1: maker(160) | isBuy(1) | orderType(2) | status(2) | timeInForce(3) | nonce(88)
        uint256 makerAndFlags;
        // Slot 2: price(96) | amount(96) | filledAmount(64)
        uint256 priceAmountFilled;
        // Slot 3: expiry(40) | createdAt(40) | marketIndex(32) | baseToken(160) - for token reference
        uint256 expiryAndMeta;
        // Slot 4: marketId for lookups (could be computed but stored for efficiency)
        bytes32 marketId;
    }
    
    /// @notice Price level with FIFO queue of orders
    struct PriceLevel {
        bytes32 head;       // First order in queue
        bytes32 tail;       // Last order in queue
        uint256 totalAmount;
        uint256 orderCount;
    }
    
    /// @notice Order queue node for FIFO within price level
    struct OrderQueueNode {
        bytes32 prev;
        bytes32 next;
        uint256 price;  // Store price for quick access during removal
    }
    
    /// @notice Committed order for MEV protection
    struct CommittedOrder {
        bytes32 commitment;  // keccak256(order params + salt)
        uint256 commitBlock;
        address committer;
        bool revealed;
        bool expired;
    }
    
    /// @notice Circuit breaker configuration per market
    struct CircuitBreaker {
        uint256 lastPrice;
        uint256 priceChangeThreshold;  // Basis points (1000 = 10%)
        uint256 cooldownPeriod;
        uint256 tripTimestamp;
        bool isTripped;
        bool isEnabled;
    }
    
    /// @notice Emergency action pending timelock
    struct EmergencyAction {
        address initiator;
        address token;
        address recipient;
        uint256 amount;
        uint256 initiatedAt;
        bool executed;
        bool cancelled;
    }
    
    /// @notice Rate limiting per user
    struct RateLimit {
        uint256 lastBlock;
        uint256 ordersThisBlock;
        uint256 volumeThisBlock;
    }
    
    /// @notice Red-Black Tree metadata (root and count)
    struct RBTreeMeta {
        uint256 root;
        uint256 count;
    }
    
    /// @notice Red-Black Tree node
    struct RBNode {
        uint256 parent;
        uint256 left;
        uint256 right;
        uint8 color;      // 0 = RED, 1 = BLACK
        bool exists;
        uint256 totalAmount;  // Aggregate amount at this price level
        uint256 orderCount;   // Number of orders at this price
    }
    
    /// @notice Enhanced market with token addresses
    struct MarketV2 {
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        bool active;
        uint256 createdAt;
        uint256 lastTradePrice;
        uint256 volume24h;
        uint256 trades24h;
    }

    struct Node {
        address owner;
        string nodeType;
        uint256 capacity;
        uint256 createdAt;
        bool active;
        bool validNode;
        bytes32 assetHash;
        string addressName;
        string lat;
        string lng;
    }

    struct NodeAsset {
        address token;
        uint256 tokenId;
        uint256 price;
        uint256 capacity;
        uint256 createdAt;
        bool active;
    }

    struct SupportingDocument {
        string url;
        string title;
        string description;
        string documentType;
        bool isFrozen;
        bool isRemoved;
        uint256 addedAt;
        uint256 removedAt;
        address addedBy;
        address removedBy;
    }

    struct Asset {
        string name;
        string assetClass;
        string[] attributes;
        uint256 createdAt;
        bool active;
    }

    // ============================================================================
    // AURA ASSET STRUCTS (from AuraAsset.sol)
    // ============================================================================

    /// @notice Asset attribute with name, values, and description
    struct Attribute {
        string name;
        string[] values;
        string description;
    }

    /// @notice Full asset definition with attributes (for minting)
    struct AssetDefinition {
        string name;
        string assetClass;
        Attribute[] attributes;
    }

    // ============================================================================
    // AUSYS STRUCTS (from AuSys.sol)
    // ============================================================================

    /// @notice Location with lat/lng coordinates
    struct Location {
        string lat;
        string lng;
    }

    /// @notice Parcel data for journey start/end locations
    struct ParcelData {
        Location startLocation;
        Location endLocation;
        string startName;
        string endName;
    }

    /// @notice AuSys Order (from AuSys.sol)
    /// @dev Status: 0=Created/PendingAcceptance, 1=Processing, 2=Settled, 3=Canceled, 4=Expired
    struct AuSysOrder {
        bytes32 id;
        address token;
        uint256 tokenId;
        uint256 tokenQuantity;
        uint256 price;
        uint256 txFee;
        address buyer;
        address seller;
        bytes32[] journeyIds;
        address[] nodes;
        ParcelData locationData;
        uint8 currentStatus;
        bytes32 contractualAgreement;
        // P2P extensions
        bool isSellerInitiated;      // true = seller created offer, false = buyer created
        address targetCounterparty;  // address(0) = open to all, else specific address only
        uint256 expiresAt;           // 0 = no expiry, else unix timestamp
        // H-04: Fee rate snapshot at creation time
        uint16 snapshotTreasuryBps;
        uint16 snapshotNodeBps;
        // Source node: the specific node the seller is fulfilling this order from.
        // Used by _debitOwnerSellableForEscrow to debit the correct node only.
        bytes32 sellerNode;
    }

    /// @notice AuSys Journey (from AuSys.sol)
    /// @dev Status: 0=Pending, 1=InTransit, 2=Delivered, 3=Canceled
    struct AuSysJourney {
        ParcelData parcelData;
        bytes32 journeyId;
        uint8 currentStatus;
        address sender;
        address receiver;
        address driver;
        uint256 journeyStart;
        uint256 journeyEnd;
        uint256 bounty;
        uint256 ETA;
    }

    // ============================================================================
    // CLOB LOGISTICS STRUCTS (from IAuraCLOB)
    // ============================================================================

    /// @notice Driver information for CLOB logistics
    struct DriverInfo {
        address driver;
        bool isActive;
        bool isAvailable;
        Location currentLocation;
        uint256 totalDeliveries;
        uint256 completedDeliveries;
        uint256 totalEarnings;
        uint256 rating; // Scaled by 100 (450 = 4.50)
    }

    /// @notice Logistics order for physical delivery
    /// @dev Status: 0=Created, 1=Assigned, 2=PickedUp, 3=InTransit, 4=Delivered, 5=Settled, 6=Cancelled, 7=Disputed
    struct LogisticsOrder {
        bytes32 orderId;
        bytes32 tradeId;
        address buyer;
        address seller;
        address sellerNode;
        address token;
        uint256 tokenId;
        uint256 quantity;
        uint256 totalPrice;
        uint256 escrowedAmount;
        uint256 driverBounty;
        Location pickupLocation;
        Location deliveryLocation;
        uint8 status;
        address assignedDriver;
        uint256 createdAt;
        uint256 deliveredAt;
    }

    struct Order {
        address buyer;
        address seller;
        bytes32 orderHash;
        uint256 price;
        uint256 amount;
        string status;
        uint256 createdAt;
    }

    struct Stake {
        uint256 amount;
        uint256 rewards;
        uint256 stakedAt;
    }

    /// @notice Unified order bridging CLOB and AuSys (from OrderBridge.sol)
    /// @dev Status: 0=PendingTrade, 1=TradeMatched, 2=LogisticsCreated, 3=InTransit, 4=Delivered, 5=Settled, 6=Cancelled
    struct UnifiedOrder {
        bytes32 clobOrderId;
        bytes32 clobTradeId;
        bytes32 ausysOrderId;
        address buyer;
        address seller;
        address sellerNode;
        address token;
        uint256 tokenId;
        uint256 tokenQuantity;
        uint256 price;
        uint256 bounty;
        uint256 escrowedAmount;
        uint8 status;
        uint8 logisticsStatus;
        uint256 createdAt;
        uint256 matchedAt;
        uint256 deliveredAt;
        uint256 settledAt;
        uint256 expiresAt;
        ParcelData deliveryData;
        bytes32[] journeyIds;
    }

    struct Journey {
        bytes32 unifiedOrderId;
        address driver;
        uint8 phase;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Market {
        string baseToken;
        uint256 baseTokenId;
        string quoteToken;
        bool active;
        uint256 createdAt;
    }

    struct CLOBOrder {
        address maker;
        bytes32 marketId;
        uint256 price;
        uint256 amount;
        uint256 filledAmount;
        bool isBuy;
        uint8 orderType;
        uint8 status;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Trade {
        bytes32 takerOrderId;
        bytes32 makerOrderId;
        address taker;
        address maker;
        bytes32 marketId;
        uint256 price;
        uint256 amount;
        uint256 quoteAmount;
        uint256 timestamp;
        uint256 createdAt;
    }

    struct LiquidityPool {
        string baseToken;
        uint256 baseTokenId;
        string quoteToken;
        uint256 baseReserve;
        uint256 quoteReserve;
        uint256 totalLpTokens;
        bool isActive;
        uint256 createdAt;
    }
    
    /// @notice Enhanced trade with more details for indexing
    struct TradeV2 {
        bytes32 takerOrderId;
        bytes32 makerOrderId;
        address taker;
        address maker;
        bytes32 marketId;
        uint256 price;
        uint256 amount;
        uint256 quoteAmount;
        uint256 takerFee;
        uint256 makerFee;
        uint256 timestamp;
        bool takerIsBuy;
    }

    function appStorage() internal pure returns (AppStorage storage ds) {
        bytes32 position = APP_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}

// Helper functions for common operations
library AppStorageLib {
    using DiamondStorage for DiamondStorage.AppStorage;

    function s() internal pure returns (DiamondStorage.AppStorage storage) {
        return DiamondStorage.appStorage();
    }

    // Node functions
    function getNode(bytes32 nodeHash) internal view returns (DiamondStorage.Node storage) {
        return s().nodes[nodeHash];
    }

    function isNodeOwner(bytes32 nodeHash, address account) internal view returns (bool) {
        return s().nodes[nodeHash].owner == account;
    }

    // Asset functions
    function getAsset(uint256 assetId) internal view returns (DiamondStorage.Asset storage) {
        return s().assets[assetId];
    }

    // Order functions
    function getOrder(bytes32 orderHash) internal view returns (DiamondStorage.Order storage) {
        return s().orders[orderHash];
    }

    // Stake functions
    function getStake(address user) internal view returns (DiamondStorage.Stake storage) {
        return s().stakes[user];
    }

    // Unified order functions
    function getUnifiedOrder(bytes32 orderId) internal view returns (DiamondStorage.UnifiedOrder storage) {
        return s().unifiedOrders[orderId];
    }

    // CLOB functions
    function getCLOBOrder(bytes32 orderId) internal view returns (DiamondStorage.CLOBOrder storage) {
        return s().clobOrders[orderId];
    }

    function getTrade(bytes32 tradeId) internal view returns (DiamondStorage.Trade storage) {
        return s().trades[tradeId];
    }

    function getPool(bytes32 poolId) internal view returns (DiamondStorage.LiquidityPool storage) {
        return s().pools[poolId];
    }

    function getMarket(bytes32 marketId) internal view returns (DiamondStorage.Market storage) {
        return s().markets[marketId];
    }

    function getNodeAsset(bytes32 nodeHash, uint256 assetId) internal view returns (DiamondStorage.NodeAsset storage) {
        return s().nodeAssets[nodeHash][assetId];
    }
    
    // Production CLOB functions
    function getPackedOrder(bytes32 orderId) internal view returns (DiamondStorage.PackedOrder storage) {
        return s().packedOrders[orderId];
    }
    
    function getCircuitBreaker(bytes32 marketId) internal view returns (DiamondStorage.CircuitBreaker storage) {
        return s().circuitBreakers[marketId];
    }
    
    function getCommittedOrder(bytes32 commitmentId) internal view returns (DiamondStorage.CommittedOrder storage) {
        return s().committedOrders[commitmentId];
    }
    
    function getPriceLevel(bytes32 marketId, uint256 price, bool isBid) internal view returns (DiamondStorage.PriceLevel storage) {
        if (isBid) {
            return s().bidLevels[marketId][price];
        } else {
            return s().askLevels[marketId][price];
        }
    }

    // ============================================================================
    // AUSYS HELPER FUNCTIONS
    // ============================================================================

    function getAuSysOrder(bytes32 orderId) internal view returns (DiamondStorage.AuSysOrder storage) {
        return s().ausysOrders[orderId];
    }

    function getAuSysJourney(bytes32 journeyId) internal view returns (DiamondStorage.AuSysJourney storage) {
        return s().ausysJourneys[journeyId];
    }

    function hasAuSysRole(bytes32 role, address account) internal view returns (bool) {
        return s().ausysRoles[role][account];
    }

    // ============================================================================
    // CLOB LOGISTICS HELPER FUNCTIONS
    // ============================================================================

    function getDriverInfo(address driver) internal view returns (DiamondStorage.DriverInfo storage) {
        return s().clobDrivers[driver];
    }

    function getLogisticsOrder(bytes32 orderId) internal view returns (DiamondStorage.LogisticsOrder storage) {
        return s().clobLogisticsOrders[orderId];
    }

    // ============================================================================
    // ERC1155 HELPER FUNCTIONS
    // ============================================================================

    function getERC1155Balance(uint256 tokenId, address account) internal view returns (uint256) {
        return s().erc1155Balances[tokenId][account];
    }

    function isERC1155ApprovedForAll(address account, address operator) internal view returns (bool) {
        return s().erc1155OperatorApprovals[account][operator];
    }

    function getERC1155TotalSupply(uint256 tokenId) internal view returns (uint256) {
        return s().erc1155TotalSupply[tokenId];
    }

    function erc1155TokenExists(uint256 tokenId) internal view returns (bool) {
        return s().erc1155Exists[tokenId];
    }

    // ============================================================================
    // CUSTODY HELPER FUNCTIONS
    // ============================================================================

    function getTokenCustodianAmount(uint256 tokenId, address custodian) internal view returns (uint256) {
        return s().tokenCustodianAmounts[tokenId][custodian];
    }

    function getTotalCustodyAmount(uint256 tokenId) internal view returns (uint256) {
        return s().tokenCustodyAmount[tokenId];
    }
}

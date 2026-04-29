// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title OrderStatus
 * @notice Shared status constants for all order types across facets
 * @dev Use these constants instead of magic numbers for consistency
 */
library OrderStatus {
    // ========================================================================
    // AUSYS ORDER STATUS
    // ========================================================================
    /// @dev AuSysOrder.currentStatus
    uint8 internal constant AUSYS_CREATED = 0;
    uint8 internal constant AUSYS_PROCESSING = 1;
    uint8 internal constant AUSYS_SETTLED = 2;
    uint8 internal constant AUSYS_CANCELED = 3;
    uint8 internal constant AUSYS_EXPIRED = 4;

    // ========================================================================
    // UNIFIED ORDER STATUS (BridgeFacet)
    // ========================================================================
    /// @dev UnifiedOrder.status
    uint8 internal constant UNIFIED_PENDING_TRADE = 0;
    uint8 internal constant UNIFIED_TRADE_MATCHED = 1;
    uint8 internal constant UNIFIED_LOGISTICS_CREATED = 2;
    uint8 internal constant UNIFIED_IN_TRANSIT = 3;
    uint8 internal constant UNIFIED_DELIVERED = 4;
    uint8 internal constant UNIFIED_SETTLED = 5;
    uint8 internal constant UNIFIED_CANCELLED = 6;

    // ========================================================================
    // LOGISTICS ORDER STATUS (CLOBLogisticsFacet)
    // ========================================================================
    /// @dev LogisticsOrder.status
    uint8 internal constant LOGISTICS_CREATED = 0;
    uint8 internal constant LOGISTICS_ASSIGNED = 1;
    uint8 internal constant LOGISTICS_PICKED_UP = 2;
    uint8 internal constant LOGISTICS_IN_TRANSIT = 3;
    uint8 internal constant LOGISTICS_DELIVERED = 4;
    uint8 internal constant LOGISTICS_SETTLED = 5;
    uint8 internal constant LOGISTICS_CANCELLED = 6;
    uint8 internal constant LOGISTICS_DISPUTED = 7;

    // ========================================================================
    // JOURNEY STATUS (AuSys)
    // ========================================================================
    /// @dev AuSysJourney.currentStatus and Journey.phase
    uint8 internal constant JOURNEY_PENDING = 0;
    uint8 internal constant JOURNEY_IN_TRANSIT = 1;
    uint8 internal constant JOURNEY_DELIVERED = 2;
    uint8 internal constant JOURNEY_CANCELED = 3;

    // ========================================================================
    // CLOB ORDER STATUS
    // ========================================================================
    /// @dev CLOBOrder.status / PackedOrder status
    uint8 internal constant CLOB_OPEN = 0;
    uint8 internal constant CLOB_PARTIALLY_FILLED = 1;
    uint8 internal constant CLOB_FILLED = 2;
    uint8 internal constant CLOB_CANCELLED = 3;
    uint8 internal constant CLOB_EXPIRED = 4;

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function ausysStatusName(uint8 status) internal pure returns (string memory) {
        if (status == AUSYS_CREATED) return "Created";
        if (status == AUSYS_PROCESSING) return "Processing";
        if (status == AUSYS_SETTLED) return "Settled";
        if (status == AUSYS_CANCELED) return "Canceled";
        if (status == AUSYS_EXPIRED) return "Expired";
        return "Unknown";
    }

    function unifiedStatusName(uint8 status) internal pure returns (string memory) {
        if (status == UNIFIED_PENDING_TRADE) return "PendingTrade";
        if (status == UNIFIED_TRADE_MATCHED) return "TradeMatched";
        if (status == UNIFIED_LOGISTICS_CREATED) return "LogisticsCreated";
        if (status == UNIFIED_IN_TRANSIT) return "InTransit";
        if (status == UNIFIED_DELIVERED) return "Delivered";
        if (status == UNIFIED_SETTLED) return "Settled";
        if (status == UNIFIED_CANCELLED) return "Cancelled";
        return "Unknown";
    }

    function logisticsStatusName(uint8 status) internal pure returns (string memory) {
        if (status == LOGISTICS_CREATED) return "Created";
        if (status == LOGISTICS_ASSIGNED) return "Assigned";
        if (status == LOGISTICS_PICKED_UP) return "PickedUp";
        if (status == LOGISTICS_IN_TRANSIT) return "InTransit";
        if (status == LOGISTICS_DELIVERED) return "Delivered";
        if (status == LOGISTICS_SETTLED) return "Settled";
        if (status == LOGISTICS_CANCELLED) return "Cancelled";
        if (status == LOGISTICS_DISPUTED) return "Disputed";
        return "Unknown";
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CLOBLib
 * @notice Production-ready library for CLOB operations with gas-efficient data structures
 * @dev Includes bitpacking helpers, red-black tree for price levels, and order management
 */
library CLOBLib {
    // ============================================================================
    // CONSTANTS
    // ============================================================================
    
    // Bitpacking positions for PackedOrder.makerAndFlags
    uint256 internal constant MAKER_MASK = (1 << 160) - 1;
    uint256 internal constant IS_BUY_SHIFT = 160;
    uint256 internal constant ORDER_TYPE_SHIFT = 161;
    uint256 internal constant STATUS_SHIFT = 163;
    uint256 internal constant TIME_IN_FORCE_SHIFT = 165;
    uint256 internal constant NONCE_SHIFT = 168;
    
    // Bitpacking positions for PackedOrder.priceAmountFilled
    uint256 internal constant PRICE_MASK = (1 << 96) - 1;
    uint256 internal constant AMOUNT_SHIFT = 96;
    uint256 internal constant AMOUNT_MASK = (1 << 96) - 1;
    uint256 internal constant FILLED_SHIFT = 192;
    uint256 internal constant FILLED_MASK = (1 << 64) - 1;
    
    // Bitpacking positions for PackedOrder.expiryAndMeta
    uint256 internal constant EXPIRY_MASK = (1 << 40) - 1;
    uint256 internal constant CREATED_AT_SHIFT = 40;
    uint256 internal constant CREATED_AT_MASK = (1 << 40) - 1;
    uint256 internal constant MARKET_INDEX_SHIFT = 80;
    
    // Order status values
    uint8 internal constant STATUS_OPEN = 0;
    uint8 internal constant STATUS_PARTIAL = 1;
    uint8 internal constant STATUS_FILLED = 2;
    uint8 internal constant STATUS_CANCELLED = 3;
    uint8 internal constant STATUS_EXPIRED = 4;
    
    // Time-in-force values
    uint8 internal constant TIF_GTC = 0;  // Good Till Cancel
    uint8 internal constant TIF_IOC = 1;  // Immediate Or Cancel
    uint8 internal constant TIF_FOK = 2;  // Fill Or Kill
    uint8 internal constant TIF_GTD = 3;  // Good Till Date
    
    // Order type values
    uint8 internal constant TYPE_LIMIT = 0;
    uint8 internal constant TYPE_MARKET = 1;
    
    // Red-Black Tree constants
    uint256 internal constant EMPTY = 0;
    uint8 internal constant RED = 0;
    uint8 internal constant BLACK = 1;
    
    // ============================================================================
    // STRUCTS (Reference - actual storage in DiamondStorage)
    // ============================================================================
    
    // Note: PackedOrder, RBNode, PriceLevel, OrderQueueNode are defined in DiamondStorage
    // These constants and functions work with those storage structures
    
    // ============================================================================
    // BITPACKING FUNCTIONS - PACK
    // ============================================================================
    
    /**
     * @notice Pack order data into makerAndFlags slot
     * @param maker Order maker address
     * @param isBuy True if buy order
     * @param orderType 0=Limit, 1=Market
     * @param status Order status
     * @param timeInForce Time-in-force type
     * @param nonce Order nonce for uniqueness
     */
    function packMakerAndFlags(
        address maker,
        bool isBuy,
        uint8 orderType,
        uint8 status,
        uint8 timeInForce,
        uint88 nonce
    ) internal pure returns (uint256) {
        return uint256(uint160(maker)) |
               (isBuy ? 1 << IS_BUY_SHIFT : 0) |
               (uint256(orderType & 0x3) << ORDER_TYPE_SHIFT) |
               (uint256(status & 0x3) << STATUS_SHIFT) |
               (uint256(timeInForce & 0x7) << TIME_IN_FORCE_SHIFT) |
               (uint256(nonce) << NONCE_SHIFT);
    }
    
    /**
     * @notice Pack price, amount, and filled into single slot
     * @param price Order price (max 96 bits)
     * @param amount Order amount (max 96 bits)
     * @param filledAmount Filled amount (max 64 bits)
     */
    function packPriceAmountFilled(
        uint96 price,
        uint96 amount,
        uint64 filledAmount
    ) internal pure returns (uint256) {
        return uint256(price) |
               (uint256(amount) << AMOUNT_SHIFT) |
               (uint256(filledAmount) << FILLED_SHIFT);
    }
    
    /**
     * @notice Pack expiry and metadata into single slot
     * @param expiry Expiration timestamp (0 for GTC)
     * @param createdAt Creation timestamp
     * @param marketIndex Market index for quick lookup
     */
    function packExpiryAndMeta(
        uint40 expiry,
        uint40 createdAt,
        uint32 marketIndex
    ) internal pure returns (uint256) {
        return uint256(expiry) |
               (uint256(createdAt) << CREATED_AT_SHIFT) |
               (uint256(marketIndex) << MARKET_INDEX_SHIFT);
    }
    
    // ============================================================================
    // BITPACKING FUNCTIONS - UNPACK
    // ============================================================================
    
    function unpackMaker(uint256 makerAndFlags) internal pure returns (address) {
        return address(uint160(makerAndFlags & MAKER_MASK));
    }
    
    function unpackIsBuy(uint256 makerAndFlags) internal pure returns (bool) {
        return (makerAndFlags >> IS_BUY_SHIFT) & 1 == 1;
    }
    
    function unpackOrderType(uint256 makerAndFlags) internal pure returns (uint8) {
        return uint8((makerAndFlags >> ORDER_TYPE_SHIFT) & 0x3);
    }
    
    function unpackStatus(uint256 makerAndFlags) internal pure returns (uint8) {
        return uint8((makerAndFlags >> STATUS_SHIFT) & 0x3);
    }
    
    function unpackTimeInForce(uint256 makerAndFlags) internal pure returns (uint8) {
        return uint8((makerAndFlags >> TIME_IN_FORCE_SHIFT) & 0x7);
    }
    
    function unpackNonce(uint256 makerAndFlags) internal pure returns (uint88) {
        return uint88(makerAndFlags >> NONCE_SHIFT);
    }
    
    function unpackPrice(uint256 priceAmountFilled) internal pure returns (uint96) {
        return uint96(priceAmountFilled & PRICE_MASK);
    }
    
    function unpackAmount(uint256 priceAmountFilled) internal pure returns (uint96) {
        return uint96((priceAmountFilled >> AMOUNT_SHIFT) & AMOUNT_MASK);
    }
    
    function unpackFilledAmount(uint256 priceAmountFilled) internal pure returns (uint64) {
        return uint64((priceAmountFilled >> FILLED_SHIFT) & FILLED_MASK);
    }
    
    function unpackExpiry(uint256 expiryAndMeta) internal pure returns (uint40) {
        return uint40(expiryAndMeta & EXPIRY_MASK);
    }
    
    function unpackCreatedAt(uint256 expiryAndMeta) internal pure returns (uint40) {
        return uint40((expiryAndMeta >> CREATED_AT_SHIFT) & CREATED_AT_MASK);
    }
    
    function unpackMarketIndex(uint256 expiryAndMeta) internal pure returns (uint32) {
        return uint32(expiryAndMeta >> MARKET_INDEX_SHIFT);
    }
    
    // ============================================================================
    // BITPACKING FUNCTIONS - UPDATE
    // ============================================================================
    
    /**
     * @notice Update status in packed makerAndFlags
     */
    function updateStatus(uint256 makerAndFlags, uint8 newStatus) internal pure returns (uint256) {
        // Clear old status bits and set new
        uint256 statusMask = uint256(0x3) << STATUS_SHIFT;
        return (makerAndFlags & ~statusMask) | (uint256(newStatus & 0x3) << STATUS_SHIFT);
    }
    
    /**
     * @notice Update filled amount in packed priceAmountFilled
     */
    function updateFilledAmount(uint256 priceAmountFilled, uint64 newFilled) internal pure returns (uint256) {
        uint256 filledMask = uint256(FILLED_MASK) << FILLED_SHIFT;
        return (priceAmountFilled & ~filledMask) | (uint256(newFilled) << FILLED_SHIFT);
    }
    
    /**
     * @notice Calculate remaining amount
     */
    function getRemainingAmount(uint256 priceAmountFilled) internal pure returns (uint96) {
        uint96 amount = unpackAmount(priceAmountFilled);
        uint64 filled = unpackFilledAmount(priceAmountFilled);
        return amount - uint96(filled);
    }
    
    // ============================================================================
    // SORTED PRICE LIST FUNCTIONS (Simplified for Diamond Storage)
    // ============================================================================
    
    // Note: Full RB-Tree implementation moved to use Diamond storage directly
    // These are helper functions that work with the flattened storage structure
    
    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================
    
    /**
     * @notice Check if an order is expired
     */
    function isExpired(uint256 expiryAndMeta) internal view returns (bool) {
        uint40 expiry = unpackExpiry(expiryAndMeta);
        // 0 means no expiry (GTC)
        return expiry != 0 && block.timestamp > expiry;
    }
    
    /**
     * @notice Check if order is active (open or partial)
     */
    function isActive(uint256 makerAndFlags) internal pure returns (bool) {
        uint8 status = unpackStatus(makerAndFlags);
        return status == STATUS_OPEN || status == STATUS_PARTIAL;
    }
    
    /**
     * @notice Calculate quote amount with overflow check
     */
    function calculateQuoteAmount(uint96 price, uint96 amount) internal pure returns (uint256) {
        return uint256(price) * uint256(amount);
    }
    
    /**
     * @notice Safe minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /**
     * @notice Safe maximum of two values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
    
    /**
     * @notice Calculate percentage change in basis points
     * @param oldValue Previous value
     * @param newValue New value
     * @return changeBps Change in basis points (10000 = 100%)
     */
    function calculatePriceChange(uint256 oldValue, uint256 newValue) internal pure returns (uint256 changeBps) {
        if (oldValue == 0) return newValue > 0 ? 10000 : 0;
        
        if (newValue >= oldValue) {
            changeBps = ((newValue - oldValue) * 10000) / oldValue;
        } else {
            changeBps = ((oldValue - newValue) * 10000) / oldValue;
        }
    }
    
    /**
     * @notice Integer square root using Babylonian method
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    
    /**
     * @notice Convert address to hex string
     */
    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(_addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
    
    /**
     * @notice Convert hex string to address
     * @dev Reverts if string is not valid hex address (42 chars starting with 0x)
     */
    function stringToAddress(string memory _str) internal pure returns (address) {
        bytes memory b = bytes(_str);
        require(b.length == 42, "Invalid address length");
        require(b[0] == "0" && (b[1] == "x" || b[1] == "X"), "Invalid address prefix");
        
        uint160 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            result *= 16;
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) {
                result += c - 48;
            } else if (c >= 97 && c <= 102) {
                result += c - 87;
            } else if (c >= 65 && c <= 70) {
                result += c - 55;
            } else {
                revert("Invalid hex char");
            }
        }
        return address(result);
    }
}


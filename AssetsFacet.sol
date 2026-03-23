// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { DiamondStorage } from '../libraries/DiamondStorage.sol';
import { LibDiamond } from '../libraries/LibDiamond.sol';
import { IERC1155 } from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import { IERC1155Receiver } from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import { IERC1155MetadataURI } from '@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol';
import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import { Address } from '@openzeppelin/contracts/utils/Address.sol';

/**
 * @title AssetsFacet
 * @notice Full ERC1155 implementation mirroring AuraAsset.sol
 * @dev Combines ERC1155, ERC1155Burnable, ERC1155Supply functionality
 *      Uses Diamond storage pattern for all state
 */
contract AssetsFacet is IERC1155, IERC1155MetadataURI {
    using Address for address;

    // ============================================================================
    // EVENTS (from AuraAsset.sol)
    // ============================================================================

    event MintedAsset(
        address indexed account,
        bytes32 indexed hash,
        uint256 indexed tokenId,
        string name,
        string assetClass,
        string className
    );

    event AssetAttributeAdded(
        bytes32 indexed hash,
        uint256 indexed attributeIndex,
        string name,
        string[] values,
        string description
    );

    event CustodyEstablished(
        uint256 indexed tokenId,
        address indexed custodian,
        uint256 amount
    );

    event CustodyReleased(
        uint256 indexed tokenId,
        address indexed custodian,
        uint256 amount,
        address indexed redeemer
    );

    /// @notice Emitted when a supported asset class is added
    /// @param classNameHash Indexed hash of the class name for efficient filtering
    /// @param className The class name string
    event SupportedClassAdded(
        bytes32 indexed classNameHash,
        string className
    );

    /// @notice Emitted when a supported asset class is removed
    /// @param classNameHash Indexed hash of the class name for efficient filtering
    /// @param className The class name string
    event SupportedClassRemoved(
        bytes32 indexed classNameHash,
        string className
    );

    // ============================================================================
    // ERRORS
    // ============================================================================

    error InvalidNode();
    error ClassInactive();
    error ClassAlreadyExists();
    error ClassNotFound();
    error AssetAlreadyExists();
    error InsufficientBalance();
    error ExceedsCustodyAmount();
    error ExceedsNodeSellableAmount();
    error NoCustodian();
    error DifferentCustodian(); // DEPRECATED: multi-custodian model now allows different minters
    error CannotRedeemOwnCustody();
    error ERC1155InvalidReceiver(address receiver);
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);
    error ERC1155MissingApprovalForAll(address operator, address owner);
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Validates that the account is a valid node (from AuraAsset.sol)
     * @dev Checks via NodesFacet.getNodeStatus()
     */
    modifier validNode(address node) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        // Check if Diamond itself (always valid) or check ownerNodes
        if (node != address(this)) {
            bytes32[] storage ownerNodes = s.ownerNodes[node];
            // Cache length to avoid repeated SLOAD
            uint256 nodeCount = ownerNodes.length;
            bool hasActiveNode = false;
            for (uint256 i = 0; i < nodeCount; i++) {
                // Cache node to avoid repeated SLOAD (saves ~3000 gas per iteration)
                DiamondStorage.Node storage nodeData = s.nodes[ownerNodes[i]];
                if (nodeData.active && nodeData.validNode) {
                    hasActiveNode = true;
                    break;
                }
            }
            if (!hasActiveNode) revert InvalidNode();
        }
        _;
    }

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    // ============================================================================
    // ERC1155 - BALANCE & APPROVAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Get the balance of an account's tokens
     */
    function balanceOf(address account, uint256 id) public view override returns (uint256) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.erc1155Balances[id][account];
    }

    /**
     * @notice Get the balance of multiple account/token pairs
     */
    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    ) public view override returns (uint256[] memory) {
        if (accounts.length != ids.length) {
            revert ERC1155InvalidArrayLength(ids.length, accounts.length);
        }

        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        uint256 accountCount = accounts.length;
        uint256[] memory batchBalances = new uint256[](accountCount);

        for (uint256 i = 0; i < accountCount; ++i) {
            batchBalances[i] = s.erc1155Balances[ids[i]][accounts[i]];
        }

        return batchBalances;
    }

    /**
     * @notice Set approval for an operator to manage all of caller's tokens
     */
    function setApprovalForAll(address operator, bool approved) public override {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        s.erc1155OperatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @notice Check if an operator is approved for all tokens of an owner
     */
    function isApprovedForAll(address account, address operator) public view override returns (bool) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.erc1155OperatorApprovals[account][operator];
    }

    // ============================================================================
    // ERC1155 - TRANSFER FUNCTIONS
    // ============================================================================

    /**
     * @notice Transfer tokens from one account to another
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) {
            revert ERC1155MissingApprovalForAll(msg.sender, from);
        }
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @notice Batch transfer tokens from one account to another
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) {
            revert ERC1155MissingApprovalForAll(msg.sender, from);
        }
        _safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    // ============================================================================
    // ERC1155 - METADATA URI
    // ============================================================================

    /**
     * @notice Returns the URI for a token ID
     */
    function uri(uint256 /* id */) public view override returns (string memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.erc1155URI;
    }

    /**
     * @notice Set the base URI for token metadata (from AuraAsset.sol)
     */
    function setURI(string memory newuri) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        s.erc1155URI = newuri;
    }

    // ============================================================================
    // ERC165 - INTERFACE SUPPORT
    // ============================================================================

    function supportsInterface(bytes4 interfaceId) public pure override(IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    // ============================================================================
    // ERC1155 SUPPLY - TOTAL SUPPLY TRACKING
    // ============================================================================

    /**
     * @notice Total amount of tokens in existence with a given ID
     */
    function totalSupply(uint256 id) public view returns (uint256) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.erc1155TotalSupply[id];
    }

    /**
     * @notice Indicates whether any token exists with a given ID
     */
    function exists(uint256 id) public view returns (bool) {
        return totalSupply(id) > 0;
    }

    // ============================================================================
    // NODE MINTING (from AuraAsset.sol)
    // ============================================================================

    /**
     * @notice Mint tokens via a valid node (from AuraAsset.nodeMint)
     * @dev Only callable by valid nodes. Establishes custody.
     * @param account The account to receive tokens (must be valid node)
     * @param asset The asset definition with attributes
     * @param amount Number of tokens to mint
     * @param className The class name for the asset
     * @param data Additional data for the receiver
     * @return hash The unique hash for this mint
     * @return tokenID The token ID
     */
    function nodeMint(
        address account,
        DiamondStorage.AssetDefinition memory asset,
        uint256 amount,
        string memory className,
        bytes memory data
    ) external validNode(msg.sender) returns (bytes32 hash, uint256 tokenID) {
        // Default path: uses first active node for per-node custody tracking
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        bytes32 mintingNode = _getFirstActiveNode(s, msg.sender);
        return _nodeMintInternal(account, asset, amount, className, data, mintingNode);
    }

    /**
     * @notice Mint tokens via a specific node — use when wallet owns multiple nodes
     * @param nodeHash The specific node hash to attribute custody to
     */
    function nodeMintForNode(
        address account,
        DiamondStorage.AssetDefinition memory asset,
        uint256 amount,
        string memory className,
        bytes memory data,
        bytes32 nodeHash
    ) external validNode(msg.sender) returns (bytes32 hash, uint256 tokenID) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        // Verify the caller owns this specific node and it's active
        DiamondStorage.Node storage node = s.nodes[nodeHash];
        require(node.active && node.validNode && node.owner == msg.sender, "Invalid node");
        return _nodeMintInternal(account, asset, amount, className, data, nodeHash);
    }

    function _getFirstActiveNode(
        DiamondStorage.AppStorage storage s,
        address owner
    ) internal view returns (bytes32) {
        bytes32[] storage ownerNodes = s.ownerNodes[owner];
        for (uint256 i = 0; i < ownerNodes.length; i++) {
            DiamondStorage.Node storage nodeData = s.nodes[ownerNodes[i]];
            if (nodeData.active && nodeData.validNode) {
                return ownerNodes[i];
            }
        }
        return bytes32(0);
    }

    function _nodeMintInternal(
        address account,
        DiamondStorage.AssetDefinition memory asset,
        uint256 amount,
        string memory className,
        bytes memory data,
        bytes32 mintingNodeHash
    ) internal returns (bytes32 hash, uint256 tokenID) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        // Require class to be active
        bytes32 classKey = keccak256(abi.encode(className));
        if (!s.isClassActive[classKey]) revert ClassInactive();

        // Generate token ID from asset definition
        tokenID = uint256(keccak256(abi.encode(asset)));
        hash = keccak256(abi.encode(account, asset));

        // Store hash mappings
        s.hashToClass[hash] = className;
        s.hashToTokenID[hash] = tokenID;
        s.ipfsID.push(hash);

        // Mint tokens
        _mint(account, tokenID, amount, data);

        // Establish custody - track per-custodian (wallet) amounts.
        // msg.sender is the node owner (custodian) — account is the recipient/buyer.
        s.tokenCustodianAmounts[tokenID][msg.sender] += amount;
        s.tokenCustodyAmount[tokenID] += amount;

        // Track per-node custody for multi-node wallets
        if (mintingNodeHash != bytes32(0)) {
            s.tokenNodeCustodyAmounts[tokenID][mintingNodeHash] += amount;
            _creditOwnerNodeSellable(s, account, tokenID, mintingNodeHash, amount);
        }

        emit CustodyEstablished(tokenID, account, amount);

        // Get resolved class name
        string memory resolvedClassName = s.hashToClass[hash];
        if (bytes(resolvedClassName).length == 0) {
            resolvedClassName = className;
        }

        // Emit main asset event
        emit MintedAsset(
            account,
            hash,
            tokenID,
            asset.name,
            asset.assetClass,
            resolvedClassName
        );

        // Emit separate events for each attribute
        uint256 attrCount = asset.attributes.length;
        for (uint256 i = 0; i < attrCount; i++) {
            emit AssetAttributeAdded(
                hash,
                i,
                asset.attributes[i].name,
                asset.attributes[i].values,
                asset.attributes[i].description
            );
        }
    }

    /**
     * @notice Lookup token ID from asset definition (from AuraAsset.lookupHash)
     */
    function lookupHash(DiamondStorage.AssetDefinition memory asset) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(asset)));
    }

    // ============================================================================
    // REDEMPTION / CUSTODY RELEASE (from AuraAsset.sol)
    // ============================================================================

    /**
     * @notice Redeem tokens - burns the tokens and releases them from custody
     * @dev This triggers physical delivery by the custodian node.
     *      The redeemer specifies which custodian to release from.
     * @param tokenId The token ID to redeem
     * @param amount The amount to redeem
     * @param custodian The custodian node to release custody from
     */
    function redeem(uint256 tokenId, uint256 amount, address custodian) external {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (s.erc1155Balances[tokenId][msg.sender] < amount) revert InsufficientBalance();
        if (custodian == address(0)) revert NoCustodian();
        if (msg.sender == custodian) revert CannotRedeemOwnCustody();
        if (s.tokenCustodianAmounts[tokenId][custodian] < amount) revert ExceedsCustodyAmount();
        _debitOwnerSellable(s, msg.sender, tokenId, amount);

        // Burn the tokens
        _burn(msg.sender, tokenId, amount);

        // Release from custody (per-custodian and total)
        s.tokenCustodianAmounts[tokenId][custodian] -= amount;
        s.tokenCustodyAmount[tokenId] -= amount;

        emit CustodyReleased(tokenId, custodian, amount, msg.sender);
    }

    /**
     * @notice Redeem tokens from a specific node — use when custodian wallet owns multiple nodes
     * @param tokenId The token ID to redeem
     * @param amount The amount to redeem
     * @param custodian The custodian wallet address
     * @param nodeHash The specific node hash to release custody from
     */
    function redeemFromNode(uint256 tokenId, uint256 amount, address custodian, bytes32 nodeHash) external {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (s.erc1155Balances[tokenId][msg.sender] < amount) revert InsufficientBalance();
        if (custodian == address(0)) revert NoCustodian();
        if (msg.sender == custodian) revert CannotRedeemOwnCustody();
        if (s.tokenCustodianAmounts[tokenId][custodian] < amount) revert ExceedsCustodyAmount();
        if (s.tokenNodeCustodyAmounts[tokenId][nodeHash] < amount) revert ExceedsCustodyAmount();
        if (s.ownerNodeSellableAmounts[msg.sender][tokenId][nodeHash] < amount) {
            revert ExceedsNodeSellableAmount();
        }

        // Verify node is owned by custodian
        require(s.nodes[nodeHash].owner == custodian, "Node not owned by custodian");

        // Burn the tokens
        _burn(msg.sender, tokenId, amount);

        // Release from custody (per-custodian, per-node, and total)
        s.tokenCustodianAmounts[tokenId][custodian] -= amount;
        s.tokenNodeCustodyAmounts[tokenId][nodeHash] -= amount;
        s.tokenCustodyAmount[tokenId] -= amount;
        s.ownerNodeSellableAmounts[msg.sender][tokenId][nodeHash] -= amount;

        emit CustodyReleased(tokenId, custodian, amount, msg.sender);
    }

    /**
     * @notice Get custody amount for a specific custodian of a token
     * @param tokenId The token ID to query
     * @param custodian The custodian address to query
     * @return amount The amount this custodian holds in custody
     */
    function getCustodyInfo(uint256 tokenId, address custodian) external view returns (uint256 amount) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.tokenCustodianAmounts[tokenId][custodian];
    }

    /**
     * @notice Get custody amount for a specific node (not wallet)
     * @param tokenId The token ID to query
     * @param nodeHash The node hash to query
     * @return amount The amount this specific node holds in custody
     */
    function getNodeCustodyInfo(uint256 tokenId, bytes32 nodeHash) external view returns (uint256 amount) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.tokenNodeCustodyAmounts[tokenId][nodeHash];
    }

    /**
     * @notice Get wallet-held sellable amount attributed to a specific node
     * @param owner The wallet owner
     * @param tokenId The token ID to query
     * @param nodeHash The node hash to query
     * @return amount The owner's sellable amount attributed to that node
     */
    function getNodeSellableAmount(
        address owner,
        uint256 tokenId,
        bytes32 nodeHash
    ) external view returns (uint256 amount) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.ownerNodeSellableAmounts[owner][tokenId][nodeHash];
    }

    /**
     * @notice Get all positive node sellable allocations for an owner/token
     * @param owner The wallet owner
     * @param tokenId The token ID to query
     * @return nodeHashes Nodes with positive sellable allocation
     * @return amounts Corresponding positive sellable amounts
     */
    function getOwnerNodeSellableBalances(
        address owner,
        uint256 tokenId
    ) external view returns (bytes32[] memory nodeHashes, uint256[] memory amounts) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        bytes32[] storage trackedNodes = s.ownerTokenSellableNodes[owner][tokenId];
        uint256 trackedCount = trackedNodes.length;
        uint256 positiveCount = 0;

        for (uint256 i = 0; i < trackedCount; i++) {
            if (s.ownerNodeSellableAmounts[owner][tokenId][trackedNodes[i]] > 0) {
                positiveCount++;
            }
        }

        nodeHashes = new bytes32[](positiveCount);
        amounts = new uint256[](positiveCount);

        uint256 idx = 0;
        for (uint256 i = 0; i < trackedCount; i++) {
            bytes32 nodeHash = trackedNodes[i];
            uint256 amount = s.ownerNodeSellableAmounts[owner][tokenId][nodeHash];
            if (amount == 0) continue;
            nodeHashes[idx] = nodeHash;
            amounts[idx] = amount;
            idx++;
        }
    }

    /**
     * @notice Get total custody amount across all custodians for a token
     * @param tokenId The token ID to query
     * @return amount The total amount in custody
     */
    function getTotalCustodyAmount(uint256 tokenId) external view returns (uint256 amount) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.tokenCustodyAmount[tokenId];
    }

    /**
     * @notice Check if a token is in custody by any custodian
     */
    function isInCustody(uint256 tokenId) external view returns (bool) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.tokenCustodyAmount[tokenId] > 0;
    }

    // ============================================================================
    // OWNER MINTING (from AuraAsset.mintBatch)
    // ============================================================================

    /**
     * @notice Batch mint tokens (owner only)
     * @dev C-02: Accepts optional nodeHash to attribute sellable amounts.
     *      Pass bytes32(0) to mint without node attribution.
     * @param to Recipient address
     * @param ids Token IDs to mint
     * @param amounts Amounts per token ID
     * @param nodeHash Node to attribute sellable amounts to (bytes32(0) = none)
     * @param data Additional data for receiver
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes32 nodeHash,
        bytes memory data
    ) external onlyOwner {
        _mintBatch(to, ids, amounts, data);
        if (nodeHash != bytes32(0)) {
            DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
            for (uint256 i = 0; i < ids.length; i++) {
                _creditOwnerNodeSellable(s, to, ids[i], nodeHash, amounts[i]);
            }
        }
    }

    // ============================================================================
    // ASSET REGISTRY (from AuraAsset.sol)
    // ============================================================================

    /**
     * @notice Add a supported asset definition (from AuraAsset.addSupportedAsset)
     */
    function addSupportedAsset(DiamondStorage.AssetDefinition memory asset) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        s.nameToSupportedAssetIndex[asset.name] = s.supportedAssetNames.length;
        s.nameToSupportedAssets[asset.name] = asset;
        bytes32 hash = keccak256(abi.encode(asset));
        s.hashToClass[hash] = asset.assetClass;
        s.supportedAssetNames.push(asset.name);
        s.ipfsID.push(hash);
    }

    /**
     * @notice Remove a supported asset (L-05: swap-and-pop instead of tombstone)
     */
    function removeSupportedAsset(DiamondStorage.AssetDefinition memory asset) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        uint256 i = s.nameToSupportedAssetIndex[asset.name];
        require(i < s.supportedAssetNames.length, "OOB");
        uint256 lastIdx = s.supportedAssetNames.length - 1;
        if (i != lastIdx) {
            string memory lastAsset = s.supportedAssetNames[lastIdx];
            s.supportedAssetNames[i] = lastAsset;
            s.nameToSupportedAssetIndex[lastAsset] = i;
        }
        s.supportedAssetNames.pop();
        delete s.nameToSupportedAssets[asset.name];
        delete s.nameToSupportedAssetIndex[asset.name];
    }

    // ============================================================================
    // CLASS REGISTRY (from AuraAsset.sol)
    // ============================================================================

    /**
     * @notice Add a supported class (from AuraAsset.addSupportedClass)
     */
    function addSupportedClass(string memory className) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        require(bytes(className).length != 0, "Empty class name");
        if (bytes(s.nameToSupportedClass[className]).length != 0) revert ClassAlreadyExists();

        s.nameToSupportedClassIndex[className] = s.supportedClassNames.length;
        s.nameToSupportedClass[className] = className;
        s.supportedClassNames.push(className);
        s.isClassActive[keccak256(abi.encode(className))] = true;

        emit SupportedClassAdded(keccak256(abi.encode(className)), className);
    }

    /**
     * @notice Remove a supported class (L-05: swap-and-pop instead of tombstone)
     */
    function removeSupportedClass(string memory className) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        uint256 i = s.nameToSupportedClassIndex[className];
        require(i < s.supportedClassNames.length, "OOB");
        uint256 lastIdx = s.supportedClassNames.length - 1;
        if (i != lastIdx) {
            string memory lastClass = s.supportedClassNames[lastIdx];
            s.supportedClassNames[i] = lastClass;
            s.nameToSupportedClassIndex[lastClass] = i;
        }
        s.supportedClassNames.pop();
        delete s.nameToSupportedClass[className];
        delete s.nameToSupportedClassIndex[className];
        s.isClassActive[keccak256(abi.encode(className))] = false;

        emit SupportedClassRemoved(keccak256(abi.encode(className)), className);
    }

    /**
     * @notice Check if a class is active
     */
    function isClassActive(string memory className) external view returns (bool) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.isClassActive[keccak256(abi.encode(className))];
    }

    /**
     * @notice Get all supported class names
     */
    function getSupportedClasses() external view returns (string[] memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.supportedClassNames;
    }

    /**
     * @notice Get all supported asset names
     */
    function getSupportedAssets() external view returns (string[] memory) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.supportedAssetNames;
    }

    // ============================================================================
    // LEGACY COMPATIBILITY - SIMPLE ASSET FUNCTIONS
    // ============================================================================

    /**
     * @notice Add an asset class (legacy compatibility)
     */
    function addAssetClass(string memory _class) external onlyOwner {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        require(!s.supportedClasses[_class], 'Class already exists');
        s.supportedClasses[_class] = true;
        s.classList.push(_class);
    }

    /**
     * @notice Add a simple asset (legacy compatibility)
     */
    function addAsset(
        string memory _name,
        string memory _assetClass,
        string[] memory _attributes
    ) external returns (bytes32 assetHash) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        require(s.supportedClasses[_assetClass], 'Class not supported');

        assetHash = keccak256(abi.encode(_name, _assetClass, s.totalAssets));

        s.assets[s.totalAssets] = DiamondStorage.Asset({
            name: _name,
            assetClass: _assetClass,
            attributes: _attributes,
            createdAt: block.timestamp,
            active: true
        });

        s.assetByHash[assetHash] = s.totalAssets;
        s.totalAssets++;

        return assetHash;
    }

    /**
     * @notice Get asset by ID (legacy compatibility)
     */
    function getAsset(uint256 _id)
        external
        view
        returns (
            string memory name,
            string memory assetClass,
            string[] memory attributes,
            uint256 createdAt,
            bool active
        )
    {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        DiamondStorage.Asset storage asset = s.assets[_id];
        return (asset.name, asset.assetClass, asset.attributes, asset.createdAt, asset.active);
    }

    /**
     * @notice Get asset ID by hash (legacy compatibility)
     */
    function getAssetByHash(bytes32 _assetHash) external view returns (uint256 id) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.assetByHash[_assetHash];
    }

    /**
     * @notice Get total assets count (legacy compatibility)
     */
    function getTotalAssets() external view returns (uint256) {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();
        return s.totalAssets;
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }

        uint256 fromBalance = s.erc1155Balances[id][from];
        if (fromBalance < amount) {
            revert ERC1155InsufficientBalance(from, fromBalance, amount, id);
        }

        unchecked {
            s.erc1155Balances[id][from] = fromBalance - amount;
        }
        s.erc1155Balances[id][to] += amount;
        _moveOwnerNodeSellable(s, from, to, id, amount);

        emit TransferSingle(msg.sender, from, to, id, amount);

        _doSafeTransferAcceptanceCheck(msg.sender, from, to, id, amount, data);
    }

    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }
        if (ids.length != amounts.length) {
            revert ERC1155InvalidArrayLength(ids.length, amounts.length);
        }

        uint256 idCount = ids.length;
        for (uint256 i = 0; i < idCount; ++i) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            uint256 fromBalance = s.erc1155Balances[id][from];
            if (fromBalance < amount) {
                revert ERC1155InsufficientBalance(from, fromBalance, amount, id);
            }
            unchecked {
                s.erc1155Balances[id][from] = fromBalance - amount;
            }
            s.erc1155Balances[id][to] += amount;
            _moveOwnerNodeSellable(s, from, to, id, amount);
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, from, to, ids, amounts, data);
    }

    // NOTE: In Diamond delegatecall context, msg.sender is the EOA, not
    // necessarily an EIP-1155 "approved operator". This is acceptable
    // because all mint/burn paths are access-controlled upstream.
    function _mint(address to, uint256 id, uint256 amount, bytes memory data) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }

        s.erc1155Balances[id][to] += amount;
        s.erc1155TotalSupply[id] += amount;
        if (!s.erc1155Exists[id]) {
            s.erc1155Exists[id] = true;
        }

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        _doSafeTransferAcceptanceCheck(msg.sender, address(0), to, id, amount, data);
    }

    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }
        if (ids.length != amounts.length) {
            revert ERC1155InvalidArrayLength(ids.length, amounts.length);
        }

        uint256 idCount = ids.length;
        for (uint256 i = 0; i < idCount; i++) {
            s.erc1155Balances[ids[i]][to] += amounts[i];
            s.erc1155TotalSupply[ids[i]] += amounts[i];
            if (!s.erc1155Exists[ids[i]]) {
                s.erc1155Exists[ids[i]] = true;
            }
        }

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);

        _doSafeBatchTransferAcceptanceCheck(msg.sender, address(0), to, ids, amounts, data);
    }

    function _burn(address from, uint256 id, uint256 amount) internal {
        DiamondStorage.AppStorage storage s = DiamondStorage.appStorage();

        uint256 fromBalance = s.erc1155Balances[id][from];
        if (fromBalance < amount) {
            revert ERC1155InsufficientBalance(from, fromBalance, amount, id);
        }

        unchecked {
            s.erc1155Balances[id][from] = fromBalance - amount;
            s.erc1155TotalSupply[id] -= amount;
        }

        emit TransferSingle(msg.sender, from, address(0), id, amount);
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

    function _moveOwnerNodeSellable(
        DiamondStorage.AppStorage storage s,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        if (amount == 0 || from == address(this) || to == address(this)) {
            return;
        }

        bytes32[] storage trackedNodes = s.ownerTokenSellableNodes[from][tokenId];
        uint256 remaining = amount;

        for (uint256 i = 0; i < trackedNodes.length && remaining > 0; i++) {
            bytes32 nodeHash = trackedNodes[i];
            uint256 nodeAmount = s.ownerNodeSellableAmounts[from][tokenId][nodeHash];
            if (nodeAmount == 0) continue;

            uint256 moved = nodeAmount > remaining ? remaining : nodeAmount;
            s.ownerNodeSellableAmounts[from][tokenId][nodeHash] -= moved;
            _creditOwnerNodeSellable(s, to, tokenId, nodeHash, moved);
            remaining -= moved;
        }

        if (remaining > 0) revert ExceedsNodeSellableAmount();
    }

    function _debitOwnerSellable(
        DiamondStorage.AppStorage storage s,
        address owner,
        uint256 tokenId,
        uint256 amount
    ) internal {
        bytes32[] storage trackedNodes = s.ownerTokenSellableNodes[owner][tokenId];
        uint256 remaining = amount;

        for (uint256 i = 0; i < trackedNodes.length && remaining > 0; i++) {
            bytes32 nodeHash = trackedNodes[i];
            uint256 nodeAmount = s.ownerNodeSellableAmounts[owner][tokenId][nodeHash];
            if (nodeAmount == 0) continue;

            uint256 debited = nodeAmount > remaining ? remaining : nodeAmount;
            s.ownerNodeSellableAmounts[owner][tokenId][nodeHash] -= debited;
            remaining -= debited;
        }

        if (remaining > 0) revert ExceedsNodeSellableAmount();
    }

    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert ERC1155InvalidReceiver(to);
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert ERC1155InvalidReceiver(to);
            }
        }
    }

    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert ERC1155InvalidReceiver(to);
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert ERC1155InvalidReceiver(to);
            }
        }
    }
}

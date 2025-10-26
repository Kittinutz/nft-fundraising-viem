// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

/**
 * @title DZNFT
 * @dev NFT contract for investment rounds with role-based access control
 */
contract DZNFT is ERC721, ERC721Burnable, Ownable, AccessControl, Pausable {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    
    uint256 private _nextTokenId;
    
    // Token URI management
    string private _baseTokenURI;
    mapping(uint256 => string) private _tokenURIs;
    
    struct InvestmentData {
        uint256 tokenId;
        uint256 roundId;
        uint256 tokenPrice;
        uint256 rewardPercentage;
        uint256 totalTokenOpenInvestment;
        uint256 purchaseTimestamp;
        uint256 closeDateInvestment;
        uint256 endDateInvestment;
        address originalBuyer;
        bool redeemed;
        bool rewardClaimed; // New: tracks if early reward was claimed
        bool transferLocked; // New: locks transfer even after redemption
        string metadata; // Additional metadata stamp
    }
    
    mapping(uint256 => InvestmentData) public investmentData;
    mapping(uint256 => bool) public tokenExists;
    
    event NFTMinted(
        uint256 indexed tokenId, 
        address indexed buyer, 
        uint256 indexed roundId, 
        uint256 tokenPrice,
        uint256 rewardPercentage
    );
    event NFTBurned(uint256 indexed tokenId, address indexed owner);
    event MetadataStamped(uint256 indexed tokenId, string metadata);
    event ExecutorRoleUpdated(address indexed account, bool granted);
    event RewardClaimed(uint256 indexed tokenId, address indexed claimer);
    event TransferLockUpdated(uint256 indexed tokenId, bool locked);
    event BaseURIUpdated(string newBaseURI);
    event TokenURIUpdated(uint256 indexed tokenId, string newTokenURI);
    
    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Caller is not an executor");
        _;
    }
    
    constructor() ERC721("DZ Investment NFT", "DZNFT") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _baseTokenURI = "https://api.dznft.com/metadata/";
    }
    

    /**
     * @dev Update executor role - only owner can do this
     */
    function updateExecutorRole(address account, bool grant) external onlyOwner {
        if (grant) {
            grantRole(EXECUTOR_ROLE, account);
        } else {
            revokeRole(EXECUTOR_ROLE, account);
        }
        emit ExecutorRoleUpdated(account, grant);
    }

    /**
     * @dev Check if an address has executor role
     */
    function isExecutor(address account) external view returns (bool) {
        return hasRole(EXECUTOR_ROLE, account);
    }

    /**
     * @dev Mint NFT with investment round data - only executor can call
     */
    function mintNFT(
        address to,
        uint256 roundId,
        uint256 tokenPrice,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 closeDateInvestment,
        uint256 endDateInvestment
    ) external onlyExecutor whenNotPaused returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(tokenPrice > 0, "Price must be greater than 0");
        require(rewardPercentage > 0 && rewardPercentage <= 10000, "Invalid reward percentage");
        require(totalTokenOpenInvestment > 0, "Total tokens must be greater than 0");
        require(closeDateInvestment > block.timestamp, "Close date must be in future");
        require(endDateInvestment > closeDateInvestment, "End date must be after close date");
        
        uint256 tokenId = _nextTokenId++;
        
        investmentData[tokenId] = InvestmentData({
            tokenId: tokenId,
            roundId: roundId,
            tokenPrice: tokenPrice,
            rewardPercentage: rewardPercentage,
            totalTokenOpenInvestment: totalTokenOpenInvestment,
            purchaseTimestamp: block.timestamp,
            closeDateInvestment: closeDateInvestment,
            endDateInvestment: endDateInvestment,
            originalBuyer: to,
            redeemed: false,
            rewardClaimed: false,
            transferLocked: false,
            metadata: ""
        });
        
        tokenExists[tokenId] = true;
        _safeMint(to, tokenId);
        
        emit NFTMinted(tokenId, to, roundId, tokenPrice, rewardPercentage);
        return tokenId;
    }

    /**
     * @dev Batch mint NFTs for gas optimization
     * @param to Address to mint NFTs to
     * @param count Number of NFTs to mint
     * @param roundId Investment round ID
     * @param tokenPrice Price per token
     * @param rewardPercentage Reward percentage
     * @param totalTokenOpenInvestment Total tokens per NFT
     * @param closeDateInvestment Close date for investment
     * @param endDateInvestment End date for investment
     * @return tokenIds Array of minted token IDs
     */
    function batchMintNFT(
        address to,
        uint256 count,
        uint256 roundId,
        uint256 tokenPrice,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 closeDateInvestment,
        uint256 endDateInvestment
    ) external onlyExecutor whenNotPaused returns (uint256[] memory tokenIds) {
        require(to != address(0), "Invalid recipient address");
        require(count > 0 && count <= 80, "Invalid count (1-80)");
        require(tokenPrice > 0, "Price must be greater than 0");
        require(rewardPercentage > 0, "Invalid reward percentage");
        require(totalTokenOpenInvestment > 0, "Total tokens must be greater than 0");
        require(closeDateInvestment > block.timestamp, "Close date must be in future");
        require(endDateInvestment > closeDateInvestment, "End date must be after close date");
        
        tokenIds = new uint256[](count);
        uint256 purchaseTime = block.timestamp; // Cache timestamp for gas optimization
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            tokenIds[i] = tokenId;
            
            investmentData[tokenId] = InvestmentData({
                tokenId: tokenId,
                roundId: roundId,
                tokenPrice: tokenPrice,
                rewardPercentage: rewardPercentage,
                totalTokenOpenInvestment: totalTokenOpenInvestment,
                purchaseTimestamp: purchaseTime,
                closeDateInvestment: closeDateInvestment,
                endDateInvestment: endDateInvestment,
                originalBuyer: to,
                redeemed: false,
                rewardClaimed: false,
                transferLocked: false,
                metadata: ""
            });
            
            tokenExists[tokenId] = true;
            _safeMint(to, tokenId);
            
            emit NFTMinted(tokenId, to, roundId, tokenPrice, rewardPercentage);
        }
        
        return tokenIds;
    }
    
    /**
     * @dev Burn NFT - only token owner can burn
     */
    function burn(uint256 tokenId) public override {
        require(tokenExists[tokenId], "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || getApproved(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender),
            "Not owner nor approved"
        );
        
        address owner = ownerOf(tokenId);
        tokenExists[tokenId] = false;
        delete investmentData[tokenId];
        delete _tokenURIs[tokenId]; // Clear the token URI
        
        super.burn(tokenId);
        emit NFTBurned(tokenId, owner);
    }
    
    /**
     * @dev Stamp metadata on NFT - only executor can call
     */
    function stampMetadata(uint256 tokenId, string calldata metadata) external onlyExecutor {
        require(tokenExists[tokenId], "Token does not exist");
        investmentData[tokenId].metadata = metadata;
        emit MetadataStamped(tokenId, metadata);
    }
    
    /**
     * @dev Mark NFT as redeemed - only executor can call
     */
    function markAsRedeemed(uint256 tokenId) external onlyExecutor {
        require(tokenExists[tokenId], "Token does not exist");
        investmentData[tokenId].redeemed = true;
    }

    /**
     * @dev Mark NFT reward as claimed and lock transfer - only executor can call
     */
    function markRewardClaimed(uint256 tokenId) external onlyExecutor {
        require(tokenExists[tokenId], "Token does not exist");
        require(!investmentData[tokenId].rewardClaimed, "Reward already claimed");
        
        investmentData[tokenId].rewardClaimed = true;
        investmentData[tokenId].transferLocked = true;
        
        emit RewardClaimed(tokenId, ownerOf(tokenId));
    }

    /**
     * @dev Check if early reward can be claimed (first 6 months)
     */
    function canClaimEarlyReward(uint256 tokenId) external view returns (bool) {
        require(tokenExists[tokenId], "Token does not exist");
        InvestmentData memory data = investmentData[tokenId];
        
        // Can claim if 6 months have passed since purchase and reward not yet claimed
        return (block.timestamp >= data.purchaseTimestamp + 180 days) && 
               !data.rewardClaimed && 
               !data.redeemed;
    }

    /**
     * @dev Check if full redemption is available (after 1 year)
     */
    function canFullyRedeem(uint256 tokenId) external view returns (bool) {
        require(tokenExists[tokenId], "Token does not exist");
        InvestmentData memory data = investmentData[tokenId];
        
        // Can fully redeem after 1 year and not yet redeemed
        return (block.timestamp >= data.purchaseTimestamp + 365 days) && 
               !data.redeemed;
    }

    /**
     * @dev Lock transfer - only executor can call
     */
    function lockTransfer(uint256 tokenId) external onlyExecutor {
        require(tokenExists[tokenId], "Token does not exist");
        
        investmentData[tokenId].transferLocked = true;
        emit TransferLockUpdated(tokenId, true);
    }

    /**
     * @dev Unlock transfer after full redemption - only executor can call
     */
    function unlockTransfer(uint256 tokenId) external onlyExecutor {
        require(tokenExists[tokenId], "Token does not exist");
        require(investmentData[tokenId].redeemed, "Must be redeemed first");
        
        investmentData[tokenId].transferLocked = false;
        emit TransferLockUpdated(tokenId, false);
    }
    
    /**
     * @dev Check if token transfer is locked
     */
    function isTransferLocked(uint256 tokenId) external view returns (bool) {
        require(tokenExists[tokenId], "Token does not exist");
        return investmentData[tokenId].transferLocked;
    }

    /**
     * @dev Get investment data for a token
     */
    function getInvestmentData(uint256 tokenId) external view returns (InvestmentData memory) {
        require(tokenExists[tokenId], "Token does not exist");
        return investmentData[tokenId];
    }
    
    /**
     * @dev Check if investment round is still open
     */
    function isInvestmentOpen(uint256 tokenId) external view returns (bool) {
        require(tokenExists[tokenId], "Token does not exist");
        return block.timestamp <= investmentData[tokenId].closeDateInvestment;
    }
    
    /**
     * @dev Check if investment has matured
     */
    function isInvestmentMatured(uint256 tokenId) external view returns (bool) {
        require(tokenExists[tokenId], "Token does not exist");
        return block.timestamp >= investmentData[tokenId].endDateInvestment;
    }
    
    /**
     * @dev Pause contract - only owner
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract - only owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Set the base URI for all tokens - only owner
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }
    
    /**
     * @dev Set individual token URI - only owner or executor
     */
    function setTokenURI(uint256 tokenId, string calldata newTokenURI) external {
        require(
            owner() == msg.sender || hasRole(EXECUTOR_ROLE, msg.sender),
            "Caller is not owner nor executor"
        );
        require(tokenExists[tokenId], "Token does not exist");
        _tokenURIs[tokenId] = newTokenURI;
        emit TokenURIUpdated(tokenId, newTokenURI);
    }
    
    /**
     * @dev Get the base URI
     */
    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }
    
    /**
     * @dev Override tokenURI to return custom URI or base URI + tokenId
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(tokenExists[tokenId], "Token does not exist");
        
        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseTokenURI;
        
        // If there is a specific token URI, return it
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }
        
        // If there is a base URI, concatenate the tokenId to the base URI
        if (bytes(base).length > 0) {
            return string(abi.encodePacked(base, _toString(tokenId), ".json"));
        }
        
        // If no base URI, return empty string
        return "";
    }
    
    /**
     * @dev Internal function to convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721, AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Override to prevent transfer when paused or locked
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override
        returns (address)
    {
        require(!paused(), "Token transfer while paused");
        
        // Check if transfer is locked (only if not minting or burning)
        if (to != address(0) && auth != address(0)) {
            require(!investmentData[tokenId].transferLocked, "Token transfer locked");
        }
        
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Batch check ownership for gas optimization
     * @param tokenIds Array of token IDs to check
     * @param user Address to check ownership for
     * @return ownedTokens Array of booleans indicating ownership
     */
    function batchCheckOwnership(uint256[] memory tokenIds, address user) 
        external 
        view 
        returns (bool[] memory ownedTokens) 
    {
        ownedTokens = new bool[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ownedTokens[i] = (ownerOf(tokenIds[i]) == user);
        }
        return ownedTokens;
    }

    /**
     * @dev Batch get investment data for gas optimization
     * @param tokenIds Array of token IDs to get data for
     * @return investments Array of investment data
     */
    function batchGetInvestmentData(uint256[] memory tokenIds) 
        external 
        view 
        returns (InvestmentData[] memory investments) 
    {
        investments = new InvestmentData[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            investments[i] = investmentData[tokenIds[i]];
        }
        return investments;
    }

    function transferOwner(address newOwner) public onlyOwner {
        transferOwnership(newOwner);
    }

    /**
     * @dev Get all NFT tokens owned by a wallet address with pagination
     * @param walletAddress The address to get NFT tokens for
     * @param offset Starting position (0-based)
     * @param limit Maximum number of tokens to return (recommended: 10-50)
     * @return tokenIds Array of token IDs owned by the address
     * @return investmentDetails Array of investment data for each token
     * @return totalTokens Total number of tokens owned by the address
     * @return totalPages Total number of pages available
     * @return currentPage Current page number (1-based)
     * @return hasMore Whether there are more tokens available
     */
    function getWalletNFTsPaginated(
        address walletAddress,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (
            uint256[] memory tokenIds,
            InvestmentData[] memory investmentDetails,
            uint256 totalTokens,
            uint256 totalPages,
            uint256 currentPage,
            bool hasMore
        )
    {
        require(walletAddress != address(0), "Invalid wallet address");
        require(limit > 0 && limit <= 100, "Limit must be between 1 and 100");
        
        // First, get all token IDs owned by the wallet
        uint256[] memory allUserTokens = _getAllTokensOwnedBy(walletAddress);
        totalTokens = allUserTokens.length;
        
        require(offset < totalTokens || totalTokens == 0, "Offset exceeds total tokens");
        
        // Calculate pagination info
        totalPages = totalTokens > 0 ? (totalTokens + limit - 1) / limit : 0;
        currentPage = totalTokens > 0 ? (offset / limit) + 1 : 0;
        
        // Calculate actual number of tokens to return
        uint256 remainingTokens = totalTokens > offset ? totalTokens - offset : 0;
        uint256 actualLimit = remainingTokens > limit ? limit : remainingTokens;
        hasMore = offset + actualLimit < totalTokens;
        
        if (actualLimit == 0) {
            return (
                new uint256[](0),
                new InvestmentData[](0),
                totalTokens,
                totalPages,
                currentPage,
                hasMore
            );
        }
        
        // Initialize arrays with actual size needed
        tokenIds = new uint256[](actualLimit);
        investmentDetails = new InvestmentData[](actualLimit);
        
        // Populate arrays with paginated data
        for (uint256 i = 0; i < actualLimit; i++) {
            uint256 tokenId = allUserTokens[offset + i];
            tokenIds[i] = tokenId;
            investmentDetails[i] = investmentData[tokenId];
        }
        
        return (
            tokenIds,
            investmentDetails,
            totalTokens,
            totalPages,
            currentPage,
            hasMore
        );
    }

    /**
     * @dev Internal function to get all token IDs owned by a specific address
     * @param owner The address to get tokens for
     * @return ownedTokens Array of token IDs owned by the address
     */
    function _getAllTokensOwnedBy(address owner) 
        internal 
        view 
        returns (uint256[] memory ownedTokens) 
    {
        // First pass: count owned tokens
        uint256 ownedCount = 0;
        for (uint256 tokenId = 0; tokenId < _nextTokenId; tokenId++) {
            if (tokenExists[tokenId] && ownerOf(tokenId) == owner) {
                ownedCount++;
            }
        }
        
        // Second pass: collect token IDs
        ownedTokens = new uint256[](ownedCount);
        uint256 index = 0;
        for (uint256 tokenId = 0; tokenId < _nextTokenId; tokenId++) {
            if (tokenExists[tokenId] && ownerOf(tokenId) == owner) {
                ownedTokens[index] = tokenId;
                index++;
            }
        }
        
        return ownedTokens;
    }

    /**
     * @dev Get wallet NFT summary (non-paginated) for quick overview
     * @param walletAddress The address to get summary for
     * @return totalNFTs Total number of NFTs owned
     * @return activeInvestments Number of NFTs not yet redeemed
     * @return redeemedInvestments Number of NFTs already redeemed
     * @return claimedRewards Number of NFTs with early rewards claimed
     * @return totalInvestedValue Total value invested across all NFTs
     * @return totalExpectedRewards Total expected rewards across all NFTs
     * @return claimableAmount Amount that can be claimed right now
     */
    function getWalletNFTSummary(address walletAddress)
        external
        view
        returns (
            uint256 totalNFTs,
            uint256 activeInvestments,
            uint256 redeemedInvestments,
            uint256 claimedRewards,
            uint256 totalInvestedValue,
            uint256 totalExpectedRewards,
            uint256 claimableAmount
        )
    {
        require(walletAddress != address(0), "Invalid wallet address");
        
        uint256[] memory userTokens = _getAllTokensOwnedBy(walletAddress);
        totalNFTs = userTokens.length;
        
        if (totalNFTs == 0) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
        
        uint256 currentTime = block.timestamp;
        
        for (uint256 i = 0; i < userTokens.length; i++) {
            InvestmentData memory data = investmentData[userTokens[i]];
            uint256 principal = data.totalTokenOpenInvestment * data.tokenPrice;
            uint256 reward = (principal * data.rewardPercentage) / 10000;
            
            totalInvestedValue += principal;
            totalExpectedRewards += reward;
            
            if (data.redeemed) {
                redeemedInvestments++;
            } else {
                activeInvestments++;
            }
            
            if (data.rewardClaimed) {
                claimedRewards++;
            }
            
            // Calculate claimable amount
            if (!data.redeemed) {
                uint256 timeSincePurchase = currentTime - data.purchaseTimestamp;
                
                if (timeSincePurchase >= 180 days) {
                    if (timeSincePurchase >= 365 days) {
                        // Full redemption available
                        if (data.rewardClaimed) {
                            claimableAmount += principal + (reward / 2);
                        } else {
                            claimableAmount += principal + reward;
                        }
                    } else if (!data.rewardClaimed) {
                        // Early reward available
                        claimableAmount += (reward / 2);
                    }
                }
            }
        }
        
        return (
            totalNFTs,
            activeInvestments,
            redeemedInvestments,
            claimedRewards,
            totalInvestedValue,
            totalExpectedRewards,
            claimableAmount
        );
    }

    /**
     * @dev Get all token IDs owned by a wallet (convenience function, non-paginated)
     * @param walletAddress The address to get token IDs for
     * @return tokenIds Array of all token IDs owned by the address
     */
    function getWalletTokenIds(address walletAddress) 
        external 
        view 
        returns (uint256[] memory tokenIds) 
    {
        require(walletAddress != address(0), "Invalid wallet address");
        return _getAllTokensOwnedBy(walletAddress);
    }
}
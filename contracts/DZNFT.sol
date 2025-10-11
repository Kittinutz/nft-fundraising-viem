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
        uint256 priceUSDTperToken;
        uint256 rewardPercentage;
        uint256 totalTokenOpenInvestment;
        uint256 purchaseTimestamp;
        uint256 closeDateInvestment;
        uint256 endDateInvestment;
        address originalBuyer;
        bool redeemed;
        string metadata; // Additional metadata stamp
    }
    
    mapping(uint256 => InvestmentData) public investmentData;
    mapping(uint256 => bool) public tokenExists;
    
    event NFTMinted(
        uint256 indexed tokenId, 
        address indexed buyer, 
        uint256 indexed roundId, 
        uint256 priceUSDTperToken,
        uint256 rewardPercentage
    );
    event NFTBurned(uint256 indexed tokenId, address indexed owner);
    event MetadataStamped(uint256 indexed tokenId, string metadata);
    event ExecutorRoleUpdated(address indexed account, bool granted);
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
     * @dev Mint NFT with investment round data - only executor can call
     */
    function mintNFT(
        address to,
        uint256 roundId,
        uint256 priceUSDTperToken,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 closeDateInvestment,
        uint256 endDateInvestment
    ) external onlyExecutor whenNotPaused returns (uint256) {
        require(to != address(0), "Invalid recipient address");
        require(priceUSDTperToken > 0, "Price must be greater than 0");
        require(rewardPercentage > 0 && rewardPercentage <= 10000, "Invalid reward percentage");
        require(totalTokenOpenInvestment > 0, "Total tokens must be greater than 0");
        require(closeDateInvestment > block.timestamp, "Close date must be in future");
        require(endDateInvestment > closeDateInvestment, "End date must be after close date");
        
        uint256 tokenId = _nextTokenId++;
        
        investmentData[tokenId] = InvestmentData({
            tokenId: tokenId,
            roundId: roundId,
            priceUSDTperToken: priceUSDTperToken,
            rewardPercentage: rewardPercentage,
            totalTokenOpenInvestment: totalTokenOpenInvestment,
            purchaseTimestamp: block.timestamp,
            closeDateInvestment: closeDateInvestment,
            endDateInvestment: endDateInvestment,
            originalBuyer: to,
            redeemed: false,
            metadata: ""
        });
        
        tokenExists[tokenId] = true;
        _safeMint(to, tokenId);
        
        emit NFTMinted(tokenId, to, roundId, priceUSDTperToken, rewardPercentage);
        return tokenId;
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
     * @dev Override to prevent transfer when paused
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override
        returns (address)
    {
        require(!paused(), "Token transfer while paused");
        return super._update(to, tokenId, auth);
    }
}
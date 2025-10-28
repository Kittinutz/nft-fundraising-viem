// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DZNFT.sol";
/**
 * @title FundRaisingCore
 * @dev Core functionality for investment rounds and NFT minting (reduced size)
 */
contract FundRaisingCore is Ownable, ReentrancyGuard, Pausable {
    DZNFT public immutable dzNFT;
    IERC20 public usdtToken;
    
    // Use explicit enum instead of interface
    enum Status { OPEN, CLOSED, COMPLETED, WITHDRAW_FUND, DIVIDEND_PAID }
    
    // Use explicit struct instead of interface
    struct InvestmentRound {
        uint256 roundId;
        string roundName;
        uint256 tokenPrice;
        uint256 rewardPercentage;
        uint256 totalTokenOpenInvestment;
        uint256 tokensSold;
        uint256 closeDateInvestment;
        uint256 endDateInvestment;
        bool isActive;
        bool exists;
        uint256 createdAt;
        Status status;
    }
    
    // Constants
    uint256 public constant USDT_DECIMALS = 18;
    uint256 public constant MAX_TOKENS_PER_INVESTMENT = 50;
    
    // Storage
    mapping(uint256 => InvestmentRound) public investmentRounds;
    mapping(uint256 => uint256[]) public roundTokenIds;
    mapping(address => uint256[]) public userInvestments;
    mapping(uint256 => mapping(address => uint256[])) public userNFTsInRound;
    mapping(uint256 => uint256) public roundLedger;
    mapping(address => uint256[]) public investorRounds;
    mapping(uint256 => uint256) public roundRewardPool;
    mapping(address => mapping(uint256 => uint256)) public userClaimedRewards;
    
    uint256 public _nextRoundId;
    uint256 public totalRoundsCreated;
    uint256 public totalUSDTRaised;
    
    // Events
    event InvestmentRoundCreated(uint256 indexed roundId, string roundName, uint256 tokenPrice);
    event Investment(address indexed investor, uint256 indexed roundId, uint256 tokenCount, uint256 usdtAmount);
    event RewardAdded(uint256 indexed roundId, uint256 amount, uint256 totalRewardPool);
    event RoundStatusChanged(uint256 indexed roundId, bool isActive);
    event USDTTokenUpdated(address indexed oldToken, address indexed newToken);
    
    // Modifiers
    modifier roundExists(uint256 roundId) {
        require(investmentRounds[roundId].exists, "Round does not exist");
        _;
    }
    
    modifier roundActive(uint256 roundId) {
        require(investmentRounds[roundId].isActive, "Round is not active");
        _;
    }
    
    modifier investmentOpen(uint256 roundId) {
        require(
            block.timestamp <= investmentRounds[roundId].closeDateInvestment,
            "Investment period has closed"
        );
        _;
    }
    
    constructor(address _dzNFT, address _usdtToken) Ownable(msg.sender) {
        require(_dzNFT != address(0), "Invalid DZNFT address");
        require(_usdtToken != address(0), "Invalid USDT address");
        
        dzNFT = DZNFT(_dzNFT);
        usdtToken = IERC20(_usdtToken);
    }
    
    /**
     * @dev Create a new investment round
     */
    function createInvestmentRound(
        string memory roundName,
        uint256 tokenPrice,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 closeDateInvestment,
        uint256 endDateInvestment
    ) external onlyOwner {
        require(bytes(roundName).length > 0, "Round name cannot be empty");
        require(tokenPrice > 0, "Token price must be greater than 0");
        require(totalTokenOpenInvestment > 0, "Total token open investment must be greater than 0");
        require(rewardPercentage > 0 && rewardPercentage <= 10000, "Invalid reward percentage (0-10000)");
        require(closeDateInvestment > block.timestamp, "Close date must be in future");
        require(endDateInvestment > closeDateInvestment, "End date must be after close date");
        
        uint256 roundId = _nextRoundId++;
        
        investmentRounds[roundId] = InvestmentRound({
            roundId: roundId,
            roundName: roundName,
            tokenPrice: tokenPrice,
            rewardPercentage: rewardPercentage,
            totalTokenOpenInvestment: totalTokenOpenInvestment,
            tokensSold: 0,
            closeDateInvestment: closeDateInvestment,
            endDateInvestment: endDateInvestment,
            isActive: true,
            exists: true,
            createdAt: block.timestamp,
            status: Status.OPEN
        });
        
        totalRoundsCreated++;
        
        emit InvestmentRoundCreated(roundId, roundName, tokenPrice);
    }
    
    /**
     * @dev Invest in a round by purchasing tokens
     */
    function investInRound(uint256 roundId, uint256 tokenAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        roundExists(roundId) 
        roundActive(roundId) 
        investmentOpen(roundId) 
    {
        require(tokenAmount > 0 && tokenAmount <= MAX_TOKENS_PER_INVESTMENT, "Invalid token amount");
        
        InvestmentRound storage round = investmentRounds[roundId];
        uint256 usdtAmount = tokenAmount * round.tokenPrice;
        
        require(
            round.tokensSold + tokenAmount <= round.totalTokenOpenInvestment,
            "Not enough tokens available in this round"
        );
        
        require(
            usdtToken.transferFrom(msg.sender, address(this), usdtAmount),
            "USDT transfer failed"
        );
        // Mint NFTs
        uint256[] memory tokenIds;
        if (tokenAmount > 1) {
            tokenIds = dzNFT.batchMintNFT(
                msg.sender,
                tokenAmount,
                roundId,
                round.tokenPrice,
                round.rewardPercentage,
                1,
                round.closeDateInvestment,
                round.endDateInvestment
            );
        } else {
            tokenIds = new uint256[](1);
            tokenIds[0] = dzNFT.mintNFT(
                msg.sender,
                roundId,
                round.tokenPrice,
                round.rewardPercentage,
                1,
                round.closeDateInvestment,
                round.endDateInvestment
            );
        }
        
        // Update storage
        uint256[] storage roundTokens = roundTokenIds[roundId];
        uint256[] storage userTokens = userInvestments[msg.sender];
        uint256[] storage userRoundTokens = userNFTsInRound[roundId][msg.sender];
        
        bool isFirstInvestmentInRound = userRoundTokens.length == 0;
        
        for(uint256 i = 0; i < tokenAmount; i++){
            roundTokens.push(tokenIds[i]);
            userTokens.push(tokenIds[i]);
            userRoundTokens.push(tokenIds[i]);
        }
        
        if (isFirstInvestmentInRound) {
            investorRounds[msg.sender].push(roundId);
        }
        
        // Update round data
        round.tokensSold += tokenAmount;
        roundLedger[roundId] += usdtAmount;
        totalUSDTRaised += usdtAmount;
        
        emit Investment(msg.sender, roundId, tokenAmount, usdtAmount);
    }
    
    /**
     * @dev Add reward to a specific round
     */
    function addRewardToRound(uint256 roundId, uint256 amount) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        require(amount > 0, "Reward amount must be greater than 0");
        require(
            usdtToken.transferFrom(msg.sender, address(this), amount * 10 ** USDT_DECIMALS),
            "USDT transfer failed"
        );
        
        roundRewardPool[roundId] += amount * 10 ** USDT_DECIMALS;
        roundLedger[roundId] += amount * 10 ** USDT_DECIMALS;
        
        emit RewardAdded(roundId, amount, roundRewardPool[roundId]);
    }
    
    /**
     * @dev Withdraw fund from a specific round
     */
    function withdrawFund(uint256 roundId) 
        external 
        onlyOwner 
        nonReentrant
        roundExists(roundId) 
    {
        uint256 amount = roundLedger[roundId];
        roundLedger[roundId] = 0;
        
        require(
            usdtToken.transfer(owner(), amount),
            "USDT transfer failed"
        );
        investmentRounds[roundId].status = Status.WITHDRAW_FUND;
    }
    
    /**
     * @dev Set round active status
     */
    function setRoundActive(uint256 roundId, bool active) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        investmentRounds[roundId].isActive = active;
        emit RoundStatusChanged(roundId, active);
    }
    
    /**
     * @dev Update USDT token address
     */
    function setUSDTToken(address newUSDTToken) external onlyOwner {
        require(newUSDTToken != address(0), "Invalid USDT token address");
        address oldToken = address(usdtToken);
        usdtToken = IERC20(newUSDTToken);
        emit USDTTokenUpdated(oldToken, newUSDTToken);
    }
    
    /**
     * @dev Update user claimed rewards (called by claims contract)
     */
    function updateUserClaimedRewards(address user, uint256 roundId, uint256 amount) 
        external 
    {
        // Only allow claims contract to call this
        userClaimedRewards[user][roundId] += amount;
    }
    
    // Getter functions for arrays
    function getRoundTokenIds(uint256 roundId) external view returns (uint256[] memory) {
        return roundTokenIds[roundId];
    }
    
    function getRoundTokenCount(uint256 roundId) external view returns (uint256) {
        return roundTokenIds[roundId].length;
    }
    
    function getUserInvestments(address user) external view returns (uint256[] memory) {
        return userInvestments[user];
    }
    
    function getUserNFTsInRound(uint256 roundId, address user) external view returns (uint256[] memory) {
        return userNFTsInRound[roundId][user];
    }
    
    function getInvestorRounds(address investor) external view returns (uint256[] memory) {
        return investorRounds[investor];
    }
    
    function getUSDTTokenAddress() external view returns (address) {
        return address(usdtToken);
    }
    
    function getContractUSDTBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }
    
    /**
     * @dev Transfer rewards from core contract to claimant via claims contract
     * @param roundId The round ID
     * @param amount The amount to transfer
     */
    function transferRewardToClaims(uint256 roundId, uint256 amount) external {
        require(msg.sender != address(0), "Invalid sender");
        require(amount > 0, "Invalid amount");
        require(roundRewardPool[roundId] >= amount, "Insufficient reward pool");
        
        // Deduct from round reward pool
        roundRewardPool[roundId] -= amount;
        
        // Approve claims contract to transfer on behalf of core
        // This allows the claims contract to call transferFrom
        require(
            usdtToken.approve(msg.sender, amount),
            "Approve failed"
        );
    }
}
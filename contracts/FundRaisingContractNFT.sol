// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DZNFT.sol";

/**
 * @title FundRaisingContractNFT
 * @dev Smart contract for creating and managing investment rounds with NFT representation
 */
contract FundRaisingContractNFT is Ownable, ReentrancyGuard, Pausable {
    DZNFT public immutable dzNFT;
    IERC20 public usdtToken;
    
    // Decimal constants
    uint256 public constant USDT_DECIMALS = 18;   // USDT uses 18 decimals in this contract
    
    // Gas optimization constants
    uint256 public constant MAX_TOKENS_PER_INVESTMENT = 100;  // Prevent DoS attacks
    uint256 public constant MAX_BATCH_CLAIM = 50;             // Limit batch operations
    
    enum Status { OPEN, CLOSED, COMPLETED , WITHDRAW_FUND, DIVIDEND_PAID }
    
    // IMPORTANT: Price format expectations
    // tokenPrice should be provided in 18 decimal format
    // Example: For $10 USDT per token, set tokenPrice = 10 * 10^18 = 10000000000000000000
    
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
    
    mapping(uint256 => InvestmentRound) public investmentRounds;
    mapping(uint256 => uint256[]) public roundTokenIds; // roundId => tokenIds array
    mapping(address => uint256[]) public userInvestments; // user => tokenIds array
    mapping(uint256 => mapping(address => uint256[])) public userNFTsInRound; // roundId => user => tokenIds array
    mapping(uint256 => uint256) public roundLedger; // roundId => USDT balance for each round
    
    // New Reward Distribution Mappings
    mapping(uint256 => uint256) public roundRewardPool; // roundId => total reward pool amount
    mapping(uint256 => uint256) public roundRewardPerNFT; // roundId => reward amount per NFT in this round
    mapping(address => mapping(uint256 => uint256)) public userClaimedRewards; // user => roundId => claimed amount
    mapping(address => uint256) public totalUserRewardsClaimed; // user => total rewards claimed across all rounds
    mapping(uint256 => uint256[]) public rewardClaimHistory; // roundId => array of claim amounts (for audit trail)
    mapping(address => uint256[]) public userRewardClaimHistory; // user => array of claim transaction amounts
    uint256 public _nextRoundId;
    uint256 public totalRoundsCreated;
    uint256 public totalUSDTRaised;
   
    
    
    event RoundStatusChanged(uint256 indexed roundId, bool isActive);
    event EarlyRewardClaimed(uint256 indexed tokenId, address indexed investor, uint256 rewardAmount);
    event USDTTokenUpdated(address indexed oldToken, address indexed newToken);
    event RoundFunded(uint256 indexed roundId, uint256 amount);
    
    // New Reward Distribution Events
    event RewardAdded(uint256 indexed roundId, uint256 amount, uint256 totalPoolAmount);
    
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
    ) external onlyOwner returns (uint256) {
        require(bytes(roundName).length > 0, "Round name cannot be empty");
        require(tokenPrice > 0, "Price must be greater than 0");
        require(rewardPercentage > 0 && rewardPercentage <= 10000, "Invalid reward percentage (0-10000)");
        require(totalTokenOpenInvestment > 0, "Total tokens must be greater than 0");
        require(closeDateInvestment > block.timestamp, "Close date must be in future");
        require(endDateInvestment > closeDateInvestment, "End date must be after close date");
        
        uint256 roundId = _nextRoundId++;
        investmentRounds[roundId] = InvestmentRound({
            roundId: roundId,
            roundName: roundName,
            tokenPrice: tokenPrice * 10 ** USDT_DECIMALS,
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
        
        
        return roundId;
    }
    
    /**
     * @dev Activate or deactivate an investment round
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
     * @dev Update USDT token address - only owner can do this
     */
    function setUSDTToken(address newUSDTToken) external onlyOwner {
        require(newUSDTToken != address(0), "Invalid USDT token address");
        require(newUSDTToken != address(usdtToken), "Same USDT token address");
        
        address oldToken = address(usdtToken);
        usdtToken = IERC20(newUSDTToken);
        
        emit USDTTokenUpdated(oldToken, newUSDTToken);
    }
    
    /**
     * @dev Get current USDT token address
     */
    function getUSDTTokenAddress() external view returns (address) {
        return address(usdtToken);
    }
    
    /**
     * @dev Invest in a specific round with token amount
     */
    function investInRound(uint256 roundId, uint256 tokenAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        roundExists(roundId) 
        roundActive(roundId) 
        investmentOpen(roundId) 
        returns (uint256) 
    {
        require(block.timestamp < investmentRounds[roundId].closeDateInvestment, "Investment period has closed");
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(tokenAmount <= MAX_TOKENS_PER_INVESTMENT, "Token amount exceeds maximum allowed per transaction");
        
        InvestmentRound storage round = investmentRounds[roundId];
        
        uint256 usdtAmount = (tokenAmount * round.tokenPrice);
        require(usdtAmount > 0, "Token amount too small");
        
        // Check if enough tokens available
        require(
            round.tokensSold + tokenAmount <= round.totalTokenOpenInvestment,
            "Not enough tokens available in this round"
        );
        
        // Transfer USDT from investor to contract (amount in USDT 18 decimals)
        require(
            usdtToken.transferFrom(msg.sender, address(this), usdtAmount),
            "USDT transfer failed"
        );
        
        // Cache variables to reduce storage reads
        address investor = msg.sender;
        uint256 tokenPrice = round.tokenPrice;
        uint256 rewardPercentage = round.rewardPercentage;
        uint256 closeDateInvestment = round.closeDateInvestment;
        uint256 endDateInvestment = round.endDateInvestment;
        
        // Use batch minting for gas optimization when minting multiple NFTs
        uint256[] memory tokenIds;
        if (tokenAmount > 1) {
            // Batch mint for multiple tokens
            tokenIds = dzNFT.batchMintNFT(
                investor,
                tokenAmount,
                roundId,
                tokenPrice,
                rewardPercentage,
                1, // Each NFT represents 1 token
                closeDateInvestment,
                endDateInvestment
            );
        } else {
            // Single mint for one token
            tokenIds = new uint256[](1);
            tokenIds[0] = dzNFT.mintNFT(
                investor,
                roundId,
                tokenPrice,
                rewardPercentage,
                1,
                closeDateInvestment,
                endDateInvestment
            );
        }
        
        // Batch update storage arrays (more gas efficient than individual pushes)
        uint256[] storage roundTokens = roundTokenIds[roundId];
        uint256[] storage userTokens = userInvestments[investor];
        uint256[] storage userRoundTokens = userNFTsInRound[roundId][investor];
        
        for(uint256 i = 0; i < tokenAmount; i++){
            roundTokens.push(tokenIds[i]);
            userTokens.push(tokenIds[i]);
            userRoundTokens.push(tokenIds[i]);
        }
        
        // Update round data (once, outside the loop)
        round.tokensSold += tokenAmount;
        totalUSDTRaised += usdtAmount;
        roundLedger[roundId] += usdtAmount;
        
        return tokenIds[0]; // Return first token ID for backward compatibility
    }
    
   
    /**
     * @dev Claim rewards for all user's NFTs in a specific round
     */
    function claimRewardRound(uint256 roundId) 
        external 
        nonReentrant 
        whenNotPaused 
        roundExists(roundId) 
    {
        uint256[] memory userTokenIds = userNFTsInRound[roundId][msg.sender];
        require(userTokenIds.length > 0, "No NFTs in this round");
        require(userTokenIds.length <= MAX_BATCH_CLAIM, "Too many NFTs to claim at once, please split into smaller batches");
        
        // First pass: calculate total payout
        (uint256 totalPayout, uint256 processedCount) = _calculateRoundPayout(userTokenIds);
        require(processedCount > 0, "No eligible NFTs to claim");
        require(totalPayout > 0, "No amount to claim");
        require(
            usdtToken.balanceOf(address(this)) >= totalPayout,
            "Insufficient contract USDT balance"
        );
        require(
            roundRewardPool[roundId] >= totalPayout,
            "Insufficient round USDT balance"
        );
        
        // Second pass: process all eligible NFTs
        _processRoundClaims(userTokenIds);
        
        // Update round ledger and transfer
        roundRewardPool[roundId] -= totalPayout;
        roundLedger[roundId] -= totalPayout;
        require(
            usdtToken.transfer(msg.sender, totalPayout),
            "USDT transfer failed"
        );
    }

    /**
     * @dev Internal function to calculate total payout for round claim
     * Logic:
     * - 0-180 days: No claims allowed
     * - 180-365 days: Can claim rewards only (first 180 days worth)
     * - 365+ days: Full redemption (principal + any unclaimed rewards)
     * 
     * Gas Optimized: Caches msg.sender and block.timestamp to reduce external calls
     */
    function _calculateRoundPayout(uint256[] memory tokenIds) 
        internal 
        view 
        returns (uint256 totalPayout, uint256 processedCount) 
    {
        address sender = msg.sender; // Cache msg.sender to reduce SLOAD operations
        uint256 currentTime = block.timestamp; // Cache timestamp to reduce external calls
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // First check ownership (cheaper operation)
            if (dzNFT.ownerOf(tokenIds[i]) != sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            if (investment.redeemed) continue;
            
            uint256 timeSincePurchase = currentTime - investment.purchaseTimestamp;
            
            // Skip if less than 180 days (no claims allowed yet)
            if (timeSincePurchase < 180 days) continue;
            
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice);
            uint256 fullRewardAmount = (principal * investment.rewardPercentage) / 100;
            
            if (timeSincePurchase >= 365 days) {
                // Phase 3: Full redemption after 365 days
                if (investment.rewardClaimed) {
                    // Only principal + remaining half reward if reward was already claimed at 180 days
                    totalPayout += principal + (fullRewardAmount / 2);
                } else {
                    // Principal + full reward if never claimed at 180 days
                    totalPayout += principal + fullRewardAmount;
                }
            } else if (timeSincePurchase >= 180 days && !investment.rewardClaimed) {
                // Phase 2: First reward claim between 180-365 days (half reward)
                totalPayout += (fullRewardAmount / 2);
            }
            // If reward already claimed and not yet 365 days, no payout
            
            processedCount++;
        }
    }

    /**
     * @dev Internal function to process round claims
     */
    /**
     * @dev Internal function to process round claims and update NFT states
     * Logic:
     * - 180-365 days: Mark reward as claimed, lock transfers until 365 days
     * - 365+ days: Full redemption (burn NFT)
     * 
     * Gas Optimized: Caches external calls and reduces repeated calculations
     */
    function _processRoundClaims(uint256[] memory tokenIds) internal {
        address sender = msg.sender; // Cache msg.sender
        uint256 currentTime = block.timestamp; // Cache timestamp
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // First check ownership (cheaper operation)
            if (dzNFT.ownerOf(tokenIds[i]) != sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            if (investment.redeemed) continue;
            
            uint256 timeSincePurchase = currentTime - investment.purchaseTimestamp;
            
            // Skip if less than 180 days (no claims allowed)
            if (timeSincePurchase < 180 days) continue;
            
            // Cache calculations to avoid recalculating in events
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice);
            uint256 rewardAmount = (principal * investment.rewardPercentage) / 100;
            
            if (timeSincePurchase >= 365 days) {
                // Phase 3: Full redemption after 365 days - burn NFT
                dzNFT.markAsRedeemed(tokenIds[i]);
                dzNFT.unlockTransfer(tokenIds[i]);
            } else if (timeSincePurchase >= 180 days && !investment.rewardClaimed) {
                // Phase 2: First reward claim between 180-365 days - mark claimed and lock transfers (half reward)
                dzNFT.markRewardClaimed(tokenIds[i]);
                emit EarlyRewardClaimed(tokenIds[i], sender, rewardAmount / 2);
            }
            // If between 180-365 days and already claimed, or not eligible, no action
        }
    }
    
    /**
     * @dev Get investment round details
     */
    function getInvestmentRound(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (InvestmentRound memory) 
    {
        return investmentRounds[roundId];
    }
    
    /**
     * @dev Get all token IDs for a specific round
     */
    function getRoundTokenIds(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256[] memory) 
    {
        return roundTokenIds[roundId];
    }
    
    /**
     * @dev Get all investments made by a user
     */
    function getUserInvestments(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userInvestments[user];
    }
    
    /**
     * @dev Get user's NFTs for a specific round
     */
    function getUserNFTsInRound(uint256 roundId, address user) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256[] memory) 
    {
        return userNFTsInRound[roundId][user];
    }
    
   
    /**
    * @dev widthdraw fund from a specific round (only owner)
    */
    function withdrawFund(uint256 roundId) 
        external 
        onlyOwner 
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
     * @dev Emergency withdraw USDT (only owner)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(
            usdtToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );
        require(
            usdtToken.transfer(owner(), amount),
            "USDT transfer failed"
        );
    }

    /**
     * @dev Emergency withdraw USDT from specific round (only owner)
     */
    function emergencyWithdrawFromRound(uint256 roundId, uint256 amount) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(
            roundLedger[roundId] >= amount,
            "Insufficient round balance"
        );
        require(
            usdtToken.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );
        
        roundLedger[roundId] -= amount;
        
        require(
            usdtToken.transfer(owner(), amount),
            "USDT transfer failed"
        );
        
    }
    
    /**
     * @dev Get contract USDT balance
     */
    function getContractUSDTBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }
    
    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    


    /**
     * @dev Get USDT balance for a specific round
     */
    function getRoundUSDTBalance(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256) 
    {
        return roundLedger[roundId];
    }


    /**
     * @dev Get total count of rounds for pagination calculation
     * @return totalRounds Total number of rounds created
     * @return activeRounds Number of currently active rounds
     */
    function getRoundsCount() 
        external 
        view 
        returns (uint256 totalRounds, uint256 activeRounds) 
    {
        totalRounds = totalRoundsCreated;
        activeRounds = 0;
        
        for (uint256 i = 0; i < _nextRoundId; i++) {
            if (investmentRounds[i].exists && investmentRounds[i].isActive) {
                activeRounds++;
            }
        }
        
        return (totalRounds, activeRounds);
    }

    /**
     * @dev Update the status of a specific round
     * @param roundId The ID of the round to update
     * @param status The new status to set
     */
    function updateStatus(uint256 roundId, Status status) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        Status oldStatus = investmentRounds[roundId].status;
        investmentRounds[roundId].status = status;
    }

    /**
     * @dev Get the current status of a round
     * @param roundId The ID of the round to check
     * @return status The current status of the round
     */
    function getRoundStatus(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (Status status) 
    {
        return investmentRounds[roundId].status;
    }

    /**
     * @dev Add rewards to a specific round (owner only)
     * @param roundId The round ID to add rewards to
     * @param amount Amount of USDT to add as rewards
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
        
        // Add to round reward pool
        roundRewardPool[roundId] += amount * 10 ** USDT_DECIMALS;
        roundLedger[roundId] += amount * 10 ** USDT_DECIMALS; // Track total added
        // Calculate reward per NFT for this round
        uint256 totalNFTsInRound = roundTokenIds[roundId].length;
        require(totalNFTsInRound > 0, "No NFTs in this round");
        
        // Update reward per NFT (cumulative)
        roundRewardPerNFT[roundId] = roundRewardPool[roundId] / totalNFTsInRound;
        
        emit RewardAdded(roundId, amount, roundRewardPool[roundId]);
    }
}
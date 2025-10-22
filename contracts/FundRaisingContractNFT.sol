// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DZNFT.sol";
import "hardhat/console.sol";

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
    
    // Sort order constants
    enum SortField { ID, NAME, CREATED_AT, CLOSE_DATE, TOTAL_RAISED, TOKENS_SOLD, REWARD_PERCENTAGE }
    enum SortDirection { ASC, DESC }
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
    mapping(uint256 => uint256) public roundUSDTLedger; // roundId => USDT balance for each round
    uint256 private _nextRoundId;
    uint256 public currentRoundId;
    uint256 public totalRoundsCreated;
    uint256 public totalUSDTRaised;
    
    event RoundCreated(
        uint256 indexed roundId,
        string roundName,
        uint256 tokenPrice,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 closeDateInvestment,
        uint256 endDateInvestment
    );
    
    event InvestmentMade(
        uint256 indexed roundId,
        uint256 indexed tokenId,
        address indexed investor,
        uint256 amountUSDT,
        uint256 tokensReceived
    );
    
    event RoundStatusChanged(uint256 indexed roundId, bool isActive);
    event RedemptionMade(uint256 indexed tokenId, address indexed investor, uint256 payout);
    event EarlyRewardClaimed(uint256 indexed tokenId, address indexed investor, uint256 rewardAmount);
    event USDTTokenUpdated(address indexed oldToken, address indexed newToken);
    event RoundFunded(uint256 indexed roundId, uint256 amount);
    event RoundEmergencyWithdraw(uint256 indexed roundId, uint256 amount);
    event RoundStatusUpdated(uint256 indexed roundId, Status oldStatus, Status newStatus);
    
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
        currentRoundId = roundId;
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
        
        emit RoundCreated(
            roundId,
            roundName,
            tokenPrice* 10 ** USDT_DECIMALS,
            rewardPercentage,
            totalTokenOpenInvestment,
            closeDateInvestment,
            endDateInvestment
        );
        
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
            
            // Emit event with cached values
            emit InvestmentMade(roundId, tokenIds[i], investor, tokenPrice, 1);
        }
        
        // Update round data (once, outside the loop)
        round.tokensSold += tokenAmount;
        totalUSDTRaised += usdtAmount;
        roundUSDTLedger[roundId] += usdtAmount;
        
        return tokenIds[0]; // Return first token ID for backward compatibility
    }
    
    /**
     * @dev Unified claim function - handles both early reward (6 months) and full redemption (1 year)
     */
    function claimRewards(uint256 tokenId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(dzNFT.ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        
        DZNFT.InvestmentData memory nftToken = dzNFT.getInvestmentData(tokenId);
        require(!nftToken.redeemed, "Investment already redeemed");
        
        uint256 timeSincePurchase = block.timestamp - nftToken.purchaseTimestamp;
        
        // Check if at least 6 months have passed
        require(timeSincePurchase >= 180 days, "Must wait at least 6 months");
        
        // Calculate amounts with proper decimal handling
        // nftToken.tokenPrice is in 18 decimals format
        // nftToken.totalTokenOpenInvestment is number of tokens (no decimals)
        uint256 principal = (nftToken.totalTokenOpenInvestment * nftToken.tokenPrice);
        uint256 rewardAmount = (principal * nftToken.rewardPercentage) / 100;
        
        uint256 totalPayout;
        bool isFullRedemption = timeSincePurchase >= 365 days; // 1 year
        
        if (isFullRedemption) {
            // Phase 3: Full redemption (after 1 year)
            if (nftToken.rewardClaimed) {
                // Only principal + remaining half dividend if dividend was already claimed
                totalPayout = principal + (rewardAmount / 2);
            } else {
                // Principal + full dividend if dividend was not claimed early
                totalPayout = principal + rewardAmount;
            }
        } else {
            // Phase 2: Early dividend only (6 months to 1 year) - half dividend
            require(!nftToken.rewardClaimed, "Reward already claimed");
            totalPayout = rewardAmount / 2;
        }
        
        require(totalPayout > 0, "No amount to claim");
        require(
            usdtToken.balanceOf(address(this)) >= totalPayout,
            "Insufficient contract USDT balance"
        );
        
        // Check round has sufficient funds
        require(
            roundUSDTLedger[nftToken.roundId] >= totalPayout,
            "Insufficient round USDT balance"
        );
        
        if (isFullRedemption) {
            // Mark as fully redeemed and unlock transfer
            dzNFT.markAsRedeemed(tokenId);
            dzNFT.unlockTransfer(tokenId);
            emit RedemptionMade(tokenId, msg.sender, totalPayout);
        } else {
            // Mark reward as claimed and lock transfer
            dzNFT.markRewardClaimed(tokenId);
            emit EarlyRewardClaimed(tokenId, msg.sender, totalPayout);
        }
        
        // Update round ledger
        roundUSDTLedger[nftToken.roundId] -= totalPayout;
        
        // Transfer USDT to investor
        require(
            usdtToken.transfer(msg.sender, totalPayout),
            "USDT transfer failed"
        );
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
            roundUSDTLedger[roundId] >= totalPayout,
            "Insufficient round USDT balance"
        );
        
        // Second pass: process all eligible NFTs
        _processRoundClaims(userTokenIds);
        
        // Update round ledger and transfer
        roundUSDTLedger[roundId] -= totalPayout;
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
                uint256 payout = investment.rewardClaimed ? principal + (rewardAmount / 2) : principal + rewardAmount;
                dzNFT.markAsRedeemed(tokenIds[i]);
                dzNFT.unlockTransfer(tokenIds[i]);
                emit RedemptionMade(tokenIds[i], sender, payout);
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
     * @dev Get number of NFTs a user has in a specific round
     */
    function getUserNFTCountInRound(uint256 roundId, address user) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256) 
    {
        return userNFTsInRound[roundId][user].length;
    }
    
    /**
     * @dev Get all unique investors in a specific round
     */
    function getRoundInvestors(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (address[] memory investors, uint256[] memory nftCounts) 
    {
        uint256[] memory tokenIds = roundTokenIds[roundId];
        address[] memory tempInvestors = new address[](tokenIds.length);
        uint256[] memory tempCounts = new uint256[](tokenIds.length);
        uint256 uniqueCount = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            address investor = investment.originalBuyer;
            
            // Check if investor already exists in our temp arrays
            bool exists = false;
            uint256 existingIndex = 0;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempInvestors[j] == investor) {
                    exists = true;
                    existingIndex = j;
                    break;
                }
            }
            
            if (exists) {
                tempCounts[existingIndex]++;
            } else {
                tempInvestors[uniqueCount] = investor;
                tempCounts[uniqueCount] = 1;
                uniqueCount++;
            }
        }
        
        // Create properly sized arrays
        investors = new address[](uniqueCount);
        nftCounts = new uint256[](uniqueCount);
        
        for (uint256 i = 0; i < uniqueCount; i++) {
            investors[i] = tempInvestors[i];
            nftCounts[i] = tempCounts[i];
        }
        
        return (investors, nftCounts);
    }
    
    /**
     * @dev Check if a user has invested in a specific round
     */
    function hasUserInvestedInRound(uint256 roundId, address user) 
        external 
        view 
        roundExists(roundId) 
        returns (bool) 
    {
        return userNFTsInRound[roundId][user].length > 0;
    }
    
    /**
     * @dev Get total USDT amount invested by a user in a specific round
     */
    function getUserTotalInvestmentInRound(uint256 roundId, address user) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256 totalUSDT, uint256 totalTokens) 
    {
        uint256[] memory userTokenIds = userNFTsInRound[roundId][user];
        totalUSDT = 0;
        totalTokens = 0;
        
        for (uint256 i = 0; i < userTokenIds.length; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(userTokenIds[i]);
            uint256 investmentUSDT = (investment.totalTokenOpenInvestment * investment.tokenPrice) / (10 ** USDT_DECIMALS);
            totalUSDT += investmentUSDT;
            totalTokens += investment.totalTokenOpenInvestment;
        }
        
        return (totalUSDT, totalTokens);
    }
    
    /**
     * @dev Get detailed investment summary for a user in a specific round
     */
    function getUserRoundSummary(uint256 roundId, address user) 
        external 
        view 
        roundExists(roundId) 
        returns (
            uint256 nftCount,
            uint256 totalUSDTInvested,
            uint256 totalTokens,
            uint256 expectedReward,
            uint256 totalExpectedPayout,
            bool hasMaturedInvestments,
            bool hasRedeemedInvestments
        ) 
    {
        uint256[] memory userTokenIds = userNFTsInRound[roundId][user];
        nftCount = userTokenIds.length;
        totalUSDTInvested = 0;
        totalTokens = 0;
        expectedReward = 0;
        totalExpectedPayout = 0;
        hasMaturedInvestments = false;
        hasRedeemedInvestments = false;
        
        for (uint256 i = 0; i < userTokenIds.length; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(userTokenIds[i]);
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice) / (10 ** USDT_DECIMALS);
            uint256 reward = (principal * investment.rewardPercentage) / 100;
            
            totalUSDTInvested += principal;
            totalTokens += investment.totalTokenOpenInvestment;
            expectedReward += reward;
            totalExpectedPayout += (principal + reward);
            
            if (block.timestamp >= investment.endDateInvestment) {
                hasMaturedInvestments = true;
            }
            
            if (investment.redeemed) {
                hasRedeemedInvestments = true;
            }
        }
        
        return (
            nftCount,
            totalUSDTInvested,
            totalTokens,
            expectedReward,
            totalExpectedPayout,
            hasMaturedInvestments,
            hasRedeemedInvestments
        );
    }
    
    /**
     * @dev Check if a round is still open for investment
     */
    function isRoundOpen(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (bool) 
    {
        InvestmentRound memory round = investmentRounds[roundId];
        return round.isActive && 
               block.timestamp <= round.closeDateInvestment &&
               round.tokensSold < round.totalTokenOpenInvestment;
    }
    
    /**
     * @dev Get available tokens remaining in a round
     */
    function getAvailableTokens(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (uint256) 
    {
        InvestmentRound memory round = investmentRounds[roundId];
        return round.totalTokenOpenInvestment - round.tokensSold;
    }
    
    /**
     * @dev Fund contract with USDT for redemptions (only owner)
     */
    function fundContract(uint256 amount) external onlyOwner {
        require(
            usdtToken.transferFrom(msg.sender, address(this), amount),
            "USDT transfer failed"
        );
    }

    /**
     * @dev Fund specific round with USDT (only owner)
     */
    function addReward(uint256 roundId, uint256 amount) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(
            usdtToken.transferFrom(msg.sender, address(this), amount * 10 ** USDT_DECIMALS),
            "USDT transfer failed"
        );

        roundUSDTLedger[roundId] += amount * 10 ** USDT_DECIMALS;
        investmentRounds[roundId].status = Status.DIVIDEND_PAID;
        emit RoundFunded(roundId, amount * 10 ** USDT_DECIMALS);
    }

    /**
    * @dev widthdraw fund from a specific round (only owner)
    */
    function withdrawFund(uint256 roundId) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        uint256 amount = roundUSDTLedger[roundId];
        roundUSDTLedger[roundId] = 0;

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
            roundUSDTLedger[roundId] >= amount,
            "Insufficient round balance"
        );
        require(
            usdtToken.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );
        
        roundUSDTLedger[roundId] -= amount;
        
        require(
            usdtToken.transfer(owner(), amount),
            "USDT transfer failed"
        );
        
        emit RoundEmergencyWithdraw(roundId, amount);
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
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 totalRounds,
        uint256 totalUSDTRaisedAmount,
        uint256 contractUSDTBalance,
        uint256 activeRounds
    ) {
        uint256 active = 0;
        for (uint256 i = 0; i < _nextRoundId; i++) {
            if (investmentRounds[i].exists && investmentRounds[i].isActive) {
                active++;
            }
        }
        
        return (
            totalRoundsCreated,
            totalUSDTRaised,
            usdtToken.balanceOf(address(this)),
            active
        );
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
        return roundUSDTLedger[roundId];
    }

    /**
     * @dev Get USDT balances for all rounds
     */
    function getAllRoundUSDTBalances() 
        external 
        view 
        returns (uint256[] memory roundIds, uint256[] memory balances) 
    {
        roundIds = new uint256[](totalRoundsCreated);
        balances = new uint256[](totalRoundsCreated);
        
        uint256 count = 0;
        for (uint256 i = 0; i < _nextRoundId; i++) {
            if (investmentRounds[i].exists) {
                roundIds[count] = i;
                balances[count] = roundUSDTLedger[i];
                count++;
            }
        }
        
        return (roundIds, balances);
    }

    /**
     * @dev Check if token can claim early dividend
     */
    function canTokenClaimEarlyReward(uint256 tokenId) 
        external 
        view 
        returns (bool) 
    {
        return dzNFT.canClaimEarlyReward(tokenId);
    }

    /**
     * @dev Check if token can be fully redeemed
     */
    function canTokenFullyRedeem(uint256 tokenId) 
        external 
        view 
        returns (bool) 
    {
        return dzNFT.canFullyRedeem(tokenId);
    }

    /**
     * @dev Get calculation of reward amount and principal amount for a specific round
     */
    /**
     * @dev Get calculation of reward amounts for a round
     * Gas Optimized: Early return for empty rounds and reduced external calls
     */
    function getCalculationDividendAmount(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (
            uint256 totalPrincipalAmount,
            uint256 totalRewardAmount,
            uint256 totalNFTs,
            uint256 redeemedNFTs,
            uint256 rewardClaimedNFTs
        ) 
    {
        uint256[] memory tokenIds = roundTokenIds[roundId];
        totalNFTs = tokenIds.length;
        
        // Early return if no tokens to save gas
        if (totalNFTs == 0) {
            return (0, 0, 0, 0, 0);
        }
        
        // Initialize counters
        totalPrincipalAmount = 0;
        totalRewardAmount = 0;
        redeemedNFTs = 0;
        rewardClaimedNFTs = 0;
        
        for (uint256 i = 0; i < totalNFTs; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            
            // Calculate principal and reward for this NFT (in USDT decimals)
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice) / (10 ** USDT_DECIMALS);
            uint256 reward = (principal * investment.rewardPercentage) / 100;
            
            totalPrincipalAmount += principal;
            totalRewardAmount += reward;
            
            // Efficient status counting
            if (investment.redeemed) {
                redeemedNFTs++;
            }
            if (investment.rewardClaimed) {
                rewardClaimedNFTs++;
            }
        }
        
        return (
            totalPrincipalAmount,
            totalRewardAmount,
            totalNFTs,
            redeemedNFTs,
            rewardClaimedNFTs
        );
    }

    /**
     * @dev Get comprehensive round information including statistics
     * @param roundId The ID of the round to get information for
     * @return roundInfo Basic round information from InvestmentRound struct
     * @return totalUSDTRaisedInRound Total USDT raised in this round
     * @return totalInvestors Number of unique investors in this round
     * @return availableTokens Remaining tokens available for investment
     * @return isInvestmentOpen Whether the round is currently open for investment
     * @return isRedemptionOpen Whether redemption period has started (1 year passed)
     * @return daysUntilClose Days remaining until investment close (0 if closed)
     * @return daysUntilRedemption Days remaining until redemption opens (0 if open)
     */
    function getRoundInformation(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (
            InvestmentRound memory roundInfo,
            uint256 totalUSDTRaisedInRound,
            uint256 totalInvestors,
            uint256 availableTokens,
            bool isInvestmentOpen,
            bool isRedemptionOpen,
            uint256 daysUntilClose,
            uint256 daysUntilRedemption
        ) 
    {
        roundInfo = investmentRounds[roundId];
        
        // Calculate total USDT raised
        totalUSDTRaisedInRound = roundInfo.tokensSold * roundInfo.tokenPrice;
        
        // Get unique investors count
        (address[] memory investors,) = this.getRoundInvestors(roundId);
        totalInvestors = investors.length;
        
        // Calculate available tokens
        availableTokens = roundInfo.totalTokenOpenInvestment - roundInfo.tokensSold;
        
        // Check if investment period is open
        isInvestmentOpen = roundInfo.isActive && 
                          block.timestamp <= roundInfo.closeDateInvestment &&
                          availableTokens > 0;
        
        // Check if redemption period is open (1 year after close date)
        uint256 redemptionStartDate = roundInfo.closeDateInvestment + 365 days;
        isRedemptionOpen = block.timestamp >= redemptionStartDate;
        
        // Calculate days until close
        if (block.timestamp >= roundInfo.closeDateInvestment) {
            daysUntilClose = 0;
        } else {
            daysUntilClose = (roundInfo.closeDateInvestment - block.timestamp) / 1 days;
        }
        
        // Calculate days until redemption opens
        if (block.timestamp >= redemptionStartDate) {
            daysUntilRedemption = 0;
        } else {
            daysUntilRedemption = (redemptionStartDate - block.timestamp) / 1 days;
        }
        
        return (
            roundInfo,
            totalUSDTRaisedInRound,
            totalInvestors,
            availableTokens,
            isInvestmentOpen,
            isRedemptionOpen,
            daysUntilClose,
            daysUntilRedemption
        );
    }

    /**
     * @dev Get summary of all rounds
     * @return roundIds Array of all round IDs
     * @return roundNames Array of round names
     * @return roundStatuses Array indicating if rounds are active
     * @return totalRaised Array of total USDT raised per round
     * @return isInvestmentOpenArray Array indicating if investment is open for each round
     */
    function getAllRoundsSummary() 
        external 
        view 
        returns (
            uint256[] memory roundIds,
            string[] memory roundNames,
            bool[] memory roundStatuses,
            uint256[] memory totalRaised,
            bool[] memory isInvestmentOpenArray
        ) 
    {
        uint256 totalRounds = totalRoundsCreated;
        
        roundIds = new uint256[](totalRounds);
        roundNames = new string[](totalRounds);
        roundStatuses = new bool[](totalRounds);
        totalRaised = new uint256[](totalRounds);
        isInvestmentOpenArray = new bool[](totalRounds);
        
        for (uint256 i = 0; i < totalRounds; i++) {
            uint256 roundId = i + 1; // Round IDs start from 1
            InvestmentRound memory round = investmentRounds[roundId];
            
            roundIds[i] = roundId;
            roundNames[i] = round.roundName;
            roundStatuses[i] = round.isActive;
            totalRaised[i] = round.tokensSold * round.tokenPrice;
            
            // Check if investment is open
            uint256 availableTokens = round.totalTokenOpenInvestment - round.tokensSold;
            isInvestmentOpenArray[i] = round.isActive && 
                               block.timestamp <= round.closeDateInvestment &&
                               availableTokens > 0;
        }
        
        return (roundIds, roundNames, roundStatuses, totalRaised, isInvestmentOpenArray);
    }

    /**
     * @dev Get paginated summary of rounds with enhanced information and sorting
     * @param offset Starting position (0-based)
     * @param limit Maximum number of rounds to return (recommended: 10-50)
     * @param sortField Field to sort by (0=ID, 1=NAME, 2=CREATED_AT, 3=CLOSE_DATE, 4=TOTAL_RAISED, 5=TOKENS_SOLD, 6=REWARD_PERCENTAGE)
     * @param sortDirection Direction to sort (0=ASC, 1=DESC)
     * @return roundIds Array of round IDs
     * @return roundNames Array of round names
     * @return roundStatuses Array indicating if rounds are active
     * @return totalRaised Array of total USDT raised per round
     * @return isInvestmentOpenArray Array indicating if investment is open for each round
     * @return availableTokensArray Array of available tokens for each round
     * @return daysUntilCloseArray Array of days until close for each round
     * @return totalPages Total number of pages available
     * @return currentPage Current page number (1-based)
     * @return hasMore Whether there are more rounds available
     */
    function getAllRoundsSummaryPaginated(
        uint256 offset, 
        uint256 limit,
        SortField sortField,
        SortDirection sortDirection
    ) 
        external 
        view 
        returns (
            uint256[] memory roundIds,
            string[] memory roundNames,
            bool[] memory roundStatuses,
            uint256[] memory totalRaised,
            bool[] memory isInvestmentOpenArray,
            uint256[] memory availableTokensArray,
            uint256[] memory daysUntilCloseArray,
            uint256 totalPages,
            uint256 currentPage,
            bool hasMore
        ) 
    {
        uint256 totalRounds = totalRoundsCreated;
        require(limit > 0 && limit <= 100, "Limit must be between 1 and 100");
        require(offset < totalRounds, "Offset exceeds total rounds");
        
        // Calculate pagination info
        totalPages = (totalRounds + limit - 1) / limit; // Ceiling division
        currentPage = (offset / limit) + 1;
        
        // Get sorted round indices
        uint256[] memory sortedIndices = _getSortedRoundIndices(sortField, sortDirection);
        
        // Calculate actual number of rounds to return
        uint256 remainingRounds = totalRounds - offset;
        uint256 actualLimit = remainingRounds > limit ? limit : remainingRounds;
        hasMore = offset + actualLimit < totalRounds;
        
        // Initialize arrays with actual size needed
        roundIds = new uint256[](actualLimit);
        roundNames = new string[](actualLimit);
        roundStatuses = new bool[](actualLimit);
        totalRaised = new uint256[](actualLimit);
        isInvestmentOpenArray = new bool[](actualLimit);
        availableTokensArray = new uint256[](actualLimit);
        daysUntilCloseArray = new uint256[](actualLimit);
        
        // Cache current time for efficiency
        uint256 currentTime = block.timestamp;
        
        for (uint256 i = 0; i < actualLimit; i++) {
            uint256 sortedIndex = offset + i;
            uint256 roundId = sortedIndices[sortedIndex]; // Round IDs start from 0, not 1
            InvestmentRound memory round = investmentRounds[roundId];
            
            roundIds[i] = roundId;
            roundNames[i] = round.roundName;
            roundStatuses[i] = round.isActive;
            totalRaised[i] = round.tokensSold * round.tokenPrice;
            
            // Calculate available tokens
            uint256 availableTokens = round.totalTokenOpenInvestment - round.tokensSold;
            availableTokensArray[i] = availableTokens;
            
            // Check if investment is open
            isInvestmentOpenArray[i] = round.isActive && 
                                      currentTime <= round.closeDateInvestment &&
                                      availableTokens > 0;
            
            // Calculate days until close
            if (currentTime >= round.closeDateInvestment) {
                daysUntilCloseArray[i] = 0;
            } else {
                daysUntilCloseArray[i] = (round.closeDateInvestment - currentTime) / 1 days;
            }
        }
        
        return (
            roundIds,
            roundNames,
            roundStatuses,
            totalRaised,
            isInvestmentOpenArray,
            availableTokensArray,
            daysUntilCloseArray,
            totalPages,
            currentPage,
            hasMore
        );
    }

    /**
     * @dev Get paginated detailed round information with sorting (more comprehensive)
     * @param offset Starting position (0-based)
     * @param limit Maximum number of rounds to return (recommended: 5-20)
     * @param sortField Field to sort by (0=ID, 1=NAME, 2=CREATED_AT, 3=CLOSE_DATE, 4=TOTAL_RAISED, 5=TOKENS_SOLD, 6=REWARD_PERCENTAGE)
     * @param sortDirection Direction to sort (0=ASC, 1=DESC)
     * @return rounds Array of complete round information
     * @return investorCounts Array of unique investor counts per round
     * @return totalPages Total number of pages available
     * @return currentPage Current page number (1-based)
     * @return hasMore Whether there are more rounds available
     */
    function getAllRoundsDetailedPaginated(
        uint256 offset, 
        uint256 limit,
        SortField sortField,
        SortDirection sortDirection
    ) 
        external 
        view 
        returns (
            InvestmentRound[] memory rounds,
            uint256[] memory investorCounts,
            uint256 totalPages,
            uint256 currentPage,
            bool hasMore
        ) 
    {
      
        uint256 totalRounds = totalRoundsCreated;
        require(limit > 0 && limit <= 50, "Limit must be between 1 and 50");
        require(offset < totalRounds, "Offset exceeds total rounds");
        
        // Calculate pagination info
        totalPages = (totalRounds + limit - 1) / limit;
        currentPage = (offset / limit) + 1;
        
        // Get sorted round indices
        uint256[] memory sortedIndices = _getSortedRoundIndices(sortField, sortDirection);
        
        // Calculate actual number of rounds to return
        uint256 remainingRounds = totalRounds - offset;
        uint256 actualLimit = remainingRounds > limit ? limit : remainingRounds;
        hasMore = offset + actualLimit < totalRounds;
        
        // Initialize arrays
        rounds = new InvestmentRound[](actualLimit);
        investorCounts = new uint256[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            uint256 sortedIndex = offset + i;
            uint256 roundId = sortedIndices[sortedIndex]; // Round IDs start from 0, not 1
            
            rounds[i] = investmentRounds[roundId];
            
            // Get investor count (this is more expensive but provides complete data)
            (address[] memory investors,) = this.getRoundInvestors(roundId);
            investorCounts[i] = investors.length;
        }
        
        return (rounds, investorCounts, totalPages, currentPage, hasMore);
    }

    /**
     * @dev Convenience function - Get paginated summary with default sorting (by ID ASC)
     * @param offset Starting position (0-based)
     * @param limit Maximum number of rounds to return
     */
    function getAllRoundsSummaryPaginatedDefault(uint256 offset, uint256 limit) 
        external 
        view 
        returns (
            uint256[] memory roundIds,
            string[] memory roundNames,
            bool[] memory roundStatuses,
            uint256[] memory totalRaised,
            bool[] memory isInvestmentOpenArray,
            uint256[] memory availableTokensArray,
            uint256[] memory daysUntilCloseArray,
            uint256 totalPages,
            uint256 currentPage,
            bool hasMore
        ) 
    {
        return this.getAllRoundsSummaryPaginated(offset, limit, SortField.ID, SortDirection.ASC);
    }

    /**
     * @dev Convenience function - Get detailed paginated rounds with default sorting (by ID ASC)
     * @param offset Starting position (0-based)
     * @param limit Maximum number of rounds to return
     */
    function getAllRoundsDetailedPaginatedDefault(uint256 offset, uint256 limit) 
        external 
        view 
        returns (
            InvestmentRound[] memory rounds,
            uint256[] memory investorCounts,
            uint256 totalPages,
            uint256 currentPage,
            bool hasMore
        ) 
    {
        return this.getAllRoundsDetailedPaginated(offset, limit, SortField.ID, SortDirection.ASC);
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
     * @dev Internal function to get sorted round indices based on sort field and direction
     * Gas optimized: Uses efficient sorting algorithm for small datasets
     * @param sortField Field to sort by
     * @param sortDirection Direction to sort (ASC or DESC)
     * @return sortedIndices Array of round indices in sorted order (0-based)
     */
    function _getSortedRoundIndices(SortField sortField, SortDirection sortDirection) 
        internal 
        view 
        returns (uint256[] memory sortedIndices) 
    {
        // First, collect all existing round IDs
        uint256[] memory tempIndices = new uint256[](_nextRoundId);
        uint256 existingCount = 0;
        
        for (uint256 i = 0; i < _nextRoundId; i++) {
            if (investmentRounds[i].exists) {
                tempIndices[existingCount] = i;
                existingCount++;
            }
        }
        
        // Create array with only existing rounds
        sortedIndices = new uint256[](existingCount);
        for (uint256 i = 0; i < existingCount; i++) {
            sortedIndices[i] = tempIndices[i];
        }
        
        // Bubble sort implementation (efficient for small datasets in blockchain)
        for (uint256 i = 0; i < existingCount - 1; i++) {
            for (uint256 j = 0; j < existingCount - i - 1; j++) {
                bool shouldSwap = _compareRounds(
                    sortedIndices[j], 
                    sortedIndices[j + 1], 
                    sortField, 
                    sortDirection
                );
                
                if (shouldSwap) {
                    // Swap indices
                    uint256 temp = sortedIndices[j];
                    sortedIndices[j] = sortedIndices[j + 1];
                    sortedIndices[j + 1] = temp;
                }
            }
        }
        
        return sortedIndices;
    }
    
    /**
     * @dev Internal function to compare two rounds based on sort criteria
     * @param indexA First round index
     * @param indexB Second round index  
     * @param sortField Field to compare
     * @param sortDirection Sort direction
     * @return shouldSwap True if rounds should be swapped
     */
    function _compareRounds(
        uint256 indexA, 
        uint256 indexB, 
        SortField sortField, 
        SortDirection sortDirection
    ) 
        internal 
        view 
        returns (bool shouldSwap) 
    {
        uint256 roundIdA = indexA; // Round IDs start from 0
        uint256 roundIdB = indexB; // Round IDs start from 0
        InvestmentRound memory roundA = investmentRounds[roundIdA];
        InvestmentRound memory roundB = investmentRounds[roundIdB];
        
        bool aIsGreater;
        
        if (sortField == SortField.ID) {
            aIsGreater = roundA.roundId > roundB.roundId;
        } else if (sortField == SortField.NAME) {
            // Simple string comparison (basic lexicographic)
            aIsGreater = keccak256(bytes(roundA.roundName)) > keccak256(bytes(roundB.roundName));
        } else if (sortField == SortField.CREATED_AT) {
            aIsGreater = roundA.createdAt > roundB.createdAt;
        } else if (sortField == SortField.CLOSE_DATE) {
            aIsGreater = roundA.closeDateInvestment > roundB.closeDateInvestment;
        } else if (sortField == SortField.TOTAL_RAISED) {
            uint256 totalRaisedA = roundA.tokensSold * roundA.tokenPrice;
            uint256 totalRaisedB = roundB.tokensSold * roundB.tokenPrice;
            aIsGreater = totalRaisedA > totalRaisedB;
        } else if (sortField == SortField.TOKENS_SOLD) {
            aIsGreater = roundA.tokensSold > roundB.tokensSold;
        } else if (sortField == SortField.REWARD_PERCENTAGE) {
            aIsGreater = roundA.rewardPercentage > roundB.rewardPercentage;
        }
        
        // Apply sort direction
        if (sortDirection == SortDirection.ASC) {
            shouldSwap = aIsGreater;
        } else {
            shouldSwap = !aIsGreater;
        }
        
        return shouldSwap;
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
        emit RoundStatusUpdated(roundId, oldStatus, status);
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
     * @dev Get round performance metrics
     * @param roundId The ID of the round to get metrics for
     * @return soldPercentage Percentage of tokens sold (in basis points, 10000 = 100%)
     * @return averageInvestmentSize Average investment size in USDT
     * @return totalRewardsPaid Total Dividends paid out so far
     * @return totalPrincipalRedeemed Total principal amount redeemed
     * @return earlyRewardsClaimed Number of early Dividends claimed (6 months)
     * @return fullRedemptions Number of full redemptions (1 year)
     */
    function getRoundMetrics(uint256 roundId) 
        external 
        view 
        roundExists(roundId) 
        returns (
            uint256 soldPercentage,
            uint256 averageInvestmentSize,
            uint256 totalRewardsPaid,
            uint256 totalPrincipalRedeemed,
            uint256 earlyRewardsClaimed,
            uint256 fullRedemptions
        ) 
    {
        InvestmentRound memory round = investmentRounds[roundId];
        uint256[] memory tokenIds = roundTokenIds[roundId];
        
        // Calculate sold percentage (in basis points)
        if (round.totalTokenOpenInvestment > 0) {
            soldPercentage = (round.tokensSold * 10000) / round.totalTokenOpenInvestment;
        }
        
        // Calculate average investment size
        (address[] memory investors,) = this.getRoundInvestors(roundId);
        if (investors.length > 0) {
            uint256 totalRaised = round.tokensSold * round.tokenPrice;
            averageInvestmentSize = totalRaised / investors.length;
        }
        
        // Calculate rewards and redemptions
        for (uint256 i = 0; i < tokenIds.length; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            
            if (investment.rewardClaimed) {
                earlyRewardsClaimed++;
                // Calculate reward amount (half of the reward for early claim)
                uint256 principalAmount = investment.totalTokenOpenInvestment * round.tokenPrice;
                uint256 fullReward = (principalAmount * round.rewardPercentage) / 100;
                totalRewardsPaid += fullReward / 2;
            }
            
            if (investment.redeemed) {
                fullRedemptions++;
                uint256 principalAmount = investment.totalTokenOpenInvestment * round.tokenPrice;
                totalPrincipalRedeemed += principalAmount;
                
                // Add remaining reward for full redemption
                if (investment.rewardClaimed) {
                    // Already claimed early reward, add remaining half
                    uint256 fullReward = (principalAmount * round.rewardPercentage) / 100;
                    totalRewardsPaid += fullReward / 2;
                } else {
                    // Full reward for full redemption without early claim
                    uint256 fullReward = (principalAmount * round.rewardPercentage) / 100;
                    totalRewardsPaid += fullReward;
                }
            }
        }
        
        return (
            soldPercentage,
            averageInvestmentSize,
            totalRewardsPaid,
            totalPrincipalRedeemed,
            earlyRewardsClaimed,
            fullRedemptions
        );
    }
}
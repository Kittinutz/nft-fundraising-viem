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
    }
    
    mapping(uint256 => InvestmentRound) public investmentRounds;
    mapping(uint256 => uint256[]) public roundTokenIds; // roundId => tokenIds array
    mapping(address => uint256[]) public userInvestments; // user => tokenIds array
    mapping(uint256 => mapping(address => uint256[])) public userNFTsInRound; // roundId => user => tokenIds array
    mapping(uint256 => uint256) public roundUSDTLedger; // roundId => USDT balance for each round
    uint256 private _nextRoundId;
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
            createdAt: block.timestamp
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
        
        // Calculate USDT per token for individual NFTs
        uint256 usdtPerToken = round.tokenPrice;
        uint256[] memory tokenIds = new uint256[](tokenAmount);
        
        for(uint256 i = 0; i < tokenAmount; i++){
            // Mint NFT representing 1 token investment
            uint256 tokenId = dzNFT.mintNFT(
                msg.sender,
                roundId,
                round.tokenPrice,
                round.rewardPercentage,
                1, // Each NFT represents 1 token
                round.closeDateInvestment,
                round.endDateInvestment
            );
            
            // Track investments
            roundTokenIds[roundId].push(tokenId);
            userInvestments[msg.sender].push(tokenId);
            userNFTsInRound[roundId][msg.sender].push(tokenId);
            tokenIds[i] = tokenId;
            
            emit InvestmentMade(roundId, tokenId, msg.sender, usdtPerToken, 1);
        }
        
        // Update round data (once, outside the loop)
        round.tokensSold += tokenAmount;
        totalUSDTRaised += usdtAmount;
        roundUSDTLedger[roundId] += usdtAmount; // Track USDT for this specific round
        
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
        uint256 principal = (nftToken.totalTokenOpenInvestment * nftToken.tokenPrice) / (10 ** USDT_DECIMALS);
        uint256 rewardAmount = (principal * nftToken.rewardPercentage) / 10000;
        
        uint256 totalPayout;
        bool isFullRedemption = timeSincePurchase >= 365 days; // 1 year
        
        if (isFullRedemption) {
            // Phase 3: Full redemption (after 1 year)
            if (nftToken.rewardClaimed) {
                // Only principal if reward was already claimed
                totalPayout = principal;
            } else {
                // Principal + full reward if reward was not claimed early
                totalPayout = principal + rewardAmount;
            }
        } else {
            // Phase 2: Early reward only (6 months to 1 year)
            require(!nftToken.rewardClaimed, "Reward already claimed");
            totalPayout = rewardAmount;
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
     */
    function _calculateRoundPayout(uint256[] memory tokenIds) 
        internal 
        view 
        returns (uint256 totalPayout, uint256 processedCount) 
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (dzNFT.ownerOf(tokenIds[i]) != msg.sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            if (investment.redeemed) continue;
            
            uint256 timeSincePurchase = block.timestamp - investment.purchaseTimestamp;
            
            // Skip if less than 180 days (no claims allowed yet)
            if (timeSincePurchase < 180 days) continue;
            
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice);
            uint256 fullRewardAmount = (principal * investment.rewardPercentage) / 100;
            
            if (timeSincePurchase >= 365 days) {
                // Phase 3: Full redemption after 365 days
                if (investment.rewardClaimed) {
                    // Only principal + remaining reward if reward was already claimed at 180 days
                    totalPayout += principal + (fullRewardAmount / 2);
                } else {
                    // Principal + full reward if never claimed at 180 days
                    totalPayout += principal + fullRewardAmount;
                }
            } else if (timeSincePurchase >= 180 days && !investment.rewardClaimed) {
                // Phase 2: First reward claim between 180-365 days
                totalPayout += (fullRewardAmount / 2) ;
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
     */
    function _processRoundClaims(uint256[] memory tokenIds) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (dzNFT.ownerOf(tokenIds[i]) != msg.sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            if (investment.redeemed) continue;
            
            uint256 timeSincePurchase = block.timestamp - investment.purchaseTimestamp;
            
            // Skip if less than 180 days (no claims allowed)
            if (timeSincePurchase < 180 days) continue;
            
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice) / (10 ** USDT_DECIMALS);
            uint256 rewardAmount = (principal * investment.rewardPercentage) / 10000;
            
            if (timeSincePurchase >= 365 days) {
                // Phase 3: Full redemption after 365 days - burn NFT
                uint256 payout = investment.rewardClaimed ? principal : principal + rewardAmount;
                dzNFT.markAsRedeemed(tokenIds[i]);
                dzNFT.unlockTransfer(tokenIds[i]);
                emit RedemptionMade(tokenIds[i], msg.sender, payout);
            } else if (timeSincePurchase >= 180 days && !investment.rewardClaimed) {
                // Phase 2: First reward claim between 180-365 days - mark claimed and lock transfers
                dzNFT.markRewardClaimed(tokenIds[i]);
                emit EarlyRewardClaimed(tokenIds[i], msg.sender, rewardAmount);
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
            uint256 reward = (principal * investment.rewardPercentage) / 10000;
            
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
     * @dev Check if token can claim early reward
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
    function getCalculationRewardAmount(uint256 roundId) 
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
        totalPrincipalAmount = 0;
        totalRewardAmount = 0;
        totalNFTs = tokenIds.length;
        redeemedNFTs = 0;
        rewardClaimedNFTs = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenIds[i]);
            
            // Calculate principal and reward for this NFT (in USDT decimals)
            uint256 principal = (investment.totalTokenOpenInvestment * investment.tokenPrice) / (10 ** USDT_DECIMALS);
            uint256 reward = (principal * investment.rewardPercentage) / 10000;
            
            totalPrincipalAmount += principal;
            totalRewardAmount += reward;
            
            // Count status
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
}
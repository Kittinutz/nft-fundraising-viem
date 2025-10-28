// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DZNFT.sol";
import "./FundRaisingCore.sol";
/**
 * @title FundRaisingClaims
 * @dev Handles reward claiming functionality
 * 
 * Reward Distribution Logic:
 * - Input: roundId (user's NFTs are fetched automatically)
 * - Phase 1 (180+ days after closeDate): User can claim 50% of reward
 * - Phase 2 (365+ days after closeDate): User can claim remaining 50% reward + principal
 * - Calculation: principal = token_price * number_of_tokens
 *               reward = (principal * reward_percentage) / 100
 *               first_payout (180 days) = reward / 2
 *               second_payout (365 days) = reward / 2 + principal
 */
contract FundRaisingClaims is Ownable, ReentrancyGuard {
    FundRaisingCore public immutable coreContract;
    DZNFT public immutable dzNFT;
    IERC20 public immutable usdtToken;
    
    // Constants
    uint256 public constant MAX_BATCH_CLAIM = 50;
    uint256 public constant FIRST_CLAIM_DAYS = 180 days;
    uint256 public constant FULL_CLAIM_DAYS = 365 days;
    
    // Events
    event RewardClaimed(
        address indexed investor, 
        uint256 indexed roundId, 
        uint256 rewardAmount,
        uint256 claimPhase // 1 for first claim, 2 for full redemption
    );
    
    constructor(address _coreContract, address _dzNFT, address _usdtToken) Ownable(msg.sender) {
        require(_coreContract != address(0), "Invalid core contract address");
        require(_dzNFT != address(0), "Invalid DZNFT address");
        require(_usdtToken != address(0), "Invalid USDT address");
        
        coreContract = FundRaisingCore(_coreContract);
        dzNFT = DZNFT(_dzNFT);
        usdtToken = IERC20(_usdtToken);
    }
    
    /**
     * @dev Claim reward for a specific round
     * User's NFTs are automatically fetched and processed
     * 
     * Phases:
     * 1. 180+ days: Claim first 50% of reward
     * 2. 365+ days: Claim remaining 50% reward + principal (full redemption)
     */
    function claimRewardRound(uint256 roundId) 
        external 
        nonReentrant 
    {
        // Get user's NFTs for this round automatically
        uint256[] memory userTokenIds = dzNFT.getUserNFTsByRound(msg.sender, roundId);
    
        require(userTokenIds.length > 0, "No NFTs in this round");
        require(userTokenIds.length <= MAX_BATCH_CLAIM, "Too many NFTs to claim at once");
        
        // Calculate total payout
        (uint256 totalPayout, uint256 claimPhase) = _calculateRoundPayout(userTokenIds);
        require(totalPayout > 0, "No amount to claim");
        
        // Verify round has sufficient balance
        uint256 roundRewardPool = coreContract.roundRewardPool(roundId);
        require(roundRewardPool >= totalPayout, "Insufficient round reward pool");
        
        // Process all eligible NFTs
        _processRoundClaims(userTokenIds);
        
        // Request reward transfer from core contract
        coreContract.transferRewardToClaims(roundId, totalPayout);
        
        // Transfer reward to user from core contract's balance
        // The core contract has already transferred the funds via transferRewardToClaims
        require(
            usdtToken.transferFrom(address(coreContract), msg.sender, totalPayout),
            "USDT transfer from core failed"
        );
        
        emit RewardClaimed(msg.sender, roundId, totalPayout, claimPhase);
    }
    
    /**
     * @dev Calculate payout for round claim
     * 
     * Logic:
     * - 0-180 days: No claims allowed (returns 0)
     * - 180-365 days: Can claim 50% reward if not yet claimed
     * - 365+ days: Full redemption (principal + any remaining rewards)
     */
    function _calculateRoundPayout(uint256[] memory tokenIds) 
        internal 
        view 
        returns (uint256 totalPayout, uint256 claimPhase) 
    {
        address sender = msg.sender;
        uint256 currentTime = block.timestamp;
        uint256 maxPhase = 0; // Track the highest applicable phase

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            // Check for duplicates - prevent double-claiming if same token ID appears twice
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenIds[j] != tokenId, "Duplicate token ID in claim array");
            }
            
            // Check ownership
            if (dzNFT.ownerOf(tokenId) != sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenId);
            
            // Skip if already fully redeemed
            if (investment.redeemed) continue;
            
            uint256 closeDateInvestment = investment.closeDateInvestment;
            
            // Skip if claim period hasn't started
            if (currentTime <= closeDateInvestment) continue;
            
            uint256 timeSinceCloseDate = currentTime - closeDateInvestment;
            
            // Skip if less than 180 days
            if (timeSinceCloseDate < FIRST_CLAIM_DAYS) continue;
            
            // Calculate principal and full reward
            uint256 principal = investment.tokenPrice * investment.totalTokenOpenInvestment;
            uint256 fullRewardAmount = (principal * investment.rewardPercentage) / 100;
            
            // Determine which phase this token is in and add payout
            if (timeSinceCloseDate >= FULL_CLAIM_DAYS) {
                // Phase 2: Full redemption (365+ days)
                if (investment.rewardClaimed) {
                    // Already claimed 50%, now claim remaining 50% + principal
                    totalPayout += principal + (fullRewardAmount / 2);
                } else {
                    // Never claimed before, now claim full reward + principal
                    totalPayout += principal + fullRewardAmount;
                }
                maxPhase = 2;
            } else if (timeSinceCloseDate >= FIRST_CLAIM_DAYS && !investment.rewardClaimed) {
                // Phase 1: First reward claim (180-365 days)
                totalPayout += (fullRewardAmount / 2);
                if (maxPhase < 1) maxPhase = 1;
            }
            // If already claimed reward and not yet 365 days, nothing to claim
        }
        
        return (totalPayout, maxPhase);
    }
    
    /**
     * @dev Process round claims and update NFT states
     */
    function _processRoundClaims(uint256[] memory tokenIds) internal {
        address sender = msg.sender;
        uint256 currentTime = block.timestamp;
        require(tokenIds.length > 0, "Token IDs array cannot be empty");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(tokenId > 0, "Invalid token ID");
            
            // Check for duplicates - prevent double processing if same token ID appears twice
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenIds[j] != tokenId, "Duplicate token ID in process array");
            }
            
            // Check ownership
            if (dzNFT.ownerOf(tokenId) != sender) continue;
            
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenId);
            
            // Skip if already redeemed
            if (investment.redeemed) continue;
            
            uint256 closeDateInvestment = investment.closeDateInvestment;
            
            // Skip if not eligible
            if (currentTime <= closeDateInvestment) continue;
            
            uint256 timeSinceCloseDate = currentTime - closeDateInvestment;
            
            // Skip if less than 180 days
            if (timeSinceCloseDate < FIRST_CLAIM_DAYS) continue;
            
            if (timeSinceCloseDate >= FULL_CLAIM_DAYS) {
                // Phase 2: Full redemption - mark as redeemed and unlock transfer
                dzNFT.markAsRedeemed(tokenId);
                dzNFT.unlockTransfer(tokenId);
            } else if (timeSinceCloseDate >= FIRST_CLAIM_DAYS && !investment.rewardClaimed) {
                // Phase 1: Mark reward as claimed (lock transfers until phase 2)
                dzNFT.markRewardClaimed(tokenId);
            }
        }
    }
    
    /**
     * @dev Get claimable reward information for a user in a round
     */
    function getClaimableReward(uint256 roundId) 
        external 
        view 
        returns (uint256 claimableAmount, uint256 claimPhase) 
    {
        uint256[] memory userTokenIds = dzNFT.getUserNFTsByRound(msg.sender, roundId);
        
        if (userTokenIds.length == 0) {
            return (0, 0);
        }
        
        return _calculateRoundPayout(userTokenIds);
    }
}
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
 */
contract FundRaisingClaims is Ownable, ReentrancyGuard {
    FundRaisingCore public immutable coreContract;
    DZNFT public immutable dzNFT;
    IERC20 public immutable usdtToken;
    
    // Constants
    uint256 public constant MAX_BATCH_CLAIM = 50;
    
    // Events
    event RewardClaimed(address indexed investor, uint256 indexed roundId, uint256 rewardAmount);
    
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
     */
    function claimRewardRound(uint256 roundId, uint256[] memory tokenIds) 
        external 
        nonReentrant 
    {
        require(tokenIds.length > 0, "No token IDs provided");
        require(tokenIds.length <= MAX_BATCH_CLAIM, "Too many tokens to claim at once");
        
        // Get round info from core contract
        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 closeDateInvestment,
            uint256 endDateInvestment,
            bool isActive,
            bool exists,
            ,
        ) = coreContract.investmentRounds(roundId);
        
        require(exists, "Round does not exist");
        require(isActive, "Round is not active");
        require(block.timestamp > closeDateInvestment, "Reward claiming not yet available");
        
        uint256 totalRewardAmount = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            // Verify ownership
            require(dzNFT.ownerOf(tokenId) == msg.sender, "Not token owner");
            
            // Get NFT details
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenId);
            
            require(investment.roundId == roundId, "Token not from this round");
            require(!investment.rewardClaimed, "Reward already claimed for this token");
            require(block.timestamp >= investment.closeDateInvestment, "Claim period not started");
            
            // Calculate reward
            uint256 rewardAmount = _calculateRoundPayout(
                roundId,
                investment.tokenPrice,
                investment.rewardPercentage,
                investment.totalTokenOpenInvestment,
                investment.closeDateInvestment,
                investment.endDateInvestment
            );
            
            if (rewardAmount > 0) {
                totalRewardAmount += rewardAmount;
                
                // Mark as claimed in NFT
                dzNFT.markRewardClaimed(tokenId);
                
                // Update core contract user claimed rewards
                coreContract.updateUserClaimedRewards(msg.sender, roundId, rewardAmount);
            }
        }
        
        if (totalRewardAmount > 0) {
            // Request reward transfer from core contract
            coreContract.transferRewardToClaims(roundId, msg.sender, totalRewardAmount);
            
            // Transfer reward from this contract to user
            require(
                usdtToken.transfer(msg.sender, totalRewardAmount),
                "USDT transfer failed"
            );
            
            emit RewardClaimed(msg.sender, roundId, totalRewardAmount);
        }
    }
    
    /**
     * @dev Calculate payout for a round based on time elapsed
     */
    function _calculateRoundPayout(
        uint256 roundId,
        uint256 tokenPrice,
        uint256 rewardPercentage,
        uint256 totalTokenOpenInvestment,
        uint256 claimStartDate,
        uint256 claimEndDate
    ) internal view returns (uint256) {
        uint256 rewardPool = coreContract.roundRewardPool(roundId);
        uint256 totalNFTsInRound = coreContract.getRoundTokenCount(roundId);
        
        if (rewardPool == 0 || totalNFTsInRound == 0) {
            return 0;
        }
        
        uint256 timeElapsed = block.timestamp - claimStartDate;
        uint256 totalDuration = claimEndDate - claimStartDate;
        
        uint256 baseReward = (tokenPrice * rewardPercentage * totalTokenOpenInvestment) / 10000;
        uint256 poolShare = rewardPool / totalNFTsInRound;
        
        uint256 timeMultiplier;
        if (timeElapsed >= totalDuration) {
            timeMultiplier = 10000; // 100% after full duration
        } else if (timeElapsed >= totalDuration / 2) {
            timeMultiplier = 5000; // 50% after half duration
        } else {
            timeMultiplier = 0; // No reward before half duration
        }
        
        return (baseReward + poolShare) * timeMultiplier / 10000;
    }
    
    /**
     * @dev Get claimable reward amount for tokens
     */
    function getClaimableReward(uint256 roundId, uint256[] memory tokenIds) 
        external 
        view 
        returns (uint256 totalClaimable) 
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            
            // Get NFT details
            DZNFT.InvestmentData memory investment = dzNFT.getInvestmentData(tokenId);
            
            if (investment.roundId == roundId && !investment.rewardClaimed && block.timestamp >= investment.closeDateInvestment) {
                uint256 rewardAmount = _calculateRoundPayout(
                    roundId,
                    investment.tokenPrice,
                    investment.rewardPercentage,
                    investment.totalTokenOpenInvestment,
                    investment.closeDateInvestment,
                    investment.endDateInvestment
                );
                totalClaimable += rewardAmount;
            }
        }
        
        return totalClaimable;
    }
}
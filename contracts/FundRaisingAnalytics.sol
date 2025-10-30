// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FundRaisingCore.sol";

/**
 * @title FundRaisingAnalytics
 * @dev Analytics and view functions for investment rounds
 */
contract FundRaisingAnalytics {
    FundRaisingCore public immutable coreContract;
    
    // Struct for round information in Analytics contract
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
        uint8 status;
    }
    
    constructor(address _coreContract) {
        require(_coreContract != address(0), "Invalid core contract address");
        coreContract = FundRaisingCore(_coreContract);
    }
    
    /**
     * @dev Get investment round details
     */
    function getInvestmentRound(uint256 roundId) 
        external 
        view 
        returns (InvestmentRound memory round, bool enableClaimReward) 
    {
        // Get the raw tuple from core contract
        (
            uint256 _roundId,
            string memory _roundName,
            uint256 _tokenPrice,
            uint256 _rewardPercentage,
            uint256 _totalTokenOpenInvestment,
            uint256 _tokensSold,
            uint256 _closeDateInvestment,
            uint256 _endDateInvestment,
            bool _isActive,
            bool _exists,
            uint256 _createdAt,
            FundRaisingCore.Status _status
        ) = coreContract.investmentRounds(roundId);
        
        round = InvestmentRound(
            _roundId,
            _roundName,
            _tokenPrice,
            _rewardPercentage,
            _totalTokenOpenInvestment,
            _tokensSold,
            _closeDateInvestment,
            _endDateInvestment,
            _isActive,
            _exists,
            _createdAt,
            uint8(_status)  // Convert enum to uint8
        );
        
        enableClaimReward = (block.timestamp > _endDateInvestment && _isActive);
        
        return (round, enableClaimReward);
    }
    
    /**
     * @dev Get all token IDs for a specific round
     */
    function getRoundTokenIds(uint256 roundId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return coreContract.getRoundTokenIds(roundId);
    }
    
    /**
     * @dev Get all investments made by a user
     */
    function getUserInvestments(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return coreContract.getUserInvestments(user);
    }
    
 
    /**
     * @dev Get total count of rounds for pagination calculation
     */
    function getRoundsCount() 
        external 
        view 
        returns (uint256 totalRounds, uint256 activeRounds) 
    {
        totalRounds = coreContract.totalRoundsCreated();
        activeRounds = 0;
        
        for (uint256 i = 0; i < totalRounds; i++) {
            (,,,,,,,, bool isActive, bool exists,,) = coreContract.investmentRounds(i);
            if (exists && isActive) {
                activeRounds++;
            }
        }
        
        return (totalRounds, activeRounds);
    }
    
    function getInvestorSummary(address investor) 
        external 
        view 
        returns (
            uint256 totalTokensOwned,
            uint256[] memory nftTokenIds,
            uint256 totalInvestment,
            uint256 dividendsEarned,
            uint256[] memory activeRounds
        ) 
    {
        return coreContract.getInvestorSummary(investor);
    }
    
    /**
     * @dev Get investor rounds
     */
    function getInvestorRounds(address investor) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return coreContract.getInvestorRounds(investor);
    }
    
    /**
     * @dev Check if claim reward is enabled for a round
     */
    function isClaimRewardEnabled(uint256 roundId) 
        external 
        view 
        returns (bool) 
    {
        (,,,,,, uint256 endDateInvestment,, bool isActive,,,) = coreContract.investmentRounds(roundId);
        return (block.timestamp > endDateInvestment && isActive);
    }
}
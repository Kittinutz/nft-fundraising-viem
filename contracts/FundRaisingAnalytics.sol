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
    
   

    function getRoundsDetail(uint256[] memory roundIds) 
        external 
        view 
        returns (FundRaisingCore.InvestmentRound[] memory) 
    {
        return coreContract.getRoundsDetail(roundIds);
    }
    
    function getWalletTokensDetail(address investor) 
        external 
        view 
        returns (uint256[] memory tokenIds, DZNFT.InvestmentData[] memory nftsDetail) 
    {
        return coreContract.getWalletTokensDetail(investor);
    }

    
    function getInvestorRoundsDetail(address investor) 
        external 
        view 
        returns (FundRaisingCore.InvestmentRound[] memory) 
    {
        uint256[] memory roundIds = _getInvestorRounds(investor);
        return coreContract.getRoundsDetail(roundIds);
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
            uint256 dividendsEarned
        ) 
    {
        return coreContract.getInvestorSummary(investor);
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
    
    function getAllTokensOwnedBy(address investor) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return coreContract.getAllTokensOwnedBy(investor);
    }
    
    function _getInvestorRounds(address investor) 
        internal 
        view 
        returns (uint256[] memory roundIds) 
    {
        require(investor != address(0), "Invalid wallet address");
        uint256[] memory tokenIds = coreContract.getAllTokensOwnedBy(investor);
        if (tokenIds.length == 0) {
            return new uint256[](0);
        }
                uint256[] memory allRoundIds = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            allRoundIds[i] = coreContract.getInvestmentData(tokenIds[i]).roundId;
        }
         // Count unique round IDs
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < allRoundIds.length; i++) {
            bool isUnique = true;
            for (uint256 j = 0; j < i; j++) {
                if (allRoundIds[i] == allRoundIds[j]) {
                    isUnique = false;
                    break;
                }
            }
            if (isUnique) {
                uniqueCount++;
            }
        }
        
        // Collect unique round IDs
        roundIds = new uint256[](uniqueCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allRoundIds.length; i++) {
            bool isUnique = true;
            for (uint256 j = 0; j < i; j++) {
                if (allRoundIds[i] == allRoundIds[j]) {
                    isUnique = false;
                    break;
                }
            }
            if (isUnique) {
                roundIds[index] = allRoundIds[i];
                index++;
            }
        }
        
        return roundIds;
    }


    function getInvestorRounds(address investor) 
        external 
        view 
        returns (uint256[] memory roundIds) 
    {
        return _getInvestorRounds(investor);
    }

  
}
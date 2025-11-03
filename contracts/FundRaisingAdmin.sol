// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFundRaisingStorage.sol";
import "./FundRaisingCore.sol";

/**
 * @title FundRaisingAdmin
 * @dev Administrative functions for fund raising management
 */
contract FundRaisingAdmin is Ownable {
    FundRaisingCore public immutable coreContract;
    
    event EmergencyWithdrawal(uint256 amount, address recipient);
    event EmergencyRoundWithdrawal(uint256 indexed roundId, uint256 amount, address recipient);
    event StatusUpdated(uint256 indexed roundId, IFundRaisingStorage.Status status);
    
    constructor(address _coreContract) Ownable(msg.sender) {
        require(_coreContract != address(0), "Invalid core contract address");
        coreContract = FundRaisingCore(_coreContract);
    }
    
    /**
     * @dev Emergency withdraw USDT (only owner)
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(
            coreContract.usdtToken().balanceOf(address(coreContract)) >= amount,
            "Insufficient balance"
        );
        require(
            coreContract.emergencyTransferUSDT(owner(), amount),
            "USDT transfer failed"
        );
        
        emit EmergencyWithdrawal(amount, owner());
    }

    /**
     * @dev Emergency withdraw USDT from specific round (only owner)
     */
    function emergencyWithdrawFromRound(uint256 roundId, uint256 amount) 
        external 
        onlyOwner 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(
            coreContract.roundLedger(roundId) >= amount,
            "Insufficient round balance"
        );
        require(
            coreContract.usdtToken().balanceOf(address(coreContract)) >= amount,
            "Insufficient contract balance"
        );
        
        // Transfer USDT from core contract to owner
        require(
            coreContract.emergencyTransferUSDT(owner(), amount),
            "USDT transfer failed"
        );
        
        // Update core contract's round ledger
        coreContract.updateRoundLedger(roundId, amount, false);
        
        emit EmergencyRoundWithdrawal(roundId, amount, owner());
    }
    
   
    
    /**
     * @dev Update the status of a specific round
     */
    function updateStatus(uint256 roundId, IFundRaisingStorage.Status status) 
        external 
        onlyOwner 
    {
        // Note: This would need to be implemented in core contract
        // For now, this is a placeholder for the interface
        
        emit StatusUpdated(roundId, status);
    }
    
    /**
     * @dev Batch update round statuses
     */
    function batchUpdateStatus(
        uint256[] calldata roundIds, 
        IFundRaisingStorage.Status[] calldata statuses
    ) external onlyOwner {
        require(roundIds.length == statuses.length, "Array length mismatch");
        require(roundIds.length > 0, "Empty arrays");
        require(roundIds.length <= 50, "Too many rounds to update at once");
        
        for (uint256 i = 0; i < roundIds.length; i++) {
            emit StatusUpdated(roundIds[i], statuses[i]);
        }
    }
    
    /**
     * @dev Batch set round active status
     */
    function batchSetRoundActive(
        uint256[] calldata roundIds, 
        bool[] calldata activeStates
    ) external onlyOwner {
        require(roundIds.length == activeStates.length, "Array length mismatch");
        require(roundIds.length > 0, "Empty arrays");
        require(roundIds.length <= 50, "Too many rounds to update at once");
        
        for (uint256 i = 0; i < roundIds.length; i++) {
            uint256 roundId = roundIds[i];
            bool activeState = activeStates[i];
            
            // Call the core contract's function to set round active status
            // This would modify the core contract's state
            FundRaisingCore(coreContract).setRoundActive(roundId, activeState);
        }
    }
    
    /**
     * @dev Get admin statistics
     */
    function getAdminStats() 
        external 
        view 
        returns (
            uint256 totalRounds,
            uint256 totalUSDTRaised,
            uint256 contractBalance,
            address usdtTokenAddress
        ) 
    {
        totalRounds = coreContract.totalRoundsCreated();
        totalUSDTRaised = coreContract.totalUSDTRaised();
        contractBalance = coreContract.usdtToken().balanceOf(address(coreContract));
        usdtTokenAddress = address(coreContract.usdtToken());
        
        return (totalRounds, totalUSDTRaised, contractBalance, usdtTokenAddress);
    }
    
    /**
     * @dev Get round financial summary
     */
    function getRoundFinancialSummary(uint256 roundId) 
        external 
        view 
        returns (
            uint256 totalInvestment,
            uint256 rewardPool,
            uint256 remainingBalance,
            uint256 totalNFTs
        ) 
    {
        totalInvestment = coreContract.roundLedger(roundId);
        rewardPool = coreContract.roundRewardPool(roundId);
        remainingBalance = totalInvestment; // Simplified calculation
        totalNFTs = coreContract.getRoundTokenCount(roundId);
        
        return (totalInvestment, rewardPool, remainingBalance, totalNFTs);
    }
}
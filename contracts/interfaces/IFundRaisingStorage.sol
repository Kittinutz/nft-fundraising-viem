// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../DZNFT.sol";

/**
 * @title IFundRaisingStorage
 * @dev Shared storage interface for fund raising contracts
 */
interface IFundRaisingStorage {
    // Enums
    enum Status { OPEN, CLOSED, COMPLETED, WITHDRAW_FUND, DIVIDEND_PAID }
    
    // Structs
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
    function USDT_DECIMALS() external pure returns (uint256);
    function MAX_TOKENS_PER_INVESTMENT() external pure returns (uint256);
    function MAX_BATCH_CLAIM() external pure returns (uint256);
    
    // Core contract references
    function dzNFT() external view returns (DZNFT);
    function usdtToken() external view returns (IERC20);
    
    // Events
    event RoundStatusChanged(uint256 indexed roundId, bool isActive);
    event EarlyRewardClaimed(uint256 indexed tokenId, address indexed investor, uint256 rewardAmount);
    event USDTTokenUpdated(address indexed oldToken, address indexed newToken);
    event RoundFunded(uint256 indexed roundId, uint256 amount);
    event RewardAdded(uint256 indexed roundId, uint256 amount, uint256 totalPoolAmount);
}
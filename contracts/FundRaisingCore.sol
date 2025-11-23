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
    address public authorizedClaimsContract;
    
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
    uint256 public constant USDT_DECIMALS = 6;
    uint256 public constant MAX_TOKENS_PER_INVESTMENT = 50;
    // Storage
    mapping(uint256 => InvestmentRound) public investmentRounds;
    mapping(uint256 => uint256[]) public roundTokenIds;
    mapping(uint256 => uint256) public roundLedger;
    mapping(uint256 => uint256) public roundRewardPool;
    mapping(uint256 => uint256) public roundInvestedAmount;

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
    event AuthorizedClaimsContractUpdated(address indexed oldContract, address indexed newContract);
    event EmergencyRoundWithdrawal( uint256 roundId, uint256 amount, address recipient);
    // Modifiers
    modifier onlyAuthorizedClaimsContract() {
        require(msg.sender == authorizedClaimsContract, "Only authorized claims contract can call this");
        _;
    }
    
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
        require(block.timestamp <= round.closeDateInvestment, "Investment period has ended");
        // ✅ SECURITY: Check for overflow before multiplication
        require(tokenAmount <= type(uint256).max / round.tokenPrice, "Calculation overflow risk");
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
                round.closeDateInvestment,
                round.endDateInvestment
            );
        }
        
        // Update storage
        uint256[] storage roundTokens = roundTokenIds[roundId];
        
        
        for(uint256 i = 0; i < tokenAmount; i++){
            roundTokens.push(tokenIds[i]);
        }
        
    
        // Update round data
        round.tokensSold += tokenAmount;
        roundLedger[roundId] += usdtAmount;
        roundInvestedAmount[roundId] += usdtAmount;
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
        investmentRounds[roundId].status = Status.DIVIDEND_PAID;

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

    function updateStatus(uint256 roundId, Status status) 
        external 
        onlyOwner 
        roundExists(roundId) 
    {
        investmentRounds[roundId].status = status;
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
     * @dev Update user claimed rewards (called by claims contract only)
     */
    function updateUserClaimedRewards(address user, uint256 roundId, uint256 amount) 
        external 
        onlyOwner
    {
        require(user != address(0), "Invalid user address");
        require(investmentRounds[roundId].exists, "Round does not exist");
        require(amount > 0, "Amount must be greater than 0");
        userClaimedRewards[user][roundId] += amount;
    }
    
    /**
     * @dev Update round ledger balance (only admin contract can call)
     * @param roundId The round ID
     * @param amount The amount to adjust
     * @param increase True to increase balance, false to decrease
     */
    function updateRoundLedger(uint256 roundId, uint256 amount, bool increase) 
        external 
        onlyAuthorizedClaimsContract
    {
        require(investmentRounds[roundId].exists, "Round does not exist");
        require(amount > 0, "Amount must be greater than 0");
        
        if (increase) {
            roundLedger[roundId] += amount;
        } else {
            require(roundLedger[roundId] >= amount, "Insufficient round ledger balance");
            roundLedger[roundId] -= amount;
        }
    }


    /**
     * @dev Emergency transfer USDT to recipient (only owner)
     * @param recipient The recipient address
     * @param amount The amount to transfer
     */
    function emergencyTransferUSDT(address recipient, uint256 amount) 
        external 
        onlyOwner
        returns (bool)
    {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(
            usdtToken.balanceOf(address(this)) >= amount,
            "Insufficient USDT balance"
        );
        return usdtToken.transfer(recipient, amount);
    }
    
    /**
     * @dev Emergency withdraw ALL USDT from specific round (only owner)
     */
    function emergencyWithdrawAllFromRound(uint256 roundId) 
        external 
        onlyOwner 
    {
        uint256 amount = roundLedger[roundId];
        require(amount > 0, "No balance to withdraw from this round");
        require(
            usdtToken.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );
        
        // Transfer all USDT from core contract to owner
        require(
            usdtToken.transfer(owner(), amount),
            "USDT transfer failed"
        );
        
        // Update core contract's round ledger to zero
        roundLedger[roundId] = 0;
        
        emit EmergencyRoundWithdrawal(roundId, amount, owner());
    }
    
    // Getter functions for arrays
    function getRoundTokenIds(uint256 roundId) external view returns (uint256[] memory) {
        return roundTokenIds[roundId];
    }
    
    function getRoundTokenCount(uint256 roundId) external view returns (uint256) {
        return roundTokenIds[roundId].length;
    }

    
    function _getRoundsDetail(uint256[] memory roundIds) 
        internal 
        view 
        returns (InvestmentRound[] memory) 
    {
        InvestmentRound[] memory rounds = new InvestmentRound[](roundIds.length);
        for (uint256 i = 0; i < roundIds.length; i++) {
            rounds[i] = investmentRounds[roundIds[i]];
        }
        return rounds;
    }

    function getRoundsDetail(uint256[] memory roundIds) 
        external 
        view 
        returns (InvestmentRound[] memory) 
    {
        return _getRoundsDetail(roundIds);
    }

    function getAllTokensOwnedBy(address investor) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return dzNFT.getAllTokensOwnedBy(investor);
    }
    
    function getWalletTokensDetail(address investor) 
        external 
        view 
        returns (uint256[] memory tokenIds, DZNFT.InvestmentData[] memory nftsDetail) 
    {
        return dzNFT.getWalletTokensDetail(investor);
    }

    /**
     * @dev Get total count of rounds for pagination calculation
     */
    function batchGetTokensDetail(uint256[] memory tokenIds) 
        external 
        view 
        returns (DZNFT.InvestmentData[] memory) 
    {
        return dzNFT.batchGetTokensDetail(tokenIds);
    }

    function getTokenDetail(uint256 tokenId) 
        external 
        view 
        returns (DZNFT.InvestmentData memory) 
        {
            // Get the data from DZNFT contract
            DZNFT.InvestmentData memory nftData = dzNFT.getTokenDetail(tokenId);
            
            // Convert to InvestmentNFTData struct
            return DZNFT.InvestmentData({
                tokenId: nftData.tokenId,
                roundId: nftData.roundId,
                tokenPrice: nftData.tokenPrice,
                rewardPercentage: nftData.rewardPercentage,
                purchaseTimestamp: nftData.purchaseTimestamp,
                closeDateInvestment: nftData.closeDateInvestment,
                endDateInvestment: nftData.endDateInvestment,
                originalBuyer: nftData.originalBuyer,
                redeemed: nftData.redeemed,
                rewardClaimed: nftData.rewardClaimed,
                transferLocked: nftData.transferLocked,
                metadata: nftData.metadata
            });
        }

    function getUSDTTokenAddress() external view returns (address) {
        return address(usdtToken);
    }
    
    function getContractUSDTBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }
    
    /**
     * @dev Transfer rewards from core contract to claimant via claims contract
     * Only the authorized claims contract can call this function
     * @param roundId The round ID
     * @param amount The amount to transfer
     */
    function transferRewardToClaims(uint256 roundId, uint256 amount) 
        external 
        onlyAuthorizedClaimsContract
    {
        require(amount > 0, "Invalid amount");
        require(investmentRounds[roundId].exists, "Round does not exist");
        require(roundLedger[roundId] >= amount, "Insufficient reward pool");
        
        // Deduct from round reward pool
        
        // Approve claims contract to transfer on behalf of core
        // This allows the claims contract to call transferFrom
        require(
            usdtToken.approve(msg.sender, amount),
            "Approve failed"
        );
    }
    
    /**
     * @dev Set the authorized claims contract address (only owner)
     */
    function setAuthorizedClaimsContract(address _claimsContract) external onlyOwner {
        require(_claimsContract != address(0), "Invalid claims contract address");
        address oldContract = authorizedClaimsContract;
        authorizedClaimsContract = _claimsContract;
        emit AuthorizedClaimsContractUpdated(oldContract, _claimsContract);
    }
    function getInvestmentData(uint256 tokenId) 
        external 
        view 
        returns (DZNFT.InvestmentData memory)
    {
        return dzNFT.getInvestmentData(tokenId);
    }
    function getExistsToken(uint256 tokenId) 
        external 
        view 
        returns (bool) 
    {
        return dzNFT.tokenExists(tokenId);
    }
}
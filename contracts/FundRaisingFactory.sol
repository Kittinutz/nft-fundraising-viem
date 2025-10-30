// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./FundRaisingCore.sol";
import "./FundRaisingAnalytics.sol";
import "./FundRaisingAdmin.sol";

/**
 * @title FundRaisingFactory
 * @dev Factory contract to deploy and manage fund raising contract suite
 */
contract FundRaisingFactory is Ownable {
    
    struct DeploymentInfo {
        address coreContract;
        address analyticsContract;
        address adminContract;
        address deployer;
        uint256 deployedAt;
        bool active;
    }
    
    mapping(address => DeploymentInfo) public deployments;
    address[] public allDeployments;
    
    event FundRaisingDeployed(
        address indexed deployer,
        address indexed coreContract,
        address analyticsContract,
        address adminContract,
        address dzNFT,
        address usdtToken
    );
    
    event DeploymentStatusChanged(address indexed coreContract, bool active);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Deploy complete fund raising contract suite
     */
    function deployFundRaising(
        address dzNFT, 
        address usdtToken
    ) external returns (
        address coreContract,
        address analyticsContract,
        address adminContract
    ) {
        require(dzNFT != address(0), "Invalid DZNFT address");
        require(usdtToken != address(0), "Invalid USDT address");
        
        // Deploy core contract
        FundRaisingCore core = new FundRaisingCore(dzNFT, usdtToken);
        coreContract = address(core);
        
        // Transfer ownership to the deployer
        core.transferOwnership(msg.sender);
        
        // Deploy analytics contract
        FundRaisingAnalytics analytics = new FundRaisingAnalytics(coreContract);
        analyticsContract = address(analytics);
        
        // Deploy admin contract
        FundRaisingAdmin admin = new FundRaisingAdmin(coreContract);
        adminContract = address(admin);
        
        // Store deployment info
        deployments[coreContract] = DeploymentInfo({
            coreContract: coreContract,
            analyticsContract: analyticsContract,
            adminContract: adminContract,
            deployer: msg.sender,
            deployedAt: block.timestamp,
            active: true
        });
        
        allDeployments.push(coreContract);
        
        emit FundRaisingDeployed(
            msg.sender,
            coreContract,
            analyticsContract,
            adminContract,
            dzNFT,
            usdtToken
        );
        
        return (coreContract, analyticsContract, adminContract);
    }
    
    /**
     * @dev Get deployment information
     */
    function getDeploymentInfo(address coreContract) 
        external 
        view 
        returns (DeploymentInfo memory) 
    {
        return deployments[coreContract];
    }
    
    /**
     * @dev Get all deployments by a specific deployer
     * REMOVED: Function too large for contract size limit
     * Use events or external indexing service instead
     */
    
    /**
     * @dev Get total number of deployments
     */
    function getTotalDeployments() external view returns (uint256) {
        return allDeployments.length;
    }
    
    /**
     * @dev Get active deployments count
     * REMOVED: Function too large for contract size limit
     * Use events or external indexing service instead
     */
    
    /**
     * @dev Set deployment status (factory owner only)
     */
    function setDeploymentStatus(address coreContract, bool active) 
        external 
        onlyOwner 
    {
        require(deployments[coreContract].coreContract != address(0), "Deployment not found");
        deployments[coreContract].active = active;
        emit DeploymentStatusChanged(coreContract, active);
    }
    
    /**
     * @dev Get deployment stats
     * REMOVED: Function too large for contract size limit
     * Use events or external indexing service instead
     */
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDT
 * @dev Mock USDT token for testing purposes
 * Simulates USDT with 6 decimals like the real token
 */
contract MockUSDT is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply 
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    // Mint function for testing
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    // Burn function for testing
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    // Faucet function for testing - gives 10,000 USDT to caller
    function faucet() external {
        _mint(msg.sender, 10000 * 10**_decimals);
    }
}
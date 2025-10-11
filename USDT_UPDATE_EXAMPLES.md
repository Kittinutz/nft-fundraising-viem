# USDT Token Update Examples

## Overview

The FundRaisingContractNFT contract now supports updating the USDT token address, providing flexibility for various scenarios.

## Basic Usage

### Check Current USDT Token

```solidity
address currentUSDT = fundRaisingContract.getUSDTTokenAddress();
console.log("Current USDT token:", currentUSDT);
```

### Update USDT Token (Owner Only)

```solidity
// Update to new USDT token
address newUSDTAddress = 0x123...; // New USDT contract address
fundRaisingContract.setUSDTToken(newUSDTAddress);

// Verify the update
address updatedUSDT = fundRaisingContract.getUSDTTokenAddress();
require(updatedUSDT == newUSDTAddress, "Update failed");
```

## Real-World Scenarios

### Scenario 1: Network Migration

When moving to a different network with different USDT addresses:

```solidity
// Original deployment on Ethereum Mainnet
// USDT: 0xdAC17F958D2ee523a2206206994597C13D831ec7

// Deploy on Polygon
// USDT: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F
fundRaisingContract.setUSDTToken(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
```

### Scenario 2: Token Upgrade

When USDT contract is upgraded:

```solidity
// Old USDT contract
address oldUSDT = 0xOldUSDTContract...;

// New upgraded USDT contract
address newUSDT = 0xNewUSDTContract...;

// Update to new contract
fundRaisingContract.setUSDTToken(newUSDT);

// Fund new contract with new USDT for redemptions
newUSDTContract.transfer(fundRaisingContract, redemptionAmount);
```

### Scenario 3: Multi-Stablecoin Support

Switch between different stablecoins:

```solidity
// Start with USDT
fundRaisingContract.setUSDTToken(USDTAddress);

// Switch to USDC
fundRaisingContract.setUSDTToken(USDCAddress);

// Switch to DAI
fundRaisingContract.setUSDTToken(DAIAddress);
```

## Important Considerations

### 1. Existing Investments

- Changing USDT token doesn't affect existing NFTs
- Existing investors will redeem using the NEW token address
- Ensure new token has sufficient balance for redemptions

### 2. Timing

```solidity
// Good practice: Update during maintenance window
// 1. Pause contract
fundRaisingContract.pause();

// 2. Update USDT token
fundRaisingContract.setUSDTToken(newTokenAddress);

// 3. Fund with new token
newToken.transfer(fundRaisingContract, requiredAmount);

// 4. Resume operations
fundRaisingContract.unpause();
```

### 3. Validation

The contract automatically validates:

- ✅ New address is not zero address
- ✅ New address is different from current address
- ✅ Only owner can call this function

## Error Handling

### Common Errors and Solutions

```solidity
// Error: "Invalid USDT token address"
// Solution: Don't use zero address
fundRaisingContract.setUSDTToken(address(0)); // ❌ Will fail

// Error: "Same USDT token address"
// Solution: Use a different address
address current = fundRaisingContract.getUSDTTokenAddress();
fundRaisingContract.setUSDTToken(current); // ❌ Will fail

// Success: Different valid address
fundRaisingContract.setUSDTToken(0x123...); // ✅ Will succeed
```

## Testing

Test the functionality:

```bash
npm run test:usdt-update
```

This test will:

1. Deploy two different USDT contracts
2. Initialize FundRaisingContractNFT with first USDT
3. Update to second USDT token
4. Verify validation works (same address, zero address)
5. Create investment round with new USDT token

## Events

Monitor USDT token updates:

```solidity
event USDTTokenUpdated(address indexed oldToken, address indexed newToken);

// Listen for events
fundRaisingContract.on("USDTTokenUpdated", (oldToken, newToken) => {
    console.log(`USDT token updated from ${oldToken} to ${newToken}`);
});
```

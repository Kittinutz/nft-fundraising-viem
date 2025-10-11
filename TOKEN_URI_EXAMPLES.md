# Token URI Examples

## Default Behavior

When the DZNFT contract is deployed, it has a default base URI: `https://api.dznft.com/metadata/`

### Example Token URIs:

- Token ID 0: `https://api.dznft.com/metadata/0.json`
- Token ID 1: `https://api.dznft.com/metadata/1.json`
- Token ID 123: `https://api.dznft.com/metadata/123.json`

## Setting Custom Base URI

Owner can update the base URI:

```solidity
// Set new base URI
dzNFT.setBaseURI("https://metadata.dznft.io/api/v1/");
```

After this change:

- Token ID 0: `https://metadata.dznft.io/api/v1/0.json`
- Token ID 1: `https://metadata.dznft.io/api/v1/1.json`

## Setting Individual Token URIs

Owner or executor can set custom URIs for specific tokens:

```solidity
// Set custom URI for token 0
dzNFT.setTokenURI(0, "https://special.metadata.com/rare-nft.json");
```

After this change:

- Token ID 0: `https://special.metadata.com/rare-nft.json` (custom URI)
- Token ID 1: `https://metadata.dznft.io/api/v1/1.json` (base URI + ID)

## Priority System

1. **Custom Token URI** (highest priority): If set, always returned
2. **Base URI + Token ID**: If no custom URI, returns `{baseURI}{tokenId}.json`
3. **Empty String**: If no base URI set and no custom URI

## Typical JSON Metadata Structure

The URI should point to a JSON file with metadata:

```json
{
  "name": "DZ Investment NFT #1",
  "description": "Investment Round 1 - Tech Startup Funding",
  "image": "https://images.dznft.com/1.png",
  "attributes": [
    {
      "trait_type": "Round ID",
      "value": 1
    },
    {
      "trait_type": "Price per Token",
      "value": "2 USDT"
    },
    {
      "trait_type": "Reward Percentage",
      "value": "10%"
    },
    {
      "trait_type": "Investment Amount",
      "value": "100 Tokens"
    },
    {
      "trait_type": "Status",
      "value": "Active"
    },
    {
      "trait_type": "Maturity Date",
      "value": "2025-11-10"
    }
  ]
}
```

## Testing

Use the test script to see token URI functionality in action:

```bash
npm run test:token-uri
```

This will demonstrate:

- Default base URI
- Setting custom base URI
- Setting individual token URIs
- Priority system working correctly

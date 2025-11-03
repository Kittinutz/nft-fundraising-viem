import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import hardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

const config: HardhatUserConfig = {
  plugins: [
    hardhatToolboxViemPlugin,
    hardhatNetworkHelpersPlugin,
    hardhatVerify,
  ],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200, // Arbitrum benefits from optimization
          },
          viaIR: true,

          // Arbitrum uses EVM version compatible settings
          evmVersion: "paris", // Recommended for Arbitrum compatibility
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200, // Arbitrum benefits from optimization
          },
          viaIR: true,
          // Arbitrum uses EVM version compatible settings
          evmVersion: "paris", // Recommended for Arbitrum compatibility
        },
      },
    },
  },
  verify: {
    blockscout: {
      enabled: false,
    },
  },
  networks: {
    localhost: {
      type: "edr-simulated",
      chainType: "op",
    },
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
};

export default config;

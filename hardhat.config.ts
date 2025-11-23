import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import hardhatNetworkHelpersPlugin from "@nomicfoundation/hardhat-network-helpers";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import dotenv from "dotenv";
import { baseSepolia } from "viem/chains";

dotenv.config();

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
    privateCloud: {
      type: "http",
      url: "https://rpc.dzabattoir.com",
    },
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
    baseSepolia: {
      type: "http",
      url: "https://sepolia.base.org",
      accounts: [process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY : ""],
    },
  },
};

export default config;

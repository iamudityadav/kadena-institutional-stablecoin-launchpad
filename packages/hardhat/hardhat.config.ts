import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@kadena/hardhat-chainweb";
import "@kadena/hardhat-kadena-create2";
import "hardhat-deploy-ethers";
import "dotenv/config";

const deployerKey =
  process.env.__RUNTIME_DEPLOYER_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
const accounts = deployerKey ? [deployerKey] : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 1000 },
      evmVersion: "paris", // recommended for 0.8.20
    },
  },
  

  chainweb: {
    hardhat: {
      chains: 5, // spin up 5 local chainweb nodes
      logging: "info",
    },
    testnet: {
      type: "external",
      chains: 5,
      accounts,
      chainIdOffset: 5920,
      chainwebChainIdOffset: 20,
      externalHostUrl: "https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet",
      etherscan: {
        apiKey: "abc", // dummy for Blockscout
        apiURLTemplate:
          "https://chain-{cid}.evm-testnet-blockscout.chainweb.com/api/",
        browserURLTemplate:
          "https://chain-{cid}.evm-testnet-blockscout.chainweb.com",
      },
    },
  },

  networks: {
    // Local Hardhat Chainweb devnet
    "chainweb-hardhat-0": {
      url: "http://127.0.0.1:8545/chain/0/evm/rpc",
      accounts,
      chainId: 626000,
    },
    "chainweb-hardhat-1": {
      url: "http://127.0.0.1:8545/chain/1/evm/rpc",
      accounts,
      chainId: 626001,
    },
    "chainweb-hardhat-2": {
      url: "http://127.0.0.1:8545/chain/2/evm/rpc",
      accounts,
      chainId: 626002,
    },
    "chainweb-hardhat-3": {
      url: "http://127.0.0.1:8545/chain/3/evm/rpc",
      accounts,
      chainId: 626003,
    },
    "chainweb-hardhat-4": {
      url: "http://127.0.0.1:8545/chain/4/evm/rpc",
      accounts,
      chainId: 626004,
    },

    // ✅ Kadena Chainweb EVM Testnet (Chain 20)
    kadenaTestnet20: {
      url: "https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet/chain/20/evm/rpc",
      accounts,
      chainId: 5920,
    },
  },sourcify: {
    enabled: true
  }
};

export default config;

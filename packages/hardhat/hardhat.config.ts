import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@kadena/hardhat-chainweb";
import "@kadena/hardhat-kadena-create2";
import "hardhat-deploy-ethers";
import "dotenv/config";

const deployerKey = process.env.__RUNTIME_DEPLOYER_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
const accounts = deployerKey ? [deployerKey] : [];

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 1000 },
      evmVersion: "prague",
    },
  },

  chainweb: {
    hardhat: {
      chains: 5, // spin up 2 local chainweb nodes
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
        apiURLTemplate: "https://chain-{cid}.evm-testnet-blockscout.chainweb.com/api/",
        browserURLTemplate: "https://chain-{cid}.evm-testnet-blockscout.chainweb.com",
      },
    },
  },
  networks: {
    "chainweb-hardhat-0": {
      url: "http://127.0.0.1:8545/chain/0/evm/rpc",
      accounts,
      chainId: 626000, // match the actual chainweb-hardhat chain id
    },
    "chainweb-hardhat-1": {
      url: "http://127.0.0.1:8545/chain/1/evm/rpc",
      accounts,
      chainId: 626001, // chain 1 will be 626001
    },
    "chainweb-hardhat-2": {
      url: "http://127.0.0.1:8545/chain/1/evm/rpc",
      accounts,
      chainId: 626002, // chain 1 will be 626001
    },
    "chainweb-hardhat-3": {
      url: "http://127.0.0.1:8545/chain/1/evm/rpc",
      accounts,
      chainId: 626003, // chain 1 will be 626001
    },
    "chainweb-hardhat-4": {
      url: "http://127.0.0.1:8545/chain/1/evm/rpc",
      accounts,
      chainId: 626004, // chain 1 will be 626001
    },
  },
};

export default config;

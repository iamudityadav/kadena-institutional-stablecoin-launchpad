import { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  // Load from .env or fallback
  const tokenName = process.env.STABLECOIN_NAME || "MyUSD";
  const tokenSymbol = process.env.STABLECOIN_SYMBOL || "MUSD";
  const admin = process.env.ADMIN_ADDRESS || deployer.address;
  const hsmSigner = process.env.ORACLE_SIGNER || deployer.address;

  // Deploy KYCRegistry
  // console.log("➡️ Deploying KYCRegistry...");
  // const KYCRegistry = await ethers.getContractFactory("KYCRegistry");
  // const kycRegistry = await KYCRegistry.deploy(admin);
  // await kycRegistry.waitForDeployment();
  // const kycAddress = await kycRegistry.getAddress();
  // console.log("✅ KYCRegistry deployed to:", kycAddress);

  // Deploy StableCoin
  console.log("➡️ Deploying StableCoin...");
  const StableCoin = await ethers.getContractFactory("Stablecoin");
  const stablecoin = await StableCoin.deploy(tokenName, tokenSymbol, admin, hsmSigner);
  await stablecoin.waitForDeployment();
  const stablecoinAddress = await stablecoin.getAddress();
  console.log("✅ StableCoin deployed to:", stablecoinAddress);

  // Summary
  console.log("\n🚀 Deployment Summary:");
  console.log("Deployer:", deployer.address);
  // console.log("StableCoin:", stablecoinAddress);
  // console.log("KYCRegistry:", kycAddress);
}

main().catch(error => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});

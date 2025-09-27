// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/*
Stablecoin.sol

Features:
- ERC20 token
- AccessControl roles (ADMIN/ISSUER/ORACLE/BRIDGE/PAUSER)
- KYCRegistry integration (pluggable)
- ReserveCapOracle integration (pluggable)
- EIP-712-based approvals (mintWithApproval, finalizeRedeem) signed by ORACLE_ROLE (HSM)
- Cross-chain send (transferCrossChain) event + resumeCrossChain (BRIDGE_ROLE)
- Freeze / blacklist, pause/unpause, nonces & expiry
- Events for audit logs

Note: For Kadena native cross-chain proofs, replace BRIDGE_ROLE gating with on-chain SPV/proof verification
      (or call Kadena EVM proof verify API once available). For hackathon, BRIDGE_ROLE works as a demo gate.
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IKYCRegistry {
    function isWhitelisted(address who) external view returns (bool);
}

interface IReserveCapOracle {
    function currentCap() external view returns (uint256);
}

contract Stablecoin is ERC20, AccessControl, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;

    // Roles
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant ISSUER_ROLE  = keccak256("ISSUER_ROLE");  // optional direct issuer
    bytes32 public constant ORACLE_ROLE  = keccak256("ORACLE_ROLE");  // HSM signer
    bytes32 public constant BRIDGE_ROLE  = keccak256("BRIDGE_ROLE");  // bridge/harmonizer/resumer
    bytes32 public constant PAUSER_ROLE  = keccak256("PAUSER_ROLE");

    // External modules
    IKYCRegistry public kyc;
    IReserveCapOracle public reserveOracle; // returns allowed max supply

    // EIP-712
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant MINT_TYPEHASH = keccak256("MintApproval(address to,uint256 amount,uint256 nonce,uint64 expiry,uint256 chainId,bytes32 requestId)");
    bytes32 public constant REDEEM_TYPEHASH = keccak256("RedeemFinalize(bytes32 requestId,address account,uint256 amount,uint64 expiry,string bankRef)");

    // Nonce tracking for replay protection
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public redeemProcessed; // requestId => processed

    // Frozen accounts
    mapping(address => bool) public frozen;

    // Events
    event AccountFrozen(address indexed account, bool frozen);
    event MintWithApproval(address indexed to, uint256 amount, uint256 nonce, bytes32 requestId);
    event RedeemFinalized(bytes32 indexed requestId, address indexed account, uint256 amount, string bankRef);
    event CrossChainSent(address indexed from, address indexed to, uint256 amount, uint256 targetChainId, bytes32 indexed crossId);
    event CrossChainReceived(address indexed to, uint256 amount, uint256 sourceChainId, bytes32 indexed crossId);

    // Cross-chain pending (optional demo storage)
    // mapping(bytes32 => bool) public crossCompleted;

    constructor(
        string memory name_,
        string memory symbol_,
        address admin,
        address kycRegistry,
        address reserveOracleAddr,
        address oracleSigner
    ) ERC20(name_, symbol_) {
        // roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _setRoleAdmin(ISSUER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ORACLE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BRIDGE_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        // assign ORACLE_ROLE to oracleSigner (HSM's public EOA or multisig address)
        _grantRole(ORACLE_ROLE, oracleSigner);

        // tie KYC & reserve oracles
        kyc = IKYCRegistry(kycRegistry);
        reserveOracle = IReserveCapOracle(reserveOracleAddr);

        // EIP-712 domain
        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name_)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    // ---------------------------
    // Modifiers
    // ---------------------------
    modifier notFrozen(address acct) {
        require(!frozen[acct], "account frozen");
        _;
    }

    // ---------------------------
    // Admin functions
    // ---------------------------
    function setKYCRegistry(address _kyc) external onlyRole(ADMIN_ROLE) {
        kyc = IKYCRegistry(_kyc);
    }

    function setReserveOracle(address _reserve) external onlyRole(ADMIN_ROLE) {
        reserveOracle = IReserveCapOracle(_reserve);
    }

    function freezeAccount(address acct, bool isFrozen) external onlyRole(ADMIN_ROLE) {
        frozen[acct] = isFrozen;
        emit AccountFrozen(acct, isFrozen);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Governance: emergency mint/burn (admin)
    function adminMint(address to, uint256 amount) external onlyRole(ADMIN_ROLE) {
        // Admin action; still check cap & KYC if desired
        _mint(to, amount);
    }

    function adminBurn(address from, uint256 amount) external onlyRole(ADMIN_ROLE) {
        _burn(from, amount);
    }

    // ---------------------------
    // ERC20 overrides & safety
    // ---------------------------
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._update(from, to, amount);
    }


    // ---------------------------
    // EIP-712 helpers
    // ---------------------------
    function _hashMintApproval(
        address to,
        uint256 amount,
        uint256 nonceVal,
        uint64 expiry,
        uint256 chainId,
        bytes32 requestId
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            MINT_TYPEHASH,
            to,
            amount,
            nonceVal,
            expiry,
            chainId,
            requestId
        ));
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _hashRedeemFinalize(
        bytes32 requestId,
        address account,
        uint256 amount,
        uint64 expiry,
        string memory bankRef
    ) internal view returns (bytes32) {
        bytes32 bankHash = keccak256(bytes(bankRef));
        bytes32 structHash = keccak256(abi.encode(
            REDEEM_TYPEHASH,
            requestId,
            account,
            amount,
            expiry,
            bankHash
        ));
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    // ---------------------------
    // Mint with oracle approval (HSM/MPC)
    // ---------------------------
    // ORACLE signs a MintApproval EIP-712. Orchestrator obtains signature and relayer calls this.
    function mintWithApproval(
        address to,
        uint256 amount,
        uint256 nonceVal,
        uint64 expiry,
        uint256 chainId,
        bytes32 requestId,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(block.timestamp <= expiry, "expired approval");
        require(nonces[to] == nonceVal, "invalid nonce");

        // verify KYC
        require(kyc.isWhitelisted(to), "beneficiary not KYC'ed");

        // check reserve cap
        uint256 cap = reserveOracle.currentCap();
        require(totalSupply() + amount <= cap, "cap exceeded");

        // recover signer
        bytes32 digest = _hashMintApproval(to, amount, nonceVal, expiry, chainId, requestId);
        address signer = digest.recover(signature);
        require(hasRole(ORACLE_ROLE, signer), "invalid oracle signature");

        // consume nonce
        nonces[to] = nonceVal + 1;

        // mint
        _mint(to, amount);

        emit MintWithApproval(to, amount, nonceVal, requestId);
    }

    // ---------------------------
    // Redeem request flow (on-chain request: user expresses intent)
    // ---------------------------
    // Application may implement a separate on-chain request table if needed.
    // For demo simplicity: user calls `requestRedeem` which emits event; off-chain bank processes; ORACLE signs finalize.
    event RedeemRequested(bytes32 indexed requestId, address indexed account, uint256 amount);

    function requestRedeem(bytes32 requestId, uint256 amount) external whenNotPaused notFrozen(msg.sender) {
        require(balanceOf(msg.sender) >= amount, "insufficient balance");
        // mark pending via event; off-chain orchestrator picks this up
        emit RedeemRequested(requestId, msg.sender, amount);
    }

    // finalize redeem: ORACLE signs the finalize payload; relayer submits finalize to burn tokens
    function finalizeRedeem(
        bytes32 requestId,
        address account,
        uint256 amount,
        uint64 expiry,
        string calldata bankRef,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        require(block.timestamp <= expiry, "expired finalize");
        require(!redeemProcessed[requestId], "already processed");

        // verify signature
        bytes32 digest = _hashRedeemFinalize(requestId, account, amount, expiry, bankRef);
        address signer = digest.recover(signature);
        require(hasRole(ORACLE_ROLE, signer), "invalid oracle signature");

        // burn (issuer/contract burns from account; ensure account had allowed or direct burn capability)
        require(balanceOf(account) >= amount, "insufficient on-chain balance");
        _burn(account, amount);

        redeemProcessed[requestId] = true;
        emit RedeemFinalized(requestId, account, amount, bankRef);
    }

    // ---------------------------
    // Cross-chain send (simple pattern)
    // ---------------------------
    // This emits an event that a bridge/harmonizer picks up; the continuation/mint on target chain must be authorized.
    // crossId is deterministic: keccak(from,to,amount,targetChain,nonce,timestamp)
    function transferCrossChain(address to, uint256 amount, uint256 targetChainId) external whenNotPaused notFrozen(msg.sender) nonReentrant {
        require(balanceOf(msg.sender) >= amount, "insufficient balance");
        // debit locally
        _burn(msg.sender, amount); // burn on source chain to avoid double supply; target will mint via resumeCrossChain
        bytes32 crossId = keccak256(abi.encodePacked(msg.sender, to, amount, targetChainId, block.number, block.timestamp));
        emit CrossChainSent(msg.sender, to, amount, targetChainId, crossId);
        // relayer / harmonizer picks up the event, fetches proof, and calls resumeCrossChain on target chain
    }

    // resumeCrossChain should be called on TARGET chain by authorized bridge/harmonizer after proving source event inclusion.
    // For demo we gate it with BRIDGE_ROLE. In production replace with Kadena SPV/proof verification logic.
    function resumeCrossChain(address to, uint256 amount, uint256 sourceChainId, bytes32 crossId) external whenNotPaused onlyRole(BRIDGE_ROLE) nonReentrant {
        // optionally check crossId uniqueness if you want
        // mint on target chain
        _mint(to, amount);
        emit CrossChainReceived(to, amount, sourceChainId, crossId);
    }

    // ---------------------------
    // Utilities
    // ---------------------------
    function domainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    // expose nonce
    function getNonce(address who) external view returns (uint256) {
        return nonces[who];
    }

    // sanity: read reserve cap
    function getReserveCap() external view returns (uint256) {
        return reserveOracle.currentCap();
    }
}

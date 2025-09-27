// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/*
- EIP-712 approvals for mint & redeem
- mintProcessed dedupe by requestId
- _update enforces pause & frozen accounts
- relayer controls mintWithApproval execution
*/

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Stablecoin is ERC20, Ownable2Step, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;

    // EIP-712
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant MINT_TYPEHASH = keccak256(
        "MintApproval(address to,uint256 amount,uint256 nonce,uint64 expiry,uint256 chainId,bytes32 requestId)"
    );

    // Nonce tracking for replay protection
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public mintProcessed; // mint requestId dedupe
    mapping(address => bool) public hsmSigners;

    // Frozen accounts
    mapping(address => bool) public frozen;

    // Relayer (only this address can call mintWithApproval)
    address public relayer;

    // Events
    event AccountFrozen(address indexed account, bool frozen);
    event MintWithApproval(address indexed to, uint256 amount, uint256 nonce, bytes32 requestId);
    event RedeemRequested(address indexed account, uint256 amount);
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);

    constructor(
        string memory name_,
        string memory symbol_,
        address hsmSigner,
        address initialRelayer
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        require(initialRelayer != address(0), "relayer required");

        // EIP-712 domain
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name_)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );

        // HSM assignment
        if (hsmSigner != address(0)) {
            hsmSigners[hsmSigner] = true;
        }

        // Relayer assignment
        relayer = initialRelayer;
    }

    // ---------------------------
    // Modifiers
    // ---------------------------
    modifier notFrozen(address acct) {
        require(!frozen[acct], "account frozen");
        _;
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "only relayer");
        _;
    }

    // ---------------------------
    // Admin / Owner functions
    // ---------------------------
    function freezeAccount(address acct, bool isFrozen) external onlyOwner {
        frozen[acct] = isFrozen;
        emit AccountFrozen(acct, isFrozen);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updateRelayer(address newRelayer) external onlyOwner {
        require(newRelayer != address(0), "invalid relayer");
        address oldRelayer = relayer;
        relayer = newRelayer;

        emit RelayerUpdated(oldRelayer, newRelayer);
    }

    // ---------------------------
    // HSM role helpers
    // ---------------------------
    function grantHSM(address signer) external onlyOwner {
        hsmSigners[signer] = true;
    }

    function revokeHSM(address signer) external onlyOwner {
        hsmSigners[signer] = false;
    }

    // ---------------------------
    // ERC20 hooks & safety
    // ---------------------------
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);
        require(!paused(), "token paused");
        if (from != address(0)) {
            require(!frozen[from], "from frozen");
        }
        if (to != address(0)) {
            require(!frozen[to], "to frozen");
        }
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
        bytes32 structHash = keccak256(
            abi.encode(MINT_TYPEHASH, to, amount, nonceVal, expiry, chainId, requestId)
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    // ---------------------------
    // Mint with HSM approval
    // ---------------------------
    function mintWithApproval(
        address to,
        uint256 amount,
        uint256 nonceVal,
        uint64 expiry,
        uint256 chainId,
        bytes32 requestId,
        bytes calldata signature
    ) external whenNotPaused nonReentrant onlyRelayer {
        require(block.timestamp <= expiry, "expired approval");
        require(nonces[to] == nonceVal, "invalid nonce");
        require(!mintProcessed[requestId], "mint already processed");

        bytes32 digest = _hashMintApproval(to, amount, nonceVal, expiry, chainId, requestId);
        address signer = digest.recover(signature);
        require(hsmSigners[signer], "invalid HSM signature");

        nonces[to] = nonceVal + 1;
        mintProcessed[requestId] = true;

        _mint(to, amount);

        emit MintWithApproval(to, amount, nonceVal, requestId);
    }

    // ---------------------------
    // Redeem request flow
    // ---------------------------
    function requestRedeem(uint256 amount) external whenNotPaused notFrozen(msg.sender) {
        require(balanceOf(msg.sender) >= amount, "insufficient balance");

        // burn immediately
        _burn(msg.sender, amount);
        emit RedeemRequested(msg.sender, amount);
    }
}

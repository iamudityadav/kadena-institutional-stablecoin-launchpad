// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract KYCRegistry {
    address public admin;
    mapping(address => bool) private _isKYC;

    // Events
    event KYCApproved(address indexed user, uint256 timestamp, string name, string symbol);
    event KYCRevoked(address indexed user, uint256 timestamp);
    event MintRequested(address indexed beneficiary, uint256 amount);

    constructor(address _admin) {
        require(_admin != address(0), "invalid admin");
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    // -------------------------------
    // KYC Management
    // -------------------------------
    function setKYC(address user, string memory name, string memory symbol) external onlyAdmin {
        _isKYC[user] = true;
        emit KYCApproved(user, block.timestamp, name, symbol);
    }

    function revokeKYC(address user) external onlyAdmin {
        _isKYC[user] = false;
        emit KYCRevoked(user, block.timestamp);
    }

    function isKYC(address user) external view returns (bool) {
        return _isKYC[user];
    }

    // -------------------------------
    // Mint lifecycle
    // -------------------------------
    function submitMintRequest(address beneficiary, uint256 amount) external {
        require(beneficiary != address(0), "invalid beneficiary");
        require(_isKYC[msg.sender], "not KYC'ed");

        emit MintRequested(beneficiary, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract KYCRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    mapping(address => bool) private _isKYC;

    event KYCSet(address indexed user, bool approved);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    function setKYC(address user, bool approved) external onlyRole(REGISTRAR_ROLE) {
        _isKYC[user] = approved;
        emit KYCSet(user, approved);
    }

    function isKYC(address user) external view returns (bool) {
        return _isKYC[user];
    }
}

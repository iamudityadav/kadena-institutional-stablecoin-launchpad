// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ReserveCapOracle is Ownable {
    uint256 private _cap;

    event CapUpdated(uint256 newCap);

    constructor(uint256 initialCap, address _initialOwner) Ownable(_initialOwner) {
        _cap = initialCap;
    }

    function setCap(uint256 newCap) external onlyOwner {
        _cap = newCap;
        emit CapUpdated(newCap);
    }

    function getCap() external view returns (uint256) {
        return _cap;
    }
}

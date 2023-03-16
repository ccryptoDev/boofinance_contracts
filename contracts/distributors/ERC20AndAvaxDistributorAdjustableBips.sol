// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ERC20AndAvaxDistributor.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20AndAvaxDistributorAdjustableBips is ERC20AndAvaxDistributor, Ownable {
    constructor(address[] memory _beneficiaries, uint256[] memory _bips, address _DEFAULT_TOKEN) ERC20AndAvaxDistributor(_beneficiaries, _bips, _DEFAULT_TOKEN) {
    }
    function updateSplit(address[] calldata _beneficiaries, uint256[] calldata _bips) external onlyOwner {
        numberBeneficiaries = _beneficiaries.length;
        require(numberBeneficiaries == _bips.length, "input length mismatch");
        require(numberBeneficiaries <= 64, "sanity check");
        uint256 totalBips;
        beneficiaries = new address[](numberBeneficiaries);
        bips = new uint256[](numberBeneficiaries);
        for (uint256 i = 0; i < numberBeneficiaries; i++) {
            beneficiaries[i] = _beneficiaries[i];
            bips[i] = _bips[i];
            totalBips += _bips[i];
        }
        require(totalBips == MAX_BIPS, "wrong bips sum");
    }
}
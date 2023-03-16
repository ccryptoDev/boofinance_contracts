// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../TokenOrAvaxTransfer.sol";

contract ERC20AndAvaxDistributor is TokenOrAvaxTransfer {
    using SafeERC20 for IERC20;
    address[] public beneficiaries;
    uint256[] public bips;
    uint256 public numberBeneficiaries;
    address public immutable DEFAULT_TOKEN;
    uint256 internal constant MAX_BIPS = 10000;
    constructor(address[] memory _beneficiaries, uint256[] memory _bips, address _DEFAULT_TOKEN) {
        require(_DEFAULT_TOKEN != address(0), "zero bad");
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
        DEFAULT_TOKEN = _DEFAULT_TOKEN;
    }
    function splitERC20(address token) public {
        uint256 tokenBalance = _checkBalance(token);
        if (tokenBalance > 0) {
            for (uint256 i = 0; i < numberBeneficiaries; i++) {
                _tokenOrAvaxTransfer(token, beneficiaries[i], (tokenBalance * bips[i]) / MAX_BIPS);
            }
        }
    }
    function defaultSplit() public {
        splitERC20(DEFAULT_TOKEN);
    }
    fallback() external {
        defaultSplit();
    }
    receive() external payable {
    }
}
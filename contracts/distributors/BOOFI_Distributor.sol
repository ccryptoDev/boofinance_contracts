// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ERC20DistributorAdjustableBips.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BOOFI_Distributor is ERC20DistributorAdjustableBips {
    using SafeERC20 for IERC20;
    uint256 public minAmountToDistribute = 200e18;
    constructor(address[] memory _beneficiaries, uint256[] memory _bips, address _BOOFI) 
        ERC20DistributorAdjustableBips(_beneficiaries, _bips, _BOOFI)
    {
    }
    //returns the pending amount of BOOFI to send to the zBOOFI_Staking contract. assumes zBOOFI_Staking is beneficiaries[0]
    function checkStakingReward() external view returns (uint256) {
        uint256 boofiBalance = IERC20(DEFAULT_TOKEN).balanceOf(address(this));
        if (boofiBalance > minAmountToDistribute) {
            return (boofiBalance * bips[0]) / MAX_BIPS;
        } else {
            return 0;
        }
    }
    function distributeBOOFI() external {
        uint256 boofiBalance = IERC20(DEFAULT_TOKEN).balanceOf(address(this));
        if (boofiBalance > minAmountToDistribute) {
            for (uint256 i = 0; i < numberBeneficiaries; i++) {
                IERC20(DEFAULT_TOKEN).safeTransfer(beneficiaries[i], (boofiBalance * bips[i]) / MAX_BIPS);
            }            
        }
    }
    function updateMinAmountToDistribute(uint256 _minAmountToDistribute) external onlyOwner {
        minAmountToDistribute = _minAmountToDistribute;
    }
    function recoverERC20(address token, address to) external onlyOwner {
        require(token != DEFAULT_TOKEN);
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, tokenBalance);
    }
}
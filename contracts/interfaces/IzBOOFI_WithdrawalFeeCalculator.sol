// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IzBOOFI_WithdrawalFeeCalculator {
    function withdrawalFee(uint256 amountZBoofiWithdrawn) external view returns(uint256);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ZombieBOOFI.sol";

contract zBOOFI_WithdrawalFeeCalculator is Ownable {
    // multiplier used in calculations of withdrawalFee function. adjustable by contract owner.
    //initial value of 10000 means that if 5% of BOOFI deposited in the zBOOFI contract has been withdrawn in the last 3 days, then the withdrawal fee is 5%
    uint256 public withdrawalFeeMultiplier = 10000;

    //zBOOFI token
    ZombieBOOFI public immutable ZBOOFI;

    uint256 public constant MAX_BIPS = 10000;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant MIN_FEE = 100;

    constructor(ZombieBOOFI _ZBOOFI) {
        ZBOOFI = _ZBOOFI;
    }

    function withdrawalFee(uint256 amountZBoofiWithdrawn) external view returns(uint256) {
        (uint256[] memory recentWithdrawals, ) = ZBOOFI.getWithdrawalAmountHistory(3);
        uint256 totalBoofi = ZBOOFI.boofiBalance();
        uint256 totalZBoofi = ZBOOFI.totalSupply();
        uint256 timeSinceLastDailyUpdate = ZBOOFI.timeSinceLastDailyUpdate();
        uint256 timeSoFarToday = timeSinceLastDailyUpdate <= SECONDS_PER_DAY ? timeSinceLastDailyUpdate : SECONDS_PER_DAY;
        uint256 withdrawalsSoFarToday = ZBOOFI.totalWithdrawals() + (amountZBoofiWithdrawn * totalBoofi / totalZBoofi) - ZBOOFI.rollingStartTotalWithdrawals();
        uint256 withdrawalsInLastThreeDays;
        if (recentWithdrawals.length < 3) {
            for (uint256 i = 0; i < recentWithdrawals.length; i ++) {
                withdrawalsInLastThreeDays += recentWithdrawals[i];
            }
            withdrawalsInLastThreeDays += withdrawalsSoFarToday;
        } else {
            withdrawalsInLastThreeDays = (
                (recentWithdrawals[0] * (SECONDS_PER_DAY - timeSoFarToday) / SECONDS_PER_DAY)
                + recentWithdrawals[1]
                + recentWithdrawals[2]
                + withdrawalsSoFarToday
            );
        }
        uint256 finalWithdrawalFee = ((withdrawalsInLastThreeDays * withdrawalFeeMultiplier) / totalBoofi);
        if (finalWithdrawalFee < MIN_FEE) {
            finalWithdrawalFee = MIN_FEE;
        }
        return finalWithdrawalFee;
    }

    function setWithdrawalFeeMultiplier(uint256 _withdrawalFeeMultiplier) external onlyOwner {
        withdrawalFeeMultiplier = _withdrawalFeeMultiplier;
    }
}
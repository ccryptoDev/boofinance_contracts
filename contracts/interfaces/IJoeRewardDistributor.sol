// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

//interface based on https://snowtrace.io/address/0x2274491950b2d6d79b7e69b683b482282ba14885

interface IJoeRewardDistributor {
    function rewardAccrued(uint8, address) external view returns (uint256);

    //rewardId = 0 for JOE, 1 for AVAX
    // Claim all the "COMP" equivalent accrued by holder in all markets
    function claimReward(uint8 rewardId, address holder) external;

    // Claim all the "COMP" equivalent accrued by holder in specific markets
    function claimReward(uint8 rewardId, address holder, address[] calldata CTokens) external;

    // Claim all the "COMP" equivalent accrued by specific holders in specific markets for their supplies and/or borrows
    function claimReward(uint8 rewardId,
        address[] calldata holders,
        address[] calldata CTokens,
        bool borrowers,
        bool suppliers
    ) external;
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IRewarder {
    function onZBoofiReward(address depositToken, address caller, address recipient, uint256 zboofiAmount, uint256 previousShareAmount, uint256 newShareAmount) external;
    function pendingTokens(address depositToken, address user) external view returns (address[] memory, uint256[] memory);
}
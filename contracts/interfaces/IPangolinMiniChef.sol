// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IPangolinMiniChef {
    function REWARD() external view returns (address);
    function rewardPerSecond() external view returns (uint256);
    function pendingReward(uint256 _pid, address _user) external view returns (uint256);
    function lpToken(uint256 pid) external view returns (address);
    function rewarder(uint256 pid) external view returns (address);
    function poolInfo(uint256 pid) external view returns (
        uint128 accRewardPerShare,
        uint64 lastRewardTime,
        uint64 allocPoint
    );
    function deposit(uint256 _pid, uint256 _amount, address to) external;
    function withdraw(uint256 _pid, uint256 _amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, int256 rewardDebt); 
}
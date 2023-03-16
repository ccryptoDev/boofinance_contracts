// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IJoeChef.sol";
import "./BoofiStrategyForDexStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForJoeV2Staking is BoofiStrategyForDexStaking {
    using SafeERC20 for IERC20;

    address internal constant JOE_TOKEN = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    IJoeChef public constant JOE_MASTERCHEF_V2 = IJoeChef(0xd6a4F121CA35509aF06A0Be99093d08462f53052);
    IRouter public constant JOE_ROUTER = IRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    uint256 public immutable JOE_PID;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        uint256 _JOE_PID
        ) 
        BoofiStrategyForDexStaking(_hauntedHouse, _depositToken, IERC20(JOE_TOKEN), JOE_ROUTER)
    {
        JOE_PID = _JOE_PID;
        pathRewardToBoofi = new address[](3);
        pathRewardToBoofi[0] = JOE_TOKEN;
        pathRewardToBoofi[1] = WAVAX;
        pathRewardToBoofi[2] = _hauntedHouse.BOOFI();
        _depositToken.safeApprove(address(JOE_MASTERCHEF_V2), MAX_UINT);
    }
    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        (uint256 pendingJoe, , , ) = JOE_MASTERCHEF_V2.pendingTokens(JOE_PID, address(this));
        return pendingJoe;
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal override {
        JOE_MASTERCHEF_V2.deposit(JOE_PID, tokenAmount);
    }

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal override {
        JOE_MASTERCHEF_V2.withdraw(JOE_PID, tokenAmount);
    }

    //claims reward from the farm
    function _getReward() internal override {
        JOE_MASTERCHEF_V2.deposit(JOE_PID, 0);
    }

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal view override returns (uint256) {
        (uint256 depositedBalance, ) = JOE_MASTERCHEF_V2.userInfo(JOE_PID, address(this));
        return depositedBalance;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IPangolinMiniChef.sol";
import "./BoofiStrategyForDexStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForPangolinMiniChefStaking is BoofiStrategyForDexStaking {
    using SafeERC20 for IERC20;

    address internal constant PNG_TOKEN = 0x60781C2586D68229fde47564546784ab3fACA982;
    IPangolinMiniChef public constant PANGOLIN_MINI_CHEF = IPangolinMiniChef(0x1f806f7C8dED893fd3caE279191ad7Aa3798E928);
    IRouter public constant PNG_ROUTER = IRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
    uint256 public immutable PANGOLIN_PID;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        uint256 _PANGOLIN_PID
        ) 
        BoofiStrategyForDexStaking(_hauntedHouse, _depositToken, IERC20(PNG_TOKEN), PNG_ROUTER)
    {
        PANGOLIN_PID = _PANGOLIN_PID;
        pathRewardToBoofi = new address[](3);
        pathRewardToBoofi[0] = PNG_TOKEN;
        pathRewardToBoofi[1] = WAVAX;
        pathRewardToBoofi[2] = _hauntedHouse.BOOFI();
        _depositToken.safeApprove(address(PANGOLIN_MINI_CHEF), MAX_UINT);
    }
    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        uint256 pendingPng = PANGOLIN_MINI_CHEF.pendingReward(PANGOLIN_PID, address(this));
        return pendingPng;
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal override {
        PANGOLIN_MINI_CHEF.deposit(PANGOLIN_PID, tokenAmount, address(this));
    }

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal override {
        PANGOLIN_MINI_CHEF.withdraw(PANGOLIN_PID, tokenAmount, address(this));
    }

    //claims reward from the farm
    function _getReward() internal override {
        PANGOLIN_MINI_CHEF.harvest(PANGOLIN_PID, address(this));
    }

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal view override returns (uint256) {
        (uint256 depositedBalance, ) = PANGOLIN_MINI_CHEF.userInfo(PANGOLIN_PID, address(this));
        return depositedBalance;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/ILydiaChef.sol";
import "./BoofiStrategyForDexStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForLydiaStaking is BoofiStrategyForDexStaking {
    using SafeERC20 for IERC20;

    address internal constant LYD_TOKEN = 0x4C9B4E1AC6F24CdE3660D5E4Ef1eBF77C710C084;
    ILydiaChef public constant LYD_CHEF = ILydiaChef(0xFb26525B14048B7BB1F3794F6129176195Db7766);
    IRouter public constant LYD_ROUTER = IRouter(0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27);
    uint256 public immutable LYD_PID;
    uint256 internal amountToSwap;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        uint256 _LYD_PID
        ) 
        BoofiStrategyForDexStaking(_hauntedHouse, _depositToken, IERC20(LYD_TOKEN), LYD_ROUTER)
    {
        LYD_PID = _LYD_PID;
        pathRewardToBoofi = new address[](3);
        pathRewardToBoofi[0] = LYD_TOKEN;
        pathRewardToBoofi[1] = WAVAX;
        pathRewardToBoofi[2] = _hauntedHouse.BOOFI();
        _depositToken.safeApprove(address(LYD_CHEF), MAX_UINT);
    }
    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        uint256 pendingLyd = LYD_CHEF.pendingLyd(LYD_PID, address(this));
        return pendingLyd;
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal override {
        if (LYD_PID != 0) {
            LYD_CHEF.deposit(LYD_PID, tokenAmount);            
        } else {
            LYD_CHEF.enterStaking(tokenAmount);
        }
    }

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal override {
        if (LYD_PID != 0) {
            LYD_CHEF.withdraw(LYD_PID, tokenAmount);            
        } else {
            LYD_CHEF.leaveStaking(tokenAmount);
        }
    }

    //claims reward from the farm
    function _getReward() internal override {
        if (LYD_PID != 0) {
            LYD_CHEF.deposit(LYD_PID, 0);           
        } else {
            LYD_CHEF.enterStaking(0);
        }
    }

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal view override returns (uint256) {
        (uint256 depositedBalance, ) = LYD_CHEF.userInfo(LYD_PID, address(this));
        return depositedBalance;
    }

    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal override {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0) {
            uint256 balanceBefore = REWARD_TOKEN.balanceOf(address(this));
            _getReward();
            uint256 balanceDiff = REWARD_TOKEN.balanceOf(address(this)) - balanceBefore;
            totalHarvested += balanceDiff;
            amountToSwap = balanceDiff;
            _swapRewardForBoofi();
        }
    }

    //swaps REWARD_TOKENs for BOOFI and sends the BOOFI to the strategyPool. a portion of REWARD_TOKENS may also be allocated to the Haunted House's performanceFeeAddress
    function _swapRewardForBoofi() internal override {
        uint256 amountIn = amountToSwap;
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                storedPerformanceFees += performanceFee;
                amountIn -= performanceFee;
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathRewardToBoofi, hauntedHouse.strategyPool(), block.timestamp);
        }
    }
}
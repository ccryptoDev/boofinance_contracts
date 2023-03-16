// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IStakingRewards.sol";
import "./BoofiStrategyForDexStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForPangolinStaking is BoofiStrategyForDexStaking {
    using SafeERC20 for IERC20;

    IRouter public constant PNG_ROUTER = IRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
    IStakingRewards public immutable STAKING_CONTRACT;
    uint256 internal amountToSwap;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        IERC20 _rewardToken,
        IStakingRewards _STAKING_CONTRACT
        ) 
        BoofiStrategyForDexStaking(_hauntedHouse, _depositToken, _rewardToken, PNG_ROUTER)
    {
        require(address(_STAKING_CONTRACT) != address(0),"zero bad");
        STAKING_CONTRACT = _STAKING_CONTRACT;
        if (address(_rewardToken) != WAVAX) {
            pathRewardToBoofi = new address[](3);
            pathRewardToBoofi[0] = address(_rewardToken);
            pathRewardToBoofi[1] = WAVAX;
            pathRewardToBoofi[2] = _hauntedHouse.BOOFI();
        } else {
            pathRewardToBoofi = new address[](2);
            pathRewardToBoofi[0] = WAVAX;
            pathRewardToBoofi[1] = _hauntedHouse.BOOFI(); 
        }
        _depositToken.safeApprove(address(STAKING_CONTRACT), MAX_UINT);
    }

    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        return STAKING_CONTRACT.earned(address(this));
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal override {
        STAKING_CONTRACT.stake(tokenAmount);
    }

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal override {
        STAKING_CONTRACT.withdraw(tokenAmount);
    }

    //claims reward from the farm
    function _getReward() internal override {
        STAKING_CONTRACT.getReward();
    }

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal view override returns (uint256) {
        uint256 depositedBalance = STAKING_CONTRACT.balanceOf(address(this));
        return depositedBalance;
    }

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
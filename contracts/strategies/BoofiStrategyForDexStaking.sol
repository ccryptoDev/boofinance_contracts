// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IRouter.sol";
import "./BoofiStrategyBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BoofiStrategyForDexStaking is BoofiStrategyBase {
    using SafeERC20 for IERC20;

    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    //token earned from DEX farm
    IERC20 public immutable REWARD_TOKEN;
    //DEX router
    IRouter public immutable ROUTER;
    //total REWARD_TOKEN harvested by the contract all time
    uint256 public totalHarvested;
    //stored rewardTokens to be withdrawn to performanceFeeAdress of HauntedHouse
    uint256 public storedPerformanceFees;
    //swap path from REWARD_TOKEN to Boofi
    address[] pathRewardToBoofi;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        IERC20 _REWARD_TOKEN,
        IRouter _ROUTER
        ) 
        BoofiStrategyBase(_hauntedHouse, _depositToken)
    {
        REWARD_TOKEN = _REWARD_TOKEN;
        ROUTER = _ROUTER;
        REWARD_TOKEN.safeApprove(address(ROUTER), MAX_UINT);
    }

    //VIEW FUNCTIONS
    //finds the pending rewards for the contract to claim
    function checkReward() public view virtual returns (uint256);

    //OWNER-ONlY FUNCTIONS
    function deposit(address, address, uint256 tokenAmount, uint256) external virtual override onlyOwner {
        _claimRewards();
        if (tokenAmount > 0) {
            _stake(tokenAmount);
        }
    }

    function withdraw(address, address to, uint256 tokenAmount, uint256) external virtual override onlyOwner {
        _claimRewards();
        if (tokenAmount > 0) {
            _withdraw(tokenAmount);
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function migrate(address newStrategy) external virtual override onlyOwner {
        uint256 toWithdraw = _checkDepositedBalance();
        if (toWithdraw > 0) {
            _withdraw(toWithdraw);
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 rewardsToTransfer = REWARD_TOKEN.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            REWARD_TOKEN.safeTransfer(newStrategy, rewardsToTransfer);
        }
    }

    function onMigration() external virtual override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        _stake(toStake);
    }

    function withdrawPerformanceFees() external virtual {
        uint256 toTransfer = storedPerformanceFees;
        storedPerformanceFees = 0;
        REWARD_TOKEN.safeTransfer(hauntedHouse.performanceFeeAddress(), toTransfer);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal virtual {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0) {
            uint256 balanceBefore = REWARD_TOKEN.balanceOf(address(this));
            _getReward();
            uint256 balanceDiff = REWARD_TOKEN.balanceOf(address(this)) - balanceBefore;
            totalHarvested += balanceDiff;
            _swapRewardForBoofi();
        }
    }

    //swaps REWARD_TOKENs for BOOFI and sends the BOOFI to the strategyPool. a portion of REWARD_TOKENS may also be allocated to the Haunted House's performanceFeeAddress
    function _swapRewardForBoofi() internal virtual {
        uint256 amountIn = REWARD_TOKEN.balanceOf(address(this)) - storedPerformanceFees;
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                storedPerformanceFees += performanceFee;
                amountIn -= performanceFee;
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathRewardToBoofi, hauntedHouse.strategyPool(), block.timestamp);
        }
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal virtual;

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal virtual;

    //claims reward from the farm
    function _getReward() internal virtual;

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal virtual returns (uint256);
}
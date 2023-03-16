// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IJoeChef.sol";
import "./BoofiStrategyForDexStakingMultiRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForJoeV3Staking is BoofiStrategyForDexStakingMultiRewards {
    using SafeERC20 for IERC20;

    address internal constant JOE_TOKEN = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    IJoeChef public constant JOE_MASTERCHEF_V3 = IJoeChef(0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00);
    IRouter public constant JOE_ROUTER = IRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    uint256 public immutable JOE_PID;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        uint256 _JOE_PID,
        address[] memory _REWARD_TOKENS_ARRAY
        )
        BoofiStrategyForDexStakingMultiRewards(
            _hauntedHouse,
            _depositToken,
            JOE_ROUTER,
            _REWARD_TOKENS_ARRAY
        )
    {
        require(_REWARD_TOKENS_ARRAY[0] == JOE_TOKEN, "first reward must be JOE");
        pathsRewardsToBoofi[0].push(JOE_TOKEN);
        pathsRewardsToBoofi[0].push(WAVAX);
        pathsRewardsToBoofi[0].push(_hauntedHouse.BOOFI());
        for (uint256 i = 1; i < _REWARD_TOKENS_ARRAY.length; i++) {
            if (_REWARD_TOKENS_ARRAY[i] != AVAX) {
                pathsRewardsToBoofi[i].push(_REWARD_TOKENS_ARRAY[i]);                
            }
            if (_REWARD_TOKENS_ARRAY[i] != WAVAX) {
                pathsRewardsToBoofi[i].push(WAVAX);
            }
            pathsRewardsToBoofi[i].push(_hauntedHouse.BOOFI());
        }
        JOE_PID = _JOE_PID;
        _depositToken.safeApprove(address(JOE_MASTERCHEF_V3), MAX_UINT);
    }
    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        (uint256 pendingJoe, , , ) = JOE_MASTERCHEF_V3.pendingTokens(JOE_PID, address(this));
        return pendingJoe;
    }

    //stakes tokenAmount into farm
    function _stake(uint256 tokenAmount) internal override {
        JOE_MASTERCHEF_V3.deposit(JOE_PID, tokenAmount);
    }

    //withdraws tokenAmount from farm
    function _withdraw(uint256 tokenAmount) internal override {
        JOE_MASTERCHEF_V3.withdraw(JOE_PID, tokenAmount);
    }

    //claims reward from the farm
    function _getReward() internal override {
        JOE_MASTERCHEF_V3.deposit(JOE_PID, 0);
    }

    //checks how many depositTokens this contract has in the farm
    function _checkDepositedBalance() internal view override returns (uint256) {
        (uint256 depositedBalance, ) = JOE_MASTERCHEF_V3.userInfo(JOE_PID, address(this));
        return depositedBalance;
    }
}
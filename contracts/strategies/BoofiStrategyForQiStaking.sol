// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IWAVAX.sol";
import "../interfaces/IQiComptroller.sol";
import "./BoofiStrategyForCTokenStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForQiStaking is BoofiStrategyForCTokenStaking {
    using SafeERC20 for IERC20;

    //total WAVAX harvested all time
    uint256 public totalWavaxHarvested;
    //stored Wavax to be withdrawn to performanceFeeAdress of HauntedHouse
    uint256 public storedWavaxPerformanceFees;
    //swap path from WAVAX to Boofi
    address[] pathWavaxToBoofi;

    address internal constant BENQI_COMPTROLLER = 0x486Af39519B4Dc9a7fCcd318217352830E8AD9b4;
    address internal constant QI_TOKEN = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;
    address internal constant JOE_ROUTER = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        ICToken _CTOKEN
        ) 
        BoofiStrategyForCTokenStaking(_hauntedHouse, _depositToken, BENQI_COMPTROLLER, _CTOKEN, IERC20(QI_TOKEN), IRouter(JOE_ROUTER))
    {
        pathRewardToBoofi = new address[](3);
        pathRewardToBoofi[0] = QI_TOKEN;
        pathRewardToBoofi[1] = WAVAX;
        pathRewardToBoofi[2] = _hauntedHouse.BOOFI();
        pathWavaxToBoofi = new address[](2);
        pathWavaxToBoofi[0] = WAVAX;
        pathWavaxToBoofi[1] = _hauntedHouse.BOOFI();
        IWAVAX(WAVAX).approve(address(ROUTER), MAX_UINT);
    }

    //VIEW FUNCTIONS
    //finds the pending rewards for the contract to claim
    function checkReward() public view override returns (uint256) {
        return IQiComptroller(COMPTROLLER).rewardAccrued(0, address(this));
    }

    //EXTERNAL FUNCTIONS
    //simple receive function for accepting AVAX
    receive() external payable {
    }

    function withdrawPerformanceFees() public override {
        super.withdrawPerformanceFees();
        uint256 wavaxToTransfer = storedWavaxPerformanceFees;
        storedWavaxPerformanceFees = 0;
        IWAVAX(WAVAX).transfer(hauntedHouse.performanceFeeAddress(), wavaxToTransfer);
    }

    //OWNER-ONlY FUNCTIONS
    function migrate(address newStrategy) external virtual override onlyOwner {
        withdrawPerformanceFees();
        uint256 toRedeem = _checkDepositedBalance();
        uint256 response = CTOKEN.redeem(toRedeem);
        require(response == 0, "CTOKEN redeem failed");
        uint256 toTransfer = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(newStrategy, toTransfer);
        uint256 rewardsToTransfer = REWARD_TOKEN.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            REWARD_TOKEN.safeTransfer(newStrategy, rewardsToTransfer);
        }
        uint256 wavaxToTransfer = IWAVAX(WAVAX).balanceOf(address(this));
        if (wavaxToTransfer > 0) {
            IWAVAX(WAVAX).transfer(newStrategy, wavaxToTransfer);
        }
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal override {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0) {
            uint256 balanceBefore = REWARD_TOKEN.balanceOf(address(this));
            _getReward();
            uint256 balanceDiff = REWARD_TOKEN.balanceOf(address(this)) - balanceBefore;
            totalRewardTokenHarvested += balanceDiff;
            uint256 avaxHarvested = address(this).balance;
            if (avaxHarvested > 0) {
                //wrap AVAX into WAVAX
                IWAVAX(WAVAX).deposit{value: avaxHarvested}();
                totalWavaxHarvested += avaxHarvested;
                _swapWavaxForBoofi(avaxHarvested);
            }
            _swapRewardForBoofi(balanceDiff);
        }
    }

    //claims reward token(s)
    function _getReward() internal override {
        //claim QI
        IQiComptroller(COMPTROLLER).claimReward(0, address(this));
        //claim AVAX
        IQiComptroller(COMPTROLLER).claimReward(1, address(this));
    }

    //swaps WAVAX for BOOFI and sends the BOOFI to the strategyPool. a portion of WAVAX may also be allocated to the Haunted House's performanceFeeAddress
    function _swapWavaxForBoofi(uint256 amountIn) internal {
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                storedWavaxPerformanceFees += performanceFee;
                amountIn -= performanceFee;
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathWavaxToBoofi, hauntedHouse.strategyPool(), block.timestamp);
        }
    }
}
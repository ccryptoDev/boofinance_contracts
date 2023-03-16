// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/ICToken_Native.sol";
import "./BoofiStrategyForQiStaking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyForQiStaking_WAVAX is BoofiStrategyForQiStaking {
    using SafeERC20 for IERC20;

    address internal constant QI_AVAX = 0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c;

    constructor(
        IHauntedHouse _hauntedHouse
        ) 
        BoofiStrategyForQiStaking(_hauntedHouse, IERC20(WAVAX), ICToken(QI_AVAX))
    {
    }

    //OWNER-ONlY FUNCTIONS
    //call _claimRewards() after other logic in this implementation to avoid swapping freshly deposited WAVAX for BOOFI
    function deposit(address, address, uint256 tokenAmount, uint256) external override onlyOwner {
        if (tokenAmount > 0) {
            _stake(tokenAmount);
        }
        _claimRewards();
    }

    function withdraw(address, address to, uint256 tokenAmount, uint256) external virtual override onlyOwner {
        _claimRewards();
        if (tokenAmount > 0) {
            _withdraw(tokenAmount);
            payable(to).transfer(tokenAmount);
        }
    }

    function migrate(address newStrategy) external virtual override onlyOwner {
        withdrawPerformanceFees();
        uint256 toRedeem = _checkDepositedBalance();
        uint256 response = CTOKEN.redeem(toRedeem);
        require(response == 0, "CTOKEN redeem failed");
        uint256 toTransfer = address(this).balance;
        IWAVAX(WAVAX).deposit{value: toTransfer}();
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
    //turns tokenAmount into CTokens
    function _stake(uint256 tokenAmount) internal override {
        IWAVAX(WAVAX).withdraw(tokenAmount);
        ICToken_Native(address(CTOKEN)).mint{value: tokenAmount}();
    }
}
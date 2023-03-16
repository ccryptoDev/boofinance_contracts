// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IRouter.sol";
import "../interfaces/ICToken.sol";
import "../interfaces/IWAVAX.sol";
import "./BoofiStrategyBase.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BoofiStrategyForCTokenStaking is BoofiStrategyBase {
    using SafeERC20 for IERC20;

    address public immutable COMPTROLLER;
    ICToken public immutable CTOKEN;
    //token equivalent to Compound's "COMP" token
    IERC20 public immutable REWARD_TOKEN;
    //DEX router
    IRouter public immutable ROUTER;
    //total REWARD_TOKEN harvested by the contract all time
    uint256 public totalRewardTokenHarvested;
    //stored rewardTokens to be withdrawn to performanceFeeAdress of HauntedHouse
    uint256 public storedPerformanceFees;
    //swap path from REWARD_TOKEN to Boofi
    address[] pathRewardToBoofi;
    //swap path from depositToken to Boofi, used for swapping profits
    address[] pathDepositToBoofi;

    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        address _COMPTROLLER,
        ICToken _CTOKEN,
        IERC20 _REWARD_TOKEN,
        IRouter _ROUTER
        ) 
        BoofiStrategyBase(_hauntedHouse, _depositToken)
    {
        COMPTROLLER = _COMPTROLLER;
        CTOKEN = _CTOKEN;
        REWARD_TOKEN = _REWARD_TOKEN;
        ROUTER = _ROUTER;
        REWARD_TOKEN.safeApprove(address(ROUTER), MAX_UINT);
        if (address(_depositToken) != address(_REWARD_TOKEN)) {
            _depositToken.safeApprove(address(ROUTER), MAX_UINT);            
        }
        _depositToken.safeApprove(address(CTOKEN), MAX_UINT);
        if (address(_depositToken) == WAVAX) {
            pathDepositToBoofi = new address[](2);
            pathDepositToBoofi[0] = WAVAX;
            pathDepositToBoofi[1] = _hauntedHouse.BOOFI(); 
        } else {
            pathDepositToBoofi = new address[](3);
            pathDepositToBoofi[0] = address(_depositToken);
            pathDepositToBoofi[1] = WAVAX;
            pathDepositToBoofi[2] = _hauntedHouse.BOOFI();
        }
    }

    //VIEW FUNCTIONS
    //finds the pending rewards for the contract to claim
    function checkReward() public view virtual returns (uint256);

    //EXTERNAL FUNCTIONS
    function withdrawPerformanceFees() public virtual {
        require(msg.sender == tx.origin || msg.sender == owner(), "onlyEOA or owner");
        _claimRewards();
        uint256 underlyingBalance = CTOKEN.balanceOfUnderlying(address(this));
        IHauntedHouse.TokenInfo memory tokenInfo = hauntedHouse.tokenParameters(address(depositToken));
        uint256 totalDeposited = tokenInfo.totalTokens;
        uint256 profits = (underlyingBalance > totalDeposited) ? (underlyingBalance - totalDeposited) : 0;
        if (profits > 0) {
            _withdraw(profits);
            uint256 underlyingToSend = _swapUnderlyingForBoofi(profits);
            if (underlyingToSend > 0) {
                depositToken.safeTransfer(hauntedHouse.performanceFeeAddress(), underlyingToSend);                
            }
        }
        uint256 toTransfer = storedPerformanceFees;
        storedPerformanceFees = 0;
        REWARD_TOKEN.safeTransfer(hauntedHouse.performanceFeeAddress(), toTransfer);
    }

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
            if (address(depositToken) == WAVAX) {
                IWAVAX(WAVAX).withdraw(tokenAmount);
                payable(to).transfer(tokenAmount);
            } else {
                depositToken.safeTransfer(to, tokenAmount);                
            }
        }
    }

    function migrate(address newStrategy) external virtual override onlyOwner {
        uint256 toRedeem = _checkDepositedBalance();
        uint256 response = CTOKEN.redeem(toRedeem);
        require(response == 0, "CTOKEN redeem failed");
        uint256 toTransfer = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(newStrategy, toTransfer);
        uint256 rewardsToTransfer = REWARD_TOKEN.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            REWARD_TOKEN.safeTransfer(newStrategy, rewardsToTransfer);
        }
    }

    function onMigration() external virtual override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        _stake(toStake);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal virtual {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0) {
            uint256 balanceBefore = REWARD_TOKEN.balanceOf(address(this));
            _getReward();
            uint256 balanceDiff = REWARD_TOKEN.balanceOf(address(this)) - balanceBefore;
            totalRewardTokenHarvested += balanceDiff;
            _swapRewardForBoofi(balanceDiff);
        }
    }

    //swaps REWARD_TOKENs for BOOFI and sends the BOOFI to the strategyPool. a portion of REWARD_TOKENS may also be allocated to the Haunted House's performanceFeeAddress
    function _swapRewardForBoofi(uint256 amountIn) internal virtual {
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                storedPerformanceFees += performanceFee;
                amountIn -= performanceFee;
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathRewardToBoofi, hauntedHouse.strategyPool(), block.timestamp);
        }
    }

    //swaps underlying depositToken profits for BOOFI and sends the BOOFI to the strategyPool. a portion of profits may also be allocated to the Haunted House's performanceFeeAddress
    function _swapUnderlyingForBoofi(uint256 amountIn) internal virtual returns (uint256) {
        uint256 performanceFee;
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                amountIn -= performanceFee;
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathDepositToBoofi, hauntedHouse.strategyPool(), block.timestamp);
        }
        return performanceFee;
    }

    //turns tokenAmount into CTokens
    function _stake(uint256 tokenAmount) internal virtual {
        uint256 response = CTOKEN.mint(tokenAmount);
        require(response == 0, "CTOKEN mint failed");
    }

    //turns appropriate amount of CTokens into tokenAmount in underlying tokens
    function _withdraw(uint256 tokenAmount) internal virtual {
        uint256 response = CTOKEN.redeemUnderlying(tokenAmount);
        require(response == 0, "CTOKEN redeemUnderlying failed");
    }

    //claims reward token(s)
    function _getReward() internal virtual;

    //checks how many cTokens this contract has total
    function _checkDepositedBalance() internal virtual returns (uint256) {
        return CTOKEN.balanceOf(address(this));
    }
}
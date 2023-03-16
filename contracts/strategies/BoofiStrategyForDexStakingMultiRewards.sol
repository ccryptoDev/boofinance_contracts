// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IRouter.sol";
import "../interfaces/IWAVAX.sol";
import "./BoofiStrategyBase.sol";
import "../TokenOrAvaxTransfer.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//base contract for staking in DEXes, for when the DEX offers multiple rewards, e.g. using a MasterChef with 'Rewarder'
abstract contract BoofiStrategyForDexStakingMultiRewards is BoofiStrategyBase, TokenOrAvaxTransfer {
    using SafeERC20 for IERC20;

    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    //DEX router
    IRouter public immutable ROUTER;
    //tokens rewarded by the DEX    
    uint256 public immutable NUMBER_REWARDS_TOKENS;
    address[] public REWARDS_TOKEN_ARRAY;
    //total REWARD_TOKENs harvested by the contract all time
    uint256[] public totalHarvested;
    //stored rewardTokens to be withdrawn to performanceFeeAdress of HauntedHouse
    uint256[] public storedPerformanceFees;
    //swap paths from REWARD_TOKENs to Boofi
    mapping(uint256 => address[]) public pathsRewardsToBoofi;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken,
        IRouter _ROUTER,
        address[] memory _REWARDS_TOKEN_ARRAY
        ) 
        BoofiStrategyBase(_hauntedHouse, _depositToken)
    {
        uint256 numRewardTokens = _REWARDS_TOKEN_ARRAY.length;
        REWARDS_TOKEN_ARRAY = _REWARDS_TOKEN_ARRAY;
        NUMBER_REWARDS_TOKENS = numRewardTokens;
        storedPerformanceFees = new uint256[](numRewardTokens);
        totalHarvested = new uint256[](numRewardTokens);
        ROUTER = _ROUTER;
        for (uint256 i = 0; i < numRewardTokens; i++) {
            if (_REWARDS_TOKEN_ARRAY[i] != AVAX) {
                IERC20(_REWARDS_TOKEN_ARRAY[i]).safeApprove(address(ROUTER), MAX_UINT);                          
            } else {
                IERC20(WAVAX).safeApprove(address(ROUTER), MAX_UINT);
            }
        }
    }

    //VIEW FUNCTIONS
    //finds the pending rewards for the contract to claim
    function checkReward() public view virtual returns (uint256);

    //EXTERNAL FUNCTIONS
    //simple receive for accepting AVAX transfers
    receive() external payable {
    }

    //OWNER-ONlY FUNCTIONS
    function deposit(address, address, uint256 tokenAmount, uint256) external override onlyOwner {
        _claimRewards();
        if (tokenAmount > 0) {
            _stake(tokenAmount);
        }
    }

    function withdraw(address, address to, uint256 tokenAmount, uint256) external override onlyOwner {
        _claimRewards();
        if (tokenAmount > 0) {
            _withdraw(tokenAmount);
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function migrate(address newStrategy) external override onlyOwner {
        uint256 toWithdraw = _checkDepositedBalance();
        if (toWithdraw > 0) {
            _withdraw(toWithdraw);
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 toTransfer;
        for (uint256 i = 0; i < NUMBER_REWARDS_TOKENS; i++) {
            toTransfer = _checkBalance(REWARDS_TOKEN_ARRAY[i]);
            _tokenOrAvaxTransfer(REWARDS_TOKEN_ARRAY[i], newStrategy, toTransfer);
        }
    }

    function onMigration() external override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        _stake(toStake);
    }

    function inCaseTokensGetStuck(IERC20 token, address to, uint256 amount) external virtual override onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");
        require(address(token) != address(depositToken), "cannot recover deposit token");
        _tokenOrAvaxTransfer(address(token), to, amount);
    }
    
    function withdrawPerformanceFees() external {
        uint256 toTransfer;
        for (uint256 i = 0; i < NUMBER_REWARDS_TOKENS; i++) {
            toTransfer = storedPerformanceFees[i];
            storedPerformanceFees[i] = 0;
            _tokenOrAvaxTransfer(REWARDS_TOKEN_ARRAY[i], hauntedHouse.performanceFeeAddress(), toTransfer);
        }
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0) {
            uint256[] memory balancesBefore = new uint256[](NUMBER_REWARDS_TOKENS);
            for (uint256 i = 0; i < NUMBER_REWARDS_TOKENS; i++) {
                balancesBefore[i] = _checkBalance(REWARDS_TOKEN_ARRAY[i]);
            }
            _getReward();
            uint256 balanceDiff;
            for (uint256 i = 0; i < NUMBER_REWARDS_TOKENS; i++) {
                balanceDiff = _checkBalance(REWARDS_TOKEN_ARRAY[i]) - balancesBefore[i];
                if (balanceDiff > 0) {
                    totalHarvested[i] += balanceDiff;
                    _swapRewardForBoofi(i);
                }  
            }
        }
    }

    //swaps REWARDS_TOKEN_ARRAY[rewardTokenIndex] for BOOFI and sends the BOOFI to the strategyPool. a portion of REWARD_TOKENS may also be allocated to the Haunted House's performanceFeeAddress
    function _swapRewardForBoofi(uint256 rewardTokenIndex) internal {
        uint256 amountIn = _checkBalance(REWARDS_TOKEN_ARRAY[rewardTokenIndex]) - storedPerformanceFees[rewardTokenIndex];
        if (amountIn > 0) {
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (amountIn * performanceFeeBips) / MAX_BIPS;
                storedPerformanceFees[rewardTokenIndex] += performanceFee;
                amountIn -= performanceFee;
            }
            if (REWARDS_TOKEN_ARRAY[rewardTokenIndex] == AVAX) {
                IWAVAX(WAVAX).deposit{value: amountIn}();
            }
            ROUTER.swapExactTokensForTokens(amountIn, 0, pathsRewardsToBoofi[rewardTokenIndex], hauntedHouse.strategyPool(), block.timestamp);
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
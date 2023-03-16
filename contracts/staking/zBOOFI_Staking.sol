// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IERC20WithPermit.sol";
import "../interfaces/IBOOFI_Distributor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract zBOOFI_Staking is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable ZBOOFI;
    IERC20 public immutable BOOFI;
    IBOOFI_Distributor public boofiDistributor;

    //sum of all user deposits of zBOOFI
    uint256 public totalShares;
    //scaled up by ACC_BOOFI_PRECISION
    uint256 public boofiPerShare;
    uint256 public constant ACC_BOOFI_PRECISION = 1e18;
    uint256 public constant MAX_BIPS = 10000;
    uint256 public constant NUMBER_TOP_HARVESTERS = 10;
    uint256 public constant SECONDS_PER_DAY = 86400;

    //sum of all BOOFI harvested by all users of the contract, over all time
    uint256 public totalHarvested;

    //stored BOOFI balance
    uint256 public storedBoofiBalance;

    //for leaderboard tracking
    address[NUMBER_TOP_HARVESTERS] public topHarvesters;
    uint256[NUMBER_TOP_HARVESTERS] public largestAmountsHarvested;

    //for tracking of statistics in trailing 24 hour period
    uint256 public rollingStartTimestamp;
    uint256 public numStoredDailyData;
    uint256[] public historicBoofiPerShare;
    uint256[] public historicTimestamps;

    //total amount harvested by each user
    mapping(address => uint256) public harvested;
    //shares are earned by depositing zBOOFI
    mapping(address => uint256) public shares;
    //pending reward = (user.amount * boofiPerShare) / ACC_BOOFI_PRECISION - user.rewardDebt
    mapping(address => uint256) public rewardDebt;

    event Deposit(address indexed caller, address indexed to, uint256 amount);
    event Withdraw(address indexed caller, address indexed to, uint256 amount);
    event Harvest(address indexed caller, address indexed to, uint256 amount, uint256 indexed totalAmountHarvested);
    event DailyUpdate(uint256 indexed dayNumber, uint256 indexed timestamp, uint256 indexed boofiPerShare);

    constructor(IERC20 _ZBOOFI, IERC20 _BOOFI, IBOOFI_Distributor _boofiDistributor) {
        ZBOOFI = _ZBOOFI;
        BOOFI = _BOOFI;
        boofiDistributor = _boofiDistributor;
        //initiate topHarvesters array with burn address
        for (uint256 i = 0; i < NUMBER_TOP_HARVESTERS; i++) {
            topHarvesters[i] = 0x000000000000000000000000000000000000dEaD;
        }
        //push first "day" of historical data
        numStoredDailyData = 1;
        historicBoofiPerShare.push(boofiPerShare);
        historicTimestamps.push(block.timestamp);
        rollingStartTimestamp = block.timestamp;
        emit DailyUpdate(1, block.timestamp, 0);
    }

    //unclaimed rewards from the distributor contract
    function checkReward() public view returns (uint256) {
        return boofiDistributor.checkStakingReward();
    }

    //returns amount of BOOFI that 'user' can currently harvest
    function pendingBOOFI(address user) public view returns (uint256) {
        uint256 unclaimedRewards = checkReward();
        uint256 bal = BOOFI.balanceOf(address(this));
        if (bal > storedBoofiBalance) {
            unclaimedRewards += (bal - storedBoofiBalance);
        }
        uint256 multiplier = boofiPerShare;
        if (totalShares > 0 && unclaimedRewards > 0) {
            multiplier = multiplier + ((unclaimedRewards * ACC_BOOFI_PRECISION) / totalShares);
        }
        uint256 rewardsOfShares = (shares[user] * multiplier) / ACC_BOOFI_PRECISION;
        return (rewardsOfShares - rewardDebt[user]);
    }

    function getTopHarvesters() public view returns (address[NUMBER_TOP_HARVESTERS] memory) {
        return topHarvesters;
    }

    function getLargestAmountsHarvested()  public view returns (uint256[NUMBER_TOP_HARVESTERS] memory) {
        return largestAmountsHarvested;
    }

    //returns most recent stored boofiPerShare and the time at which it was stored
    function getLatestStoredBoofiPerShare() public view returns(uint256, uint256) {
        return (historicBoofiPerShare[numStoredDailyData - 1], historicTimestamps[numStoredDailyData - 1]);
    }

    //returns last amountDays of stored boofiPerShare datas
    function getBoofiPerShareHistory(uint256 amountDays) public view returns(uint256[] memory, uint256[] memory) {
        uint256 endIndex = numStoredDailyData - 1;
        uint256 startIndex = (amountDays > endIndex) ? 0 : (endIndex - amountDays + 1);
        uint256 length = endIndex - startIndex + 1;
        uint256[] memory boofiPerShares = new uint256[](length);
        uint256[] memory timestamps = new uint256[](length);
        for(uint256 i = startIndex; i <= endIndex; i++) {
            boofiPerShares[i - startIndex] = historicBoofiPerShare[i];
            timestamps[i - startIndex] = historicTimestamps[i];            
        }
        return (boofiPerShares, timestamps);
    }

    function timeSinceLastDailyUpdate() public view returns(uint256) {
        return (block.timestamp - rollingStartTimestamp);
    }

    //EXTERNAL FUNCTIONS
    //harvest rewards for message sender
    function harvest() external {
        _claimRewards();
        _harvest(msg.sender);
    }

    //harvest rewards for message sender and send them to 'to'
    function harvestTo(address to) external {
        _claimRewards();
        _harvest(to);
    }

    //deposit 'amount' of zBOOFI and credit them to message sender
    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    //deposit 'amount' of zBOOFI and credit them to 'to'
    function depositTo(address to, uint256 amount) external {
        _deposit(to, amount);
    }

    //approve this contract to transfer 'value' zBOOFI, then deposit 'amount' of zBOOFI and credit them to message sender
    function depositWithPermit(uint256 amount, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20WithPermit(address(ZBOOFI)).permit(msg.sender, address(this), value, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    //approve this contract to transfer 'value' zBOOFI, then deposit 'amount' of zBOOFI and credit them to 'to'
    function depositToWithPermit(address to, uint256 amount, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20WithPermit(address(ZBOOFI)).permit(msg.sender, address(this), value, deadline, v, r, s);
        _deposit(to, amount);
    }

    //withdraw funds and send them to message sender
    function withdraw(uint256 amount) external {
        _withdraw(msg.sender, amount);
    }

    //withdraw funds and send them to 'to'
    function withdrawTo(address to, uint256 amount) external {
        _withdraw(to, amount);
    }

    //OWNER-ONLY FUNCTIONS
    //in case the boofiDistributor needs to be changed
    function setBoofiDistributor(IBOOFI_Distributor _boofiDistributor) external onlyOwner {
        boofiDistributor = _boofiDistributor;
    }

    //recover ERC20 tokens other than BOOFI that have been sent mistakenly to the boofiDistributor address
    function recoverERC20FromDistributor(address token, address to) external onlyOwner {
        require(token != address(BOOFI));
        boofiDistributor.recoverERC20(token, to);
    }

    //recover ERC20 tokens other than BOOFI or zBOOFI that have been sent mistakenly to this address
    function recoverERC20(address token, address to) external onlyOwner {
        require(token != address(BOOFI) && token != address(ZBOOFI));
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, tokenBalance);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {
        //claim rewards if possible
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards > 0 && totalShares > 0) {
            boofiDistributor.distributeBOOFI();
        }
        //update boofiPerShare if the contract's balance has increased since last check
        uint256 bal = BOOFI.balanceOf(address(this));
        if (bal > storedBoofiBalance && totalShares > 0) {
            uint256 balanceDiff = bal - storedBoofiBalance;
            //update stored BOOFI Balance
            storedBoofiBalance = bal;
            boofiPerShare += ((balanceDiff * ACC_BOOFI_PRECISION) / totalShares);
        }
        _dailyUpdate();
    }

    function _harvest(address to) internal {
        uint256 rewardsOfShares = (shares[msg.sender] * boofiPerShare) / ACC_BOOFI_PRECISION;
        uint256 userPendingRewards = (rewardsOfShares - rewardDebt[msg.sender]);
        rewardDebt[msg.sender] = rewardsOfShares;
        if (userPendingRewards > 0) {
            totalHarvested += userPendingRewards;
            harvested[to] += userPendingRewards;
            _updateTopHarvesters(to);
            emit Harvest(msg.sender, to, userPendingRewards, harvested[to]);
            BOOFI.safeTransfer(to, userPendingRewards);
            //update stored BOOFI Balance
            storedBoofiBalance -= userPendingRewards;
        }
    }

    function _deposit(address to, uint256 amount) internal {
        _claimRewards();
        _harvest(to);
        if (amount > 0) {
            shares[to] += amount;
            totalShares += amount;
            rewardDebt[to] += (boofiPerShare * amount) / ACC_BOOFI_PRECISION;
            emit Deposit(msg.sender, to, amount);
            ZBOOFI.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _withdraw(address to, uint256 amount) internal {
        _claimRewards();
        _harvest(to);
        if (amount > 0) {
            require(shares[msg.sender] >= amount, "cannot withdraw more than staked");
            shares[msg.sender] -= amount;
            totalShares -= amount;
            rewardDebt[msg.sender] -= (boofiPerShare * amount) / ACC_BOOFI_PRECISION;
            emit Withdraw(msg.sender, to, amount);
            ZBOOFI.safeTransfer(to, amount);
        }
    }

    function _updateTopHarvesters(address user) internal {
        uint256 amountHarvested = harvested[user];

        //short-circuit logic to skip steps is user will not be in top harvesters array
        if (largestAmountsHarvested[(NUMBER_TOP_HARVESTERS - 1)] >= amountHarvested) {
            return;
        }

        //check if user already in list -- fetch index if they are
        uint256 i = 0;
        bool alreadyInList;
        for(i; i < NUMBER_TOP_HARVESTERS; i++) {
            if(topHarvesters[i] == user) {
                alreadyInList = true;
                break;
            }
        }   

        //get the index of the new element
        uint256 j = 0;
        for(j; j < NUMBER_TOP_HARVESTERS; j++) {
            if(largestAmountsHarvested[j] < amountHarvested) {
                break;
            }
        }   

        if (!alreadyInList) {
            //shift the array down by one position, as necessary
            for(uint256 k = (NUMBER_TOP_HARVESTERS - 1); k > j; k--) {
                largestAmountsHarvested[k] = largestAmountsHarvested[k - 1];
                topHarvesters[k] = topHarvesters[k - 1];
            //add in the new element, but only if it belongs in the array
            } if(j < (NUMBER_TOP_HARVESTERS - 1)) {
                largestAmountsHarvested[j] =  amountHarvested;
                topHarvesters[j] =  user;
            //update last array item in edge case where new amountHarvested is only larger than the smallest stored value
            } else if (largestAmountsHarvested[(NUMBER_TOP_HARVESTERS - 1)] < amountHarvested) {
                largestAmountsHarvested[j] =  amountHarvested;
                topHarvesters[j] =  user;
            }   

        //case handling for when user already holds a spot
        //check i>=j for the edge case of updates to tied positions
        } else if (i >= j) {
            //shift the array by one position, until the user's previous spot is overwritten
            for(uint256 m = i; m > j; m--) {
                largestAmountsHarvested[m] = largestAmountsHarvested[m - 1];
                topHarvesters[m] = topHarvesters[m - 1];
            }
            //add user back into array, in appropriate position
            largestAmountsHarvested[j] =  amountHarvested;
            topHarvesters[j] =  user;   

        //handle tie edge cases
        } else {
            //just need to update user's amountHarvested in this case
            largestAmountsHarvested[i] = amountHarvested;
        }
    }

    function _dailyUpdate() internal {
        if (timeSinceLastDailyUpdate() >= SECONDS_PER_DAY) {
            //store daily data
            //store boofiPerShare and timestamp
            historicBoofiPerShare.push(boofiPerShare);
            historicTimestamps.push(block.timestamp);
            numStoredDailyData += 1;

            //emit event
            emit DailyUpdate(numStoredDailyData, block.timestamp, boofiPerShare);

            //update rolling data
            rollingStartTimestamp = block.timestamp;
        }
    }
}
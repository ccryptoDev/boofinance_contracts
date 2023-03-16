// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IzBOOFI_WithdrawalFeeCalculator.sol";
import "./ERC20WithVotingAndPermit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// This contract handles swapping to and from zBOOFI, BooFinances's staking token.
contract ZombieBOOFI is ERC20WithVotingAndPermit("ZombieBOOFI", "zBOOFI"), Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable boofi;

    uint256 public constant MAX_WITHDRAWAL_FEE = 2500;
    uint256 public constant MAX_BIPS = 10000;
    uint256 public constant SECONDS_PER_DAY = 86400;
    //zBOOFI per BOOFI, scaled up by 1e18. e.g. 100e18 is 100 zBOOFI per BOOFI
    uint256 public constant INIT_EXCHANGE_RATE = 100e18;

    // tracks total deposits over all time
    uint256 public totalDeposits;
    // tracks total withdrawals over all time
    uint256 public totalWithdrawals;
    // Tracks total BOOFI that has been redistributed via the withdrawalFee.
    uint256 public fundsRedistributedByWithdrawalFee;
    // contract that calculates withdrawal fee
    address public withdrawalFeeCalculator;
    //tracks whether withdrawal fee is enabled or not
    bool withdrawalFeeEnabled;

    //stored historic exchange rates, historic withdrawal + deposit amounts, and their timestamps, separated by ~24 hour intervals
    uint256 public numStoredDailyData;
    uint256[] public historicExchangeRates;
    uint256[] public historicDepositAmounts;
    uint256[] public historicWithdrawalAmounts;
    uint256[] public historicTimestamps;

    //for tracking of statistics in trailing 24 hour period
    uint256 public rollingStartTimestamp;
    uint256 public rollingStartBoofiBalance;
    uint256 public rollingStartTotalDeposits;
    uint256 public rollingStartTotalWithdrawals;

    //stores deposits to help tracking of profits
    mapping(address => uint256) public deposits;
    //stores withdrawals to help tracking of profits
    mapping(address => uint256) public withdrawals;
    //stores cumulative amounts transferred in and out of each address, as BOOFI
    mapping(address => uint256) public transfersIn;
    mapping(address => uint256) public transfersOut;    

    event Enter(address indexed account, uint256 amount);
    event Leave(address indexed account, uint256 amount, uint256 shares);
    event WithdrawalFeeEnabled();
    event WithdrawalFeeDisabled();
    event DailyUpdate(
        uint256 indexed dayNumber,
        uint256 indexed timestamp,
        uint256 amountBoofiReceived,
        uint256 amountBoofiDeposited,
        uint256 amountBoofiWithdrawn
    );

    constructor(IERC20 _boofi) {
        boofi = _boofi;
        //push first "day" of historical data
        numStoredDailyData = 1;
        historicExchangeRates.push(1e36 / INIT_EXCHANGE_RATE);
        historicDepositAmounts.push(0);
        historicWithdrawalAmounts.push(0);
        historicTimestamps.push(block.timestamp);
        rollingStartTimestamp = block.timestamp;
        emit DailyUpdate(1, block.timestamp, 0, 0, 0);
    }

    //PUBLIC VIEW FUNCTIONS
    function boofiBalance() public view returns(uint256) {
        return boofi.balanceOf(address(this));
    }

    //returns current exchange rate of zBOOFI to BOOFI -- i.e. BOOFI per zBOOFI -- scaled up by 1e18
    function currentExchangeRate() public view returns(uint256) {
        uint256 totalShares = totalSupply();
        if(totalShares == 0) {
            return (1e36 / INIT_EXCHANGE_RATE);
        }
        return (boofiBalance() * 1e18) / totalShares;
    }

    //returns expected amount of zBOOFI from BOOFI deposit
    function expectedZBOOFI(uint256 amountBoofi) public view returns(uint256) {
        return (amountBoofi * 1e18) /  currentExchangeRate();
    }

    //returns expected amount of BOOFI from zBOOFI withdrawal
    function expectedBOOFI(uint256 amountZBoofi) public view returns(uint256) {
        return ((amountZBoofi * currentExchangeRate()) * (MAX_BIPS - withdrawalFee(amountZBoofi))) / (MAX_BIPS * 1e18);
    }

    //returns user profits in BOOFI, or negative if they have losses (due to withdrawal fee)
    function userProfits(address account) public view returns(int256) {
        uint256 userDeposits = deposits[account];
        uint256 userWithdrawals = withdrawals[account];
        uint256 totalShares = totalSupply();
        uint256 shareValue = (balanceOf(account) * boofiBalance()) / totalShares;
        uint256 totalAssets = userWithdrawals + shareValue;
        return int256(int256(totalAssets) - int256(userDeposits));
    }

    //similar to 'userProfits', but counts transfersIn as deposits and transfers out as withdrawals
    function userProfitsIncludingTransfers(address account) public view returns(int256) {
        uint256 userDeposits = deposits[account] + transfersIn[account];
        uint256 userWithdrawals = withdrawals[account] + transfersOut[account];
        uint256 totalShares = totalSupply();
        uint256 shareValue = (balanceOf(account) * boofiBalance()) / totalShares;
        uint256 totalAssets = userWithdrawals + shareValue;
        return int256(int256(totalAssets) - int256(userDeposits));
    }

    //returns most recent stored exchange rate and the time at which it was stored
    function getLatestStoredExchangeRate() public view returns(uint256, uint256) {
        return (historicExchangeRates[numStoredDailyData - 1], historicTimestamps[numStoredDailyData - 1]);
    }

    //returns last amountDays of stored exchange rate datas
    function getExchangeRateHistory(uint256 amountDays) public view returns(uint256[] memory, uint256[] memory) {
        uint256 endIndex = numStoredDailyData - 1;
        uint256 startIndex = (amountDays > endIndex) ? 0 : (endIndex - amountDays + 1);
        uint256 length = endIndex - startIndex + 1;
        uint256[] memory exchangeRates = new uint256[](length);
        uint256[] memory timestamps = new uint256[](length);
        for(uint256 i = startIndex; i <= endIndex; i++) {
            exchangeRates[i - startIndex] = historicExchangeRates[i];
            timestamps[i - startIndex] = historicTimestamps[i];            
        }
        return (exchangeRates, timestamps);
    }

    //returns most recent stored daily deposit amount and the time at which it was stored
    function getLatestStoredDepositAmount() public view returns(uint256, uint256) {
        return (historicDepositAmounts[numStoredDailyData - 1], historicTimestamps[numStoredDailyData - 1]);
    }

    //returns last amountDays of stored daily deposit amount datas
    function getDepositAmountHistory(uint256 amountDays) public view returns(uint256[] memory, uint256[] memory) {
        uint256 endIndex = numStoredDailyData - 1;
        uint256 startIndex = (amountDays > endIndex) ? 0 : (endIndex - amountDays + 1);
        uint256 length = endIndex - startIndex + 1;
        uint256[] memory depositAmounts = new uint256[](length);
        uint256[] memory timestamps = new uint256[](length);
        for(uint256 i = startIndex; i <= endIndex; i++) {
            depositAmounts[i - startIndex] = historicDepositAmounts[i];
            timestamps[i - startIndex] = historicTimestamps[i];            
        }
        return (depositAmounts, timestamps);
    }

    //returns most recent stored daily withdrawal amount and the time at which it was stored
    function getLatestStoredWithdrawalAmount() public view returns(uint256, uint256) {
        return (historicWithdrawalAmounts[numStoredDailyData - 1], historicTimestamps[numStoredDailyData - 1]);
    }

    //returns last amountDays of stored daily withdrawal amount datas
    function getWithdrawalAmountHistory(uint256 amountDays) public view returns(uint256[] memory, uint256[] memory) {
        uint256 endIndex = numStoredDailyData - 1;
        uint256 startIndex = (amountDays > endIndex) ? 0 : (endIndex - amountDays + 1);
        uint256 length = endIndex - startIndex + 1;
        uint256[] memory withdrawalAmounts = new uint256[](length);
        uint256[] memory timestamps = new uint256[](length);
        for(uint256 i = startIndex; i <= endIndex; i++) {
            withdrawalAmounts[i - startIndex] = historicWithdrawalAmounts[i];
            timestamps[i - startIndex] = historicTimestamps[i];            
        }
        return (withdrawalAmounts, timestamps);
    }

    //tracks the amount of BOOFI the contract has received as rewards so far today
    function rewardsToday() public view returns(uint256) {
        // Gets the current BOOFI balance of the contract
        uint256 totalBoofi = boofiBalance();
        // gets deposits during the period
        uint256 depositsDuringPeriod = depositsToday();
        // gets withdrawals during the period
        uint256 withdrawalsDuringPeriod = withdrawalsToday();
        // net rewards received is (new boofi balance - old boofi balance) + (withdrawals - deposits)
        return ((totalBoofi + withdrawalsDuringPeriod) - (depositsDuringPeriod + rollingStartBoofiBalance));
    }

    //tracks the amount of BOOFI deposited to the contract so far today
    function depositsToday() public view returns(uint256) {
        uint256 depositsDuringPeriod = totalDeposits - rollingStartTotalDeposits;
        return depositsDuringPeriod;
    }

    //tracks the amount of BOOFI withdrawn from the contract so far today
    function withdrawalsToday() public view returns(uint256) {
        uint256 withdrawalsDuringPeriod = totalWithdrawals - rollingStartTotalWithdrawals;
        return withdrawalsDuringPeriod;
    }

    function timeSinceLastDailyUpdate() public view returns(uint256) {
        return (block.timestamp - rollingStartTimestamp);
    }

    //calculates and returns the current withdrawalFee, in BIPS
    function withdrawalFee() public view returns(uint256) {
        if (!withdrawalFeeEnabled) {
            return 0;
        } else {
            uint256 withdrawalFeeValue = IzBOOFI_WithdrawalFeeCalculator(withdrawalFeeCalculator).withdrawalFee(0);
            if (withdrawalFeeValue >= MAX_WITHDRAWAL_FEE) {
                return MAX_WITHDRAWAL_FEE;
            } else {
                return withdrawalFeeValue;
            }
        }
    }

    //calculates and returns the expected withdrawalFee, in BIPS, for a withdrawal of '_share' zBOOFI
    function withdrawalFee(uint256 _share) public view returns(uint256) {
        if (!withdrawalFeeEnabled) {
            return 0;
        } else {
            uint256 withdrawalFeeValue = IzBOOFI_WithdrawalFeeCalculator(withdrawalFeeCalculator).withdrawalFee(_share);
            if (withdrawalFeeValue >= MAX_WITHDRAWAL_FEE) {
                return MAX_WITHDRAWAL_FEE;
            } else {
                return withdrawalFeeValue;
            }
        }
    }

    //EXTERNAL FUNCTIONS
    // Enter the contract. Pay some BOOFI. Earn some shares.
    // Locks BOOFI and mints zBOOFI
    function enter(uint256 _amount) external {
        _enter(msg.sender, _amount);
    }

    //similar to 'enter', but sends new zBOOFI to address '_to'
    function enterFor(address _to, uint256 _amount) external {
        _enter(_to, _amount);
    }

    // Leave the vault. Claim back your BOOFI.
    // Unlocks the staked + gained BOOFI and redistributes zBOOFI.
    function leave(uint256 _share) external {
        _leave(msg.sender, _share);
    }

    //similar to 'leave', but sends the unlocked BOOFI to address '_to'
    function leaveTo(address _to, uint256 _share) external {
        _leave(_to, _share);
    }

    //similar to 'leave', but the transaction reverts if the dynamic withdrawal fee is above 'maxWithdrawalFee' when the transaction is mined
    function leaveWithMaxWithdrawalFee(uint256 _share, uint256 maxWithdrawalFee) external {
        require(maxWithdrawalFee <= MAX_WITHDRAWAL_FEE, "maxWithdrawalFee input too high. tx will always fail");
        require(withdrawalFee(_share) <= maxWithdrawalFee, "withdrawalFee slippage");
        _leave(msg.sender, _share);
    }

    //similar to 'leaveWithMaxWithdrawalFee', but sends the unlocked BOOFI to address '_to'
    function leaveToWithMaxWithdrawalFee(address _to, uint256 _share, uint256 maxWithdrawalFee) external {
        require(maxWithdrawalFee <= MAX_WITHDRAWAL_FEE, "maxWithdrawalFee input too high. tx will always fail");
        require(withdrawalFee(_share) <= maxWithdrawalFee, "withdrawalFee slippage");
        _leave(_to, _share);
    }

    //OWNER-ONLY FUNCTIONS
    function enableWithdrawalFee() external onlyOwner {
        require(!withdrawalFeeEnabled, "withdrawal fee already enabled");
        withdrawalFeeEnabled = true;
        emit WithdrawalFeeEnabled();
    }

    function disableWithdrawalFee() external onlyOwner {
        require(withdrawalFeeEnabled, "withdrawal fee already disabled");
        withdrawalFeeEnabled = false;
        emit WithdrawalFeeDisabled();
    }

    function setWithdrawalFeeCalculator(address _withdrawalFeeCalculator) external onlyOwner {
        withdrawalFeeCalculator = _withdrawalFeeCalculator;
    }

    //INTERNAL FUNCTIONS
    function _dailyUpdate() internal {
        if (timeSinceLastDailyUpdate() >= SECONDS_PER_DAY) {
            //repeat of rewardsReceived() logic
            // Gets the current BOOFI balance of the contract
            uint256 totalBoofi = boofiBalance();
            // gets deposits during the period
            uint256 depositsDuringPeriod = totalDeposits - rollingStartTotalDeposits;
            // gets withdrawals during the period
            uint256 withdrawalsDuringPeriod = totalWithdrawals - rollingStartTotalWithdrawals;
            // net rewards received is (new boofi balance - old boofi balance) + (withdrawals - deposits)
            uint256 rewardsReceivedDuringPeriod = ((totalBoofi + withdrawalsDuringPeriod) - (depositsDuringPeriod + rollingStartBoofiBalance));

            //store daily data
            //store exchange rate and timestamp
            historicExchangeRates.push(currentExchangeRate());
            historicDepositAmounts.push(depositsDuringPeriod);
            historicWithdrawalAmounts.push(withdrawalsDuringPeriod);
            historicTimestamps.push(block.timestamp);
            numStoredDailyData += 1;

            //emit event
            emit DailyUpdate(numStoredDailyData, block.timestamp, rewardsReceivedDuringPeriod, depositsDuringPeriod, withdrawalsDuringPeriod);

            //update rolling data
            rollingStartTimestamp = block.timestamp;
            rollingStartBoofiBalance = boofiBalance();
            rollingStartTotalDeposits = totalDeposits;
            rollingStartTotalWithdrawals = totalWithdrawals;
        }
    }

    //tracking for profits on transfers
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        // Gets the amount of zBOOFI in existence
        uint256 totalShares = totalSupply();
        // Gets the current BOOFI balance of the contract
        uint256 totalBoofi = boofiBalance();
        uint256 boofiValueOfShares = (amount * totalBoofi) / totalShares;
        // take part of profit tracking
        transfersIn[recipient] += boofiValueOfShares;
        transfersOut[sender] += boofiValueOfShares;
        //perform the internal transfer
        super._transfer(sender, recipient, amount);
    }

    function _enter(address recipient, uint256 _amount) internal {
        // Gets the amount of BOOFI locked in the contract
        uint256 totalBoofi = boofiBalance();
        // Gets the amount of zBOOFI in existence
        uint256 totalShares = totalSupply();
        // If no zBOOFI exists, mint it according to the initial exchange rate
        if (totalShares == 0 || totalBoofi == 0) {
            _mint(recipient, (_amount * (INIT_EXCHANGE_RATE) / 1e18));
        }
        // Calculate and mint the amount of zBOOFI the BOOFI is worth.
        // The ratio will change over time, as zBOOFI is burned/minted and BOOFI
        // deposited + gained from fees / withdrawn.
        else {
            uint256 what = (_amount * totalShares) / totalBoofi;
            _mint(recipient, what);
        }
        //track deposited BOOFI
        deposits[recipient] = deposits[recipient] + _amount;
        totalDeposits += _amount;
        // Lock the BOOFI in the contract
        boofi.safeTransferFrom(msg.sender, address(this), _amount);

        _dailyUpdate();

        emit Enter(recipient, _amount);
    }

    function _leave(address recipient, uint256 _share) internal {
        // Gets the amount of zBOOFI in existence
        uint256 totalShares = totalSupply();
        // Gets the BOOFI balance of the contract
        uint256 totalBoofi = boofiBalance();  
        // Calculates the amount of BOOFI the zBOOFI is worth      
        uint256 what = (_share * totalBoofi) / totalShares;
        //burn zBOOFI
        _burn(msg.sender, _share);
        //calculate and track tax
        uint256 tax = (what * withdrawalFee(_share)) / MAX_BIPS;
        uint256 toSend = what - tax;
        fundsRedistributedByWithdrawalFee += tax;
        //track withdrawn BOOFI
        withdrawals[recipient] += toSend;
        totalWithdrawals += toSend;
        //Send the person's BOOFI to their address
        boofi.safeTransfer(recipient, toSend);
        
        _dailyUpdate();

        emit Leave(recipient, what, _share);
    }
}
 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./interfaces/IRewarder.sol";
import "./interfaces/IBoofiStrategy.sol";
import "./interfaces/IBOOFI.sol";
import "./interfaces/IZBOOFI.sol";
import "./interfaces/IOracle.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HauntedHouse is Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many shares the user currently has
        int256 rewardDebt; // Reward debt. At any time, the amount of pending zBOOFI for a user is ((user.amount * accZBOOFIPerShare) / ACC_BOOFI_PRECISION) - user.rewardDebt
    }

    // Info of each accepted token.
    struct TokenInfo {
        IRewarder rewarder; // Address of rewarder for token
        IBoofiStrategy strategy; // Address of strategy for token
        uint256 lastRewardTime; // Last time that zBOOFI distribution occurred for this token
        uint256 lastCumulativeReward; // Value of cumulativeAvgZboofiPerWeightedValueLocked at last update
        uint256 storedPrice; // Latest value of token
        uint256 accZBOOFIPerShare; // Accumulated zBOOFI per share, times ACC_BOOFI_PRECISION.
        uint256 totalShares; //total number of shares for the token
        uint256 totalTokens; //total number of tokens deposited
        uint128 multiplier; // multiplier for this token
        uint16 withdrawFeeBP; // Withdrawal fee in basis points
    }

    // The BOOFI TOKEN!
    IBOOFI public immutable BOOFI;
    // The ZBOOFI TOKEN
    IZBOOFI public immutable ZBOOFI;
    // The timestamp when mining starts.
    uint256 public startTime;

    // global reward and weighted TVL tracking
    uint256 public weightedTotalValueLocked;
    uint256 public cumulativeAvgZboofiPerWeightedValueLocked;
    uint256 public lastAvgUpdateTimestamp;

    //endowment addresses
    address public dev;
    address public marketingAndCommunity;
    address public partnership;
    address public foundation;
    address public zBoofiStaking;
    //address to receive BOOFI purchased by strategies
    address public strategyPool;
    //performance fee address -- receives "performance fees" from strategies
    address public performanceFeeAddress;

    uint256 public constant devBips = 625;
    uint256 public constant marketingAndCommunityBips = 625;
    uint256 public constant partnershipBips = 625;
    uint256 public constant foundationBips = 1750;
    uint256 public zBoofiStakingBips = 0;
    //sum of the above endowment bips
    uint256 public totalEndowmentBips = devBips + marketingAndCommunityBips + partnershipBips + foundationBips + zBoofiStakingBips;

    //amount currently withdrawable by endowments
    uint256 public endowmentBal;

    //address that controls updating prices of deposited tokens
    address public priceUpdater;

    // amount of BOOFI emitted per second
    uint256 public boofiEmissionPerSecond;

    //whether auto-updating of prices is turned on or off. off by default
    bool public autoUpdatePrices;
    //address of oracle for auto-updates
    address public oracle;

    uint256 internal constant ACC_BOOFI_PRECISION = 1e18;
    uint256 internal constant BOOFI_PRECISION_SQUARED = 1e36;
    uint256 internal constant MAX_BIPS = 10000;
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // list of tokens currently approved for deposit
    address[] public approvedTokenList;
    //mapping to track token positions in approvedTokenList
    mapping(address => uint256) public tokenListPosition;
    //mapping for tracking contracts approved to call into this one
    mapping(address => bool) public approvedContracts;
    //mapping for tracking whether or not a token is approved for deposit
    mapping(address => bool) public approvedTokens;
    // Info for all accepted tokens
    mapping(address => TokenInfo) public tokenParameters;
    // tracks if tokens have been added before, to ensure they are not added multiple times
    mapping(address => bool) public tokensAdded;
    // Info of each user that stakes tokens. stored as userInfo[token][userAddress]
    mapping(address => mapping(address => UserInfo)) public userInfo;
    //tracks historic deposits of each address. deposits[token][user] is the total deposits of 'token' for 'user', cumulative over all time
    mapping(address => mapping(address => uint256)) public deposits;
    //tracks historic withdrawals of each address. deposits[token][user] is the total withdrawals of 'token' for 'user', cumulative over all time
    mapping(address => mapping(address => uint256)) public withdrawals;
    //access control roles -- given to owner by default, who can reassign as necessary
    //role 0 can modify the approved token list and add new tokens
    //role 1 can change token multipliers, rewarders, and withdrawFeeBPs
    //role 2 can adjust endowment, strategyPool, and price updater addresses
    //role 3 has ability to modify the BOOFI emission rate
    //role 4 controls access for other contracts, whether automatic price updating is on or off, and the oracle address for this
    //role 5 has strategy management powers
    mapping(uint256 => address) public roles;

    /**
     * @notice Throws if called by non-approved smart contract
     */
    modifier onlyApprovedContractOrEOA() {
        require(tx.origin == msg.sender || approvedContracts[msg.sender], "onlyApprovedContractOrEOA");
        _;
    }

    modifier onlyRole(uint256 role) {
        if (roles[role] == address(0)) {
            require(msg.sender == owner(), "only owner");
        } else {
            require(msg.sender == roles[role], "only role");            
        }
        _;
    }

    event Deposit(address indexed user, address indexed token, uint256 amount, address indexed to);
    event Withdraw(address indexed user, address indexed token, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, address indexed token, uint256 amount, address indexed to);
    event Harvest(address indexed user, address indexed token, uint256 amountBOOFI);
    event BoofiEmissionSet(uint256 newBoofiEmissionPerSecond);
    event DevSet(address indexed oldAddress, address indexed newAddress);
    event MarketingAndCommunitySet(address indexed oldAddress, address indexed newAddress);
    event PartnershipSet(address indexed oldAddress, address indexed newAddress);
    event FoundationSet(address indexed oldAddress, address indexed newAddress);
    event ZboofiStakingSet(address indexed oldAddress, address indexed newAddress);
    event StrategyPoolSet(address indexed oldAddress, address indexed newAddress);
    event PerformanceFeeAddressSet(address indexed oldAddress, address indexed newAddress);
    event PriceUpdaterSet(address indexed oldAddress, address indexed newAddress);
    event OracleSet(address indexed oldAddress, address indexed newAddress);
    event RoleTransferred(uint256 role, address indexed oldAddress, address indexed newAddress);

    constructor(
        IBOOFI _BOOFI,
        IZBOOFI _ZBOOFI,
        uint256 _startTime,
        address _dev,
        address _marketingAndCommunity,
        address _partnership,
        address _foundation,
        address _strategyPool,
        address _performanceFeeAddress,
        uint256 _boofiEmissionPerSecond 
    ) {
        require(_startTime > block.timestamp, "need future");
        BOOFI = _BOOFI;
        ZBOOFI = _ZBOOFI;
        _BOOFI.approve(address(_ZBOOFI), MAX_UINT);
        startTime = _startTime;
        setEndowment(0, _dev);
        setEndowment(1, _marketingAndCommunity);
        setEndowment(2, _partnership);
        setEndowment(3, _foundation);
        setStrategyPool(_strategyPool);
        setPerformanceFeeAddress(_performanceFeeAddress);
        boofiEmissionPerSecond = _boofiEmissionPerSecond;
        //update this value so function '_globalUpdate()' will do nothing before _startTime
        lastAvgUpdateTimestamp = _startTime;
        emit BoofiEmissionSet(_boofiEmissionPerSecond);
    }

    //VIEW FUNCTIONS
    function tokenListLength() public view returns (uint256) {
        return approvedTokenList.length;
    }

    function tokenList() external view returns (address[] memory) {
        return approvedTokenList;
    }

    // View function to see total pending reward in zBOOFI on frontend.
    function pendingZBOOFI(address token, address userAddress) public view returns (uint256) {
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][userAddress];
        uint256 accZBOOFIPerShare = tokenInfo.accZBOOFIPerShare;
        uint256 poolShares = tokenInfo.totalShares;
        //mimic global update
        uint256 globalCumulativeAverage = cumulativeAvgZboofiPerWeightedValueLocked;
        if (block.timestamp > lastAvgUpdateTimestamp && weightedTotalValueLocked > 0) {
            uint256 newBOOFI  = (block.timestamp - lastAvgUpdateTimestamp) * boofiEmissionPerSecond;
            uint256 endowmentAmount = (newBOOFI * totalEndowmentBips) / MAX_BIPS;
            uint256 finalAmount = newBOOFI - endowmentAmount;
            //convert BOOFI to zBOOFI. factor of 1e18 is because of exchange rate scaling
            uint256 newZBOOFI = ZBOOFI.expectedZBOOFI(finalAmount);
            //NOTE: large scaling here, as divisor is enormous
            globalCumulativeAverage += (newZBOOFI * BOOFI_PRECISION_SQUARED) / weightedTotalValueLocked;
        }
        //mimic single token update
        if (block.timestamp > tokenInfo.lastRewardTime) {
            uint256 cumulativeRewardDiff = (cumulativeAvgZboofiPerWeightedValueLocked - tokenInfo.lastCumulativeReward);
            //NOTE: inverse scaling to that performed in calculating cumulativeAvgZboofiPerWeightedValueLocked
            uint256 zboofiReward = (cumulativeRewardDiff * tokenWeightedValueLocked(token)) / BOOFI_PRECISION_SQUARED;
            if (zboofiReward > 0) {
                accZBOOFIPerShare += (zboofiReward * ACC_BOOFI_PRECISION) / poolShares;
            }
        }
        return _toUInt256(int256((user.amount * accZBOOFIPerShare) / ACC_BOOFI_PRECISION) - user.rewardDebt);
    }

    // view function to get all pending rewards, from HauntedHouse and Rewarder
    function pendingTokens(address token, address user) external view 
        returns (address[] memory, uint256[] memory) {
        (address[] memory strategyTokens, uint256[] memory strategyRewards) = IBoofiStrategy (tokenParameters[token].strategy).pendingTokens(user);
        address[] memory rewarderTokens;
        uint256[] memory rewarderRewards;
        if (address(tokenParameters[token].rewarder) != address(0)) {
            (rewarderTokens, rewarderRewards) = tokenParameters[token].rewarder.pendingTokens(token, user);
        }
        uint256 numStrategyTokens = strategyTokens.length;
        uint256 numRewarderTokens = rewarderTokens.length;        
        uint256 rewardsLength = 1 + numStrategyTokens + numRewarderTokens;
        address[] memory _rewardTokens = new address[](rewardsLength);
        uint256[] memory _pendingAmounts = new uint256[](rewardsLength);
        _rewardTokens[0] = address(ZBOOFI);
        _pendingAmounts[0] = pendingZBOOFI(token, user);
        for (uint256 i = 0; i < numStrategyTokens; i ++) {
            _rewardTokens[i + 1] = strategyTokens[i];
            _pendingAmounts[i + 1] = strategyRewards[i];
        }
        for (uint256 j = 0; j < numRewarderTokens; j++) {
            _rewardTokens[j + numStrategyTokens + 1] = rewarderTokens[j];
            _pendingAmounts[j + numStrategyTokens + 1] = rewarderRewards[j];
        }
        return(_rewardTokens, _pendingAmounts);
    }

    //returns user profits in token due to withdrawal fees (negative in the case that the user has net losses due to previous withdrawal fees)
    function profitInLP(address token, address userAddress) external view returns(int256) {
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][userAddress];
        uint256 userDeposits = deposits[token][userAddress];
        uint256 userWithdrawals = withdrawals[token][userAddress];
        uint256 tokensFromShares = (user.amount * tokenInfo.totalTokens) / tokenInfo.totalShares;
        uint256 totalAssets = userWithdrawals + tokensFromShares;
        return (int256(totalAssets) - int256(userDeposits));
    }

    //convenience function to get the emission of BOOFI at the current emission + exchange rates, to depositors of a given token, accounting for endowment distribution
    function boofiPerSecondToToken(address token) public view returns(uint256) {
        return ((boofiEmissionPerSecond * tokenWeightedValueLocked(token)) * (MAX_BIPS - totalEndowmentBips) / MAX_BIPS) / weightedTotalValueLocked;
    }

    //function to get the emission of zBOOFI per second at the current emission rate, at the current exchange rate, accounting for endowment distribution
    function zboofiPerSecond() external view returns (uint256) {
        return ZBOOFI.expectedZBOOFI((boofiEmissionPerSecond * (MAX_BIPS - totalEndowmentBips)) / MAX_BIPS);
    }

    //convenience function to get the annualized emission of ZBOOFI at the current emission + exchange rates, to depositors of a given token, accounting for endowment distribution
    function zboofiPerSecondToToken(address token) external view returns(uint256) {
        return ZBOOFI.expectedZBOOFI(boofiPerSecondToToken(token));
    }

    //function to get current value locked from a single token
    function tokenValueLocked(address token) public view returns (uint256) {
        return (tokenParameters[token].totalTokens * tokenParameters[token].storedPrice);
    }

    //get current value locked for a single token, multiplied by the token's multiplier
    function tokenWeightedValueLocked(address token) public view returns (uint256) {
        return (tokenValueLocked(token) * tokenParameters[token].multiplier);
    }

    //WRITE FUNCTIONS
    /// @notice Update reward variables of the given token.
    /// @param token The address of the deposited token.
    function updateTokenRewards(address token) external onlyApprovedContractOrEOA {
        _updateTokenRewards(token);
    }

    // Update reward variables for all approved tokens. Be careful of gas spending!
    function massUpdateTokens() external onlyApprovedContractOrEOA {
        uint256 length = tokenListLength();
        _globalUpdate();
        for (uint256 i = 0; i < length; i++) {
            _tokenUpdate(approvedTokenList[i]);
        }
    }

    /// @notice Deposit tokens to HauntedHouse for zBOOFI allocation.
    /// @param token The address of the token to deposit
    /// @param amount Token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(address token, uint256 amount, address to) external onlyApprovedContractOrEOA {
        _deposit(token, amount, to);
    }

    //convenience function
    function deposit(address token, uint256 amount) external onlyApprovedContractOrEOA {
        _deposit(token, amount, msg.sender);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param token The address of the deposited token.
    /// @param to Receiver of BOOFI rewards.
    function harvest(address token, address to) external onlyApprovedContractOrEOA {
        _harvest(token, to);
    }

    //convenience function
    function harvest(address token) external onlyApprovedContractOrEOA {
        _harvest(token, msg.sender);
    }

    //convenience function to batch harvest tokens
    function batchHarvest(address[] calldata tokens) external onlyApprovedContractOrEOA {
        for (uint256 i = 0; i < tokens.length; i++) {
            _harvest(tokens[i], msg.sender);
        }
    }

    //convenience function to batch harvest tokens
    function batchHarvest(address[] calldata tokens, address to) external onlyApprovedContractOrEOA {
        for (uint256 i = 0; i < tokens.length; i++) {
            _harvest(tokens[i], to);
        }
    }

    /// @notice Withdraw tokens from HauntedHouse.
    /// @param token The address of the withdrawn token.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the tokens.
    function withdraw(address token, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        _withdraw(token, amountShares, to);
    }

    //convenience function
    function withdraw(address token, uint256 amountShares) external onlyApprovedContractOrEOA {
        _withdraw(token, amountShares, msg.sender);
    }

    /// @notice Withdraw tokens from HauntedHouse and harvest pending rewards
    /// @param token The address of the withdrawn token.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the tokens.
    function withdrawAndHarvest(address token, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        _withdrawAndHarvest(token, amountShares, to);
    }

    //convenience function
    function withdrawAndHarvest(address token, uint256 amountShares) external onlyApprovedContractOrEOA {
        _withdrawAndHarvest(token, amountShares, msg.sender);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param token The address of the withdrawn token.
    /// @param to Receiver of the tokens.
    function emergencyWithdraw(address token, address to) external onlyApprovedContractOrEOA {
        _emergencyWithdraw(token, to);
    }

    //convenience function
    function emergencyWithdraw(address token) external onlyApprovedContractOrEOA {
        _emergencyWithdraw(token, msg.sender);
    }

    //distribute pending endowment funds. callable by anyone.
    function distributeEndowment() external {
        uint256 totalToSend = endowmentBal;
        endowmentBal = 0;
        uint256 toDev = (totalToSend * devBips) / totalEndowmentBips;
        uint256 toMarketingAndCommunity = (totalToSend * marketingAndCommunityBips) / totalEndowmentBips;
        uint256 toPartnership = (totalToSend * partnershipBips) / totalEndowmentBips;
        uint256 toFoundation = (totalToSend * foundationBips) / totalEndowmentBips;
        if (zBoofiStakingBips > 0) {
            uint256 toZboofiStaking = (totalToSend * zBoofiStakingBips) / totalEndowmentBips;
            _safeBOOFITransfer(zBoofiStaking, toZboofiStaking); 
        }
        _safeBOOFITransfer(dev, toDev);
        _safeBOOFITransfer(marketingAndCommunity, toMarketingAndCommunity);
        _safeBOOFITransfer(partnership, toPartnership);
        _safeBOOFITransfer(foundation, toFoundation);
    }

    //ACCESS-CONTROLLED FUNCTIONS
    function setRole(uint256 role, address holder) external onlyOwner {
        emit RoleTransferred(role, roles[role], holder);
        roles[role] = holder;
    }

    //modifies whether 'token' is in the approved list of tokens or not. only approved tokens can be deposited.
    function modifyApprovedToken(address token, bool status) external onlyRole(0) {
        _modifyApprovedToken(token, status);
    }

    /// @notice Add parameters to a new token.
    /// @param token the token address
    /// @param _withdrawFeeBP withdrawal fee of the token.
    /// @param _multiplier token multiplier for weighted TVL
    /// @param _rewarder Address of the rewarder delegate.
    /// @param _strategy Address of the strategy delegate.
    function add(address token, uint16 _withdrawFeeBP, uint128 _multiplier, IRewarder _rewarder, IBoofiStrategy _strategy)
        external onlyRole(0) {
        require(
            _withdrawFeeBP <= 1000,
            "_withdrawFeeBP high"
        );
        //track adding token
        require(!tokensAdded[token], "cannot add token 2x");
        tokensAdded[token] = true;
        //approve token if it is not already approved
        _modifyApprovedToken(token, true);
        //do global update to rewards before adding new token
        _globalUpdate();
        uint256 _lastRewardTime =
            block.timestamp > startTime ? block.timestamp : startTime;
        tokenParameters[token] = (
            TokenInfo({
                rewarder: _rewarder, // Address of rewarder for token
                strategy: _strategy, // Address of strategy for token
                multiplier: _multiplier, // multiplier for this token
                lastRewardTime: _lastRewardTime, // Last time that zBOOFI distribution occurred for this token
                lastCumulativeReward: cumulativeAvgZboofiPerWeightedValueLocked, // Value of cumulativeAvgZboofiPerWeightedValueLocked at last update
                storedPrice: 0, // Latest value of token
                accZBOOFIPerShare: 0, // Accumulated zBOOFI per share, times ACC_BOOFI_PRECISION.
                withdrawFeeBP: _withdrawFeeBP, // Withdrawal fee in basis points
                totalShares: 0, //total number of shares for the token
                totalTokens: 0 //total number of tokens deposited
            })
        );
    }

    /// @notice Update the given token's withdrawal fee BIPS.
    /// @param token the token address
    /// @param _withdrawFeeBP new withdrawal fee BIPS value
    function changeWithdrawFeeBP(address token, uint16 _withdrawFeeBP) external onlyRole(1) {
        require(
            _withdrawFeeBP <= 1000,
            "_withdrawFeeBP high"
        );
        tokenParameters[token].withdrawFeeBP = _withdrawFeeBP;
    }

    /// @notice Update the given token's rewarder contract.
    /// @param token the token address
    /// @param _rewarder Address of the rewarder delegate.
    function changeRewarder(address token, IRewarder _rewarder) external onlyRole(1) {
        tokenParameters[token].rewarder = _rewarder;
    }

    /// @notice Update the given tokens' multiplier factors
    /// @param tokens the token addresses
    /// @param _multipliers new token multipliers for weighted TVL
    function changeMultipliers(address[] calldata tokens, uint128[] calldata _multipliers) external onlyRole(1) {
        require(tokens.length == _multipliers.length, "inputs");
        //do global update to rewards before updating tokens
        _globalUpdate();
        for (uint256 i = 0; i < tokens.length; i++) {
            //do single token update to ensure that each token gets any zBOOFI accumulated up to this point in time, based on past multiplier
            _tokenUpdate(tokens[i]);
            //update the multiplier and adjust the weighted TVL
            weightedTotalValueLocked -= tokenWeightedValueLocked(tokens[i]);
            tokenParameters[tokens[i]].multiplier = _multipliers[i];
            weightedTotalValueLocked += tokenWeightedValueLocked(tokens[i]);
        }
    }

    function setEndowment(uint256 endowmentRole, address _newAddress) public onlyRole(2) {
        require(_newAddress != address(0));
        if (endowmentRole == 0) {
            emit DevSet(dev, _newAddress);
            dev = _newAddress;            
        } else if (endowmentRole == 1) {
            emit MarketingAndCommunitySet(marketingAndCommunity, _newAddress);
            marketingAndCommunity = _newAddress;
        } else if (endowmentRole == 2) {
            emit PartnershipSet(partnership, _newAddress);
            partnership = _newAddress;
        } else if (endowmentRole == 3) {
            emit FoundationSet(foundation, _newAddress);
            foundation = _newAddress;
        } else if (endowmentRole == 4) {
            emit ZboofiStakingSet(zBoofiStaking, _newAddress);
            zBoofiStaking = _newAddress;
        }
    }

    function setPerformanceFeeAddress(address _performanceFeeAddress) public onlyRole(2) {
        require(_performanceFeeAddress != address(0));
        emit PerformanceFeeAddressSet(performanceFeeAddress, _performanceFeeAddress);
        performanceFeeAddress = _performanceFeeAddress;
    }

    function setStrategyPool(address _strategyPool) public onlyRole(2) {
        require(_strategyPool != address(0));
        emit StrategyPoolSet(strategyPool, _strategyPool);
        strategyPool = _strategyPool;
    }

    function setZBoofiStakingBips(uint256 _zBoofiStakingBips) external onlyRole(2) {
        require(zBoofiStaking != address(0), "not set yet");
        require(totalEndowmentBips + _zBoofiStakingBips <= MAX_BIPS);
        totalEndowmentBips -= zBoofiStakingBips;
        totalEndowmentBips += _zBoofiStakingBips;
        zBoofiStakingBips = _zBoofiStakingBips;
    }

    function setPriceUpdater(address _priceUpdater) external onlyRole(2) {
        require(_priceUpdater != address(0));
        emit PriceUpdaterSet(priceUpdater, _priceUpdater);
        priceUpdater = _priceUpdater;
    }

    function setBoofiEmission(uint256 newBoofiEmissionPerSecond) external onlyRole(3) {
        _globalUpdate();
        boofiEmissionPerSecond = newBoofiEmissionPerSecond;
        emit BoofiEmissionSet(newBoofiEmissionPerSecond);
    }

    function modifyApprovedContracts(address[] calldata contracts, bool[] calldata statuses) external onlyRole(4) {
        require(contracts.length == statuses.length, "inputs");
        for (uint256 i = 0; i < contracts.length; i++) {
            approvedContracts[contracts[i]] = statuses[i];
        }
    }

    function setAutoUpdatePrices(bool newStatus) external onlyRole(4) {
        autoUpdatePrices = newStatus;
    }

    function setOracle(address _oracle) external onlyRole(4) {
        emit OracleSet(oracle, _oracle);
        oracle = _oracle;
    }

    //STRATEGY MANAGEMENT FUNCTIONS
    function inCaseTokensGetStuck(address token, address to, uint256 amount) external onlyRole(5) {
        IBoofiStrategy strat = tokenParameters[token].strategy;
        strat.inCaseTokensGetStuck(IERC20(token), to, amount);
    }

    function setPerformanceFeeBips(IBoofiStrategy strat, uint256 newPerformanceFeeBips) external onlyRole(5) {
        strat.setPerformanceFeeBips(newPerformanceFeeBips);
    }

    //used to migrate from using one strategy to another
    function migrateStrategy(address token, IBoofiStrategy newStrategy) external onlyRole(5) {
        TokenInfo storage tokenInfo = tokenParameters[token];
        //migrate funds from old strategy to new one
        tokenInfo.strategy.migrate(address(newStrategy));
        //update strategy in storage
        tokenInfo.strategy = newStrategy;
        newStrategy.onMigration();
    }

    //used in emergencies, or if setup of a strategy fails
    function setStrategy(address token, IBoofiStrategy newStrategy, bool transferOwnership, address newOwner) 
        external onlyRole(5) {
        TokenInfo storage tokenInfo = tokenParameters[token];
        if (transferOwnership) {
            tokenInfo.strategy.transferOwnership(newOwner);
        }
        tokenInfo.strategy = newStrategy;
    }

    //STRATEGY-ONLY FUNCTIONS
    //an autocompounding strategy calls this function to account for new tokens that it earns
    function accountAddedTokens(address token, uint256 amount) external {
        TokenInfo storage tokenInfo = tokenParameters[token];
        require(msg.sender == address(tokenInfo.strategy), "only strategy");
        tokenInfo.totalTokens += amount;
    }

    //PRICE UPDATER-ONLY FUNCTIONS
    //update price of a single token
    function updatePrice(address token, uint256 newPrice) external {
        require(msg.sender == priceUpdater, "only priceUpdater");
        //perform global update to rewards
        _globalUpdate();
        //update token rewards prior to price update
        _tokenUpdate(token);
        //perform price update internally, keeping track of weighted TVL
        _tokenPriceUpdate(token, newPrice);
    }

    //update prices for an array of tokens
    function updatePrices(address[] memory tokens, uint256[] memory newPrices) external {
        require(msg.sender == priceUpdater, "only priceUpdater");
        require(tokens.length == newPrices.length, "inputs");
        //perform global update to rewards
        _globalUpdate();
        for (uint256 i = 0; i < tokens.length; i++) {
            //update token rewards prior to price update
            _tokenUpdate(tokens[i]);
            //perform price update internally, keeping track of weighted TVL
            _tokenPriceUpdate(tokens[i], newPrices[i]);
        }
    }

    //INTERNAL FUNCTIONS
    function _deposit(address token, uint256 amount, address to) internal {
        require(approvedTokens[token], "token not approved for deposit");
        _updateTokenRewards(token);
        TokenInfo storage tokenInfo = tokenParameters[token];
        if (amount > 0) {
            UserInfo storage user = userInfo[token][to];
            //find number of new shares from amount
            uint256 newShares;
            if (tokenInfo.totalShares > 0) {
                newShares = (amount * tokenInfo.totalShares) / tokenInfo.totalTokens;
            } else {
                newShares = amount;
            }

            //transfer tokens directly to strategy
            IERC20(token).safeTransferFrom(address(msg.sender), address(tokenInfo.strategy), amount);
            //tell strategy to deposit newly transferred tokens and process update
            tokenInfo.strategy.deposit(msg.sender, to, amount, newShares);

            //track new shares
            tokenInfo.totalShares += newShares;
            user.amount += newShares;
            user.rewardDebt += int256((newShares * tokenInfo.accZBOOFIPerShare) / ACC_BOOFI_PRECISION);

            tokenInfo.totalTokens += amount;
            weightedTotalValueLocked += (tokenInfo.storedPrice * amount * tokenInfo.multiplier);

            //track deposit for profit tracking
            deposits[token][to] += amount;

            //rewarder logic
            IRewarder _rewarder = tokenInfo.rewarder;
            if (address(_rewarder) != address(0)) {
                _rewarder.onZBoofiReward(token, msg.sender, to, 0, user.amount - newShares, user.amount);
            }
            emit Deposit(msg.sender, token, amount, to);
        } 
    }

    function _harvest(address token, address to) internal {
        _updateTokenRewards(token);
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][msg.sender];

        //find all time ZBOOFI rewards for all of user's shares
        uint256 accumulatedZBoofi = (user.amount * tokenInfo.accZBOOFIPerShare) / ACC_BOOFI_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendingZBoofi = _toUInt256(int256(accumulatedZBoofi) - user.rewardDebt);
        //update user reward debt
        user.rewardDebt = int256(accumulatedZBoofi);

        //handle BOOFI rewards
        if (pendingZBoofi != 0) {
            _safeZBOOFITransfer(to, pendingZBoofi);
        }

        //call strategy to update
        tokenInfo.strategy.withdraw(msg.sender, to, 0, 0);
        
        //rewarder logic
        IRewarder _rewarder = tokenInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onZBoofiReward(token, msg.sender, to, pendingZBoofi, user.amount, user.amount);
        }

        emit Harvest(msg.sender, token, pendingZBoofi);
    }

    function _withdraw(address token, uint256 amountShares, address to) internal {
        _updateTokenRewards(token);
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][msg.sender];
        require(user.amount >= amountShares, "withdraw: too much");

        if (amountShares > 0 && tokenInfo.totalShares > 0) {
            //find amount of tokens from shares
            uint256 tokensFromShares = (amountShares * tokenInfo.totalTokens) / tokenInfo.totalShares;
            //subtract out withdraw fee if it applies and there are other depositors of the token to benefit from the fee
            if (tokenInfo.withdrawFeeBP > 0 && tokenInfo.totalShares > amountShares) {
                uint256 withdrawFee = (tokensFromShares * tokenInfo.withdrawFeeBP) / MAX_BIPS;
                tokensFromShares -=  withdrawFee;
            }
            //track withdrawal for profit tracking
            withdrawals[token][to] += tokensFromShares;
            //track removed tokens
            tokenInfo.totalTokens -= tokensFromShares;
            weightedTotalValueLocked -= (tokenInfo.storedPrice * tokensFromShares * tokenInfo.multiplier);
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            tokenInfo.strategy.withdraw(msg.sender, to, tokensFromShares, amountShares);
            //track removed shares
            user.amount -= amountShares;
            tokenInfo.totalShares -= amountShares;
            uint256 rewardDebtOfShares = ((amountShares * tokenInfo.accZBOOFIPerShare) / ACC_BOOFI_PRECISION);
            user.rewardDebt -= int256(rewardDebtOfShares);
            emit Withdraw(msg.sender, token, amountShares, to);
        }

        //rewarder logic
        IRewarder _rewarder = tokenInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onZBoofiReward(token, msg.sender, to, 0, user.amount + amountShares, user.amount);
        }
    }

    function _withdrawAndHarvest(address token, uint256 amountShares, address to) internal {
        _updateTokenRewards(token);
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][msg.sender];
        require(user.amount >= amountShares, "withdraw: too much");

        //find all time ZBOOFI rewards for all of user's shares
        uint256 accumulatedZBoofi = (user.amount * tokenInfo.accZBOOFIPerShare) / ACC_BOOFI_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendingZBoofi = _toUInt256(int256(accumulatedZBoofi) - user.rewardDebt);
        if (amountShares > 0 && tokenInfo.totalShares > 0) {
            //find amount of tokens from shares
            uint256 tokensFromShares = (amountShares * tokenInfo.totalTokens) / tokenInfo.totalShares;
            //subtract out withdraw fee if it applies and there are other depositors of the token to benefit from the fee
            if (tokenInfo.withdrawFeeBP > 0 && tokenInfo.totalShares > amountShares) {
                uint256 withdrawFee = (tokensFromShares * tokenInfo.withdrawFeeBP) / MAX_BIPS;
                tokensFromShares -=  withdrawFee;
            }
            //track withdrawal for profit tracking
            withdrawals[token][to] += tokensFromShares;
            //track removed tokens
            tokenInfo.totalTokens -= tokensFromShares;
            weightedTotalValueLocked -= (tokenInfo.storedPrice * tokensFromShares * tokenInfo.multiplier);
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            tokenInfo.strategy.withdraw(msg.sender, to, tokensFromShares, amountShares);
            //track removed shares
            user.amount -= amountShares;
            tokenInfo.totalShares -= amountShares;
            //update value of 'accumulatedZBoofi' for use in setting rewardDebt, so that the new value accounts for the withdrawn shares
            accumulatedZBoofi = (user.amount * tokenInfo.accZBOOFIPerShare) / ACC_BOOFI_PRECISION;
            emit Withdraw(msg.sender, token, amountShares, to);
        }

        //call strategy to update, if it has not been called already
        if (amountShares == 0) {
            tokenInfo.strategy.withdraw(msg.sender, to, 0, 0);
        }

        //update user reward debt
        user.rewardDebt = int256(accumulatedZBoofi);

        //handle BOOFI rewards
        if (pendingZBoofi != 0) {
            _safeZBOOFITransfer(to, pendingZBoofi);
        }
        
        //rewarder logic
        IRewarder _rewarder = tokenInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onZBoofiReward(token, msg.sender, to, pendingZBoofi, user.amount + amountShares, user.amount);
        }
        emit Harvest(msg.sender, token, pendingZBoofi);
    }

    function _emergencyWithdraw(address token, address to) internal {
        //skip token update
        TokenInfo storage tokenInfo = tokenParameters[token];
        UserInfo storage user = userInfo[token][msg.sender];
        uint256 amountShares = user.amount;
        if (amountShares > 0 && tokenInfo.totalShares > 0) {
            //find amount of tokens from shares
            uint256 tokensFromShares = (amountShares * tokenInfo.totalTokens) / tokenInfo.totalShares;
            //subtract out withdraw fee if it applies and there are other depositors of the token to benefit from the fee
            if (tokenInfo.withdrawFeeBP > 0 && tokenInfo.totalShares > amountShares) {
                uint256 withdrawFee = (tokensFromShares * tokenInfo.withdrawFeeBP) / MAX_BIPS;
                tokensFromShares -=  withdrawFee;
            }
            //track withdrawal for profit tracking
            withdrawals[token][to] += tokensFromShares;
            //track removed tokens
            tokenInfo.totalTokens -= tokensFromShares;
            weightedTotalValueLocked -= (tokenInfo.storedPrice * tokensFromShares * tokenInfo.multiplier);
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            tokenInfo.strategy.withdraw(msg.sender, to, tokensFromShares, amountShares);
            //track removed shares
            user.amount -= amountShares;
            tokenInfo.totalShares -= amountShares;
            //update user reward debt
            user.rewardDebt = 0;
            emit EmergencyWithdraw(msg.sender, token, amountShares, to);
        }

        //rewarder logic
        IRewarder _rewarder = tokenInfo.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onZBoofiReward(token, msg.sender, to, 0, amountShares, 0);
        }     
    }

    // Safe ZBOOFI transfer function, just in case if rounding error causes contract to not have enough ZBOOFIs.
    function _safeZBOOFITransfer(address _to, uint256 _amount) internal {
        uint256 boofiBal = ZBOOFI.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > boofiBal) {
            transferSuccess = ZBOOFI.transfer(_to, boofiBal);
        } else {
            transferSuccess = ZBOOFI.transfer(_to, _amount);
        }
        require(transferSuccess, "_safeZBOOFITransfer");
    }

    // Safe BOOFI transfer function, just in case if rounding error causes contract to not have enough BOOFIs.
    function _safeBOOFITransfer(address _to, uint256 _amount) internal {
        uint256 boofiBal = BOOFI.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > boofiBal) {
            transferSuccess = BOOFI.transfer(_to, boofiBal);
        } else {
            transferSuccess = BOOFI.transfer(_to, _amount);
        }
        require(transferSuccess, "_safeBOOFITransfer");
    }

    function _globalUpdate() internal {
        //only need to update a max of once per second. also skip all logic if no value locked
        if (block.timestamp > lastAvgUpdateTimestamp && weightedTotalValueLocked > 0) {
            uint256 newBOOFI  = (block.timestamp - lastAvgUpdateTimestamp) * boofiEmissionPerSecond;
            BOOFI.mint(address(this), newBOOFI);
            uint256 endowmentAmount = (newBOOFI * totalEndowmentBips) / MAX_BIPS;
            endowmentBal += endowmentAmount;
            uint256 finalAmount = newBOOFI - endowmentAmount;
            uint256 zboofiBefore = ZBOOFI.balanceOf(address(this));
            ZBOOFI.enter(finalAmount);
            uint256 newZBOOFI = ZBOOFI.balanceOf(address(this)) - zboofiBefore;
            //update global average for all pools
            //NOTE: large scaling here, as divisor is enormous
            cumulativeAvgZboofiPerWeightedValueLocked += (newZBOOFI * BOOFI_PRECISION_SQUARED) / weightedTotalValueLocked;
            //update stored value for last time of global update
            lastAvgUpdateTimestamp = block.timestamp;
        }
    }

    function _tokenUpdate(address token) internal {
        TokenInfo storage tokenInfo = tokenParameters[token];
        //only need to update a max of once per second
        if (block.timestamp > tokenInfo.lastRewardTime && tokenInfo.totalShares > 0) {
            uint256 cumulativeRewardDiff = (cumulativeAvgZboofiPerWeightedValueLocked - tokenInfo.lastCumulativeReward);
            //NOTE: inverse scaling to that performed in calculating cumulativeAvgZboofiPerWeightedValueLocked
            uint256 zboofiReward = (cumulativeRewardDiff * tokenWeightedValueLocked(token)) / BOOFI_PRECISION_SQUARED;
            if (zboofiReward > 0) {
                tokenInfo.accZBOOFIPerShare += (zboofiReward * ACC_BOOFI_PRECISION) / tokenInfo.totalShares;
            }
            //update stored rewards for token
            tokenInfo.lastRewardTime = block.timestamp;
            tokenInfo.lastCumulativeReward = cumulativeAvgZboofiPerWeightedValueLocked;
        }
        //trigger automatic price update only if mechanic is enabled and caller is an EOA
        if (autoUpdatePrices && msg.sender == tx.origin) {
            uint256 newPrice = IOracle(oracle).getPrice(token);
            _tokenPriceUpdate(token, newPrice);
        }
    }

    function _tokenPriceUpdate(address token, uint256 newPrice) internal {
        TokenInfo storage tokenInfo = tokenParameters[token];
        //subtract out old values
        weightedTotalValueLocked -= (tokenInfo.storedPrice * tokenInfo.totalTokens * tokenInfo.multiplier);
        //update price and add in new values
        tokenInfo.storedPrice = newPrice;
        weightedTotalValueLocked += (newPrice * tokenInfo.totalTokens * tokenInfo.multiplier);
    }

    function _updateTokenRewards(address token) internal {
        TokenInfo storage tokenInfo = tokenParameters[token];
        //short circuit update if there are no deposits of the token or it has a zero multiplier
        uint256 tokenShares = tokenInfo.totalShares;
        if (tokenShares == 0 || tokenInfo.multiplier == 0) {
            tokenInfo.lastRewardTime = block.timestamp;
            tokenInfo.lastCumulativeReward = cumulativeAvgZboofiPerWeightedValueLocked;
            return;
        }
        // perform global update
        _globalUpdate();
        //perform update just for token
        _tokenUpdate(token); 
    }

    function _modifyApprovedToken(address token, bool status) internal {
        if (!approvedTokens[token] && status) {
            approvedTokens[token] = true;
            tokenListPosition[token] = tokenListLength();
            approvedTokenList.push(token);
        } else if (approvedTokens[token] && !status) {
            approvedTokens[token] = false;
            address lastTokenInList = approvedTokenList[tokenListLength() - 1];
            approvedTokenList[tokenListPosition[token]] = lastTokenInList;
            tokenListPosition[lastTokenInList] = tokenListPosition[token];
            approvedTokenList.pop();
        }
    }

    function _toUInt256(int256 a) internal pure returns (uint256) {
        if (a < 0) {
            return 0;
        } else {
            return uint256(a);
        }        
    }
}
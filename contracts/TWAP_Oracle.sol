// SPDX-License-Identifier: MIT
//based on: https://github.com/Uniswap/uniswap-v2-periphery/tree/master/contracts/examples

pragma solidity =0.6.6;
pragma experimental ABIEncoderV2;

import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";

//copy of Ownable contract to avoid conflicts for not satisfying compiler requirements in OpenZeppelin's latest version
contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() public {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
    function owner() public view virtual returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract TWAP_Oracle is Ownable {
    using FixedPoint for *;

    struct Observation {
        uint256 timestamp;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    uint256 public constant PERIOD = 24 hours;
    //pangolin factory
    address public constant DEFAULT_FACTORY = 0xefa94DE7a4656D787667C749f7E1223D71E9FD88;

    //stored price/trading observations
    mapping(address => Observation) public observations;
    //used for tokens that need a factory other than the default
    mapping(address => mapping(address => address)) public factories;
    //used for mapping factories to their pair init code hashes, used for calculating token pairs
    mapping(address => bytes) public factoryInitCodes;

    constructor() public {
        //Pangolin
        setFactoryInitCode(0xefa94DE7a4656D787667C749f7E1223D71E9FD88, 
            hex"40231f6b438bce0797c9ada29b718a87ea0a5cea3fe9a771abdd76bd41a3e545");
        //TraderJoe
        setFactoryInitCode(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10, 
            hex'0bbca9af0511ad1a1da383135cf3a8d2ac620e549ef9f6ae3a4c33c2fed0af91');
        //Lydia
        setFactoryInitCode(0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27, 
            hex'47cc4f3a5e7a237c464e09c6758ac645084f198b8f64eedc923317ac4481a10c');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                factoryInitCodes[factory] // init code hash
            ))));
    }

    // note this will always return 0 before update has been called successfully for the first time for the pair.
    function consult(address tokenA, address tokenB, address tokenIn, uint256 amountIn) public view returns (uint256 amountOut) {
        address factory = _getFactory(tokenA, tokenB);
        address pair = pairFor(factory, tokenA, tokenB);
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (tokenIn == token0) {
            amountOut = observations[pair].price0Average.mul(amountIn).decode144();
        } else {
            require(tokenIn == token1, 'TWAP_Oracle: invalid tokenIn');
            amountOut = observations[pair].price1Average.mul(amountIn).decode144();
        }
    }

    function consultWithUpdate(address tokenA, address tokenB, address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        update(tokenA, tokenB);
        return consult(tokenA, tokenB, tokenIn, amountIn);
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(address tokenA, address tokenB) public {
        address factory = _getFactory(tokenA, tokenB);
        address pair = pairFor(factory, tokenA, tokenB);
        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint256 timeElapsed = block.timestamp - observations[pair].timestamp;
        if (timeElapsed > PERIOD) {
            (uint256 price0Cumulative, uint256 price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
            // leave price as zero if this is the first observation
            if (timeElapsed < block.timestamp) {
                // overflow is desired, casting never truncates
                // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
                observations[pair].price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - observations[pair].price0CumulativeLast) / timeElapsed));
                observations[pair].price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - observations[pair].price1CumulativeLast) / timeElapsed));
            }
            observations[pair].timestamp = block.timestamp;
            observations[pair].price0CumulativeLast = price0Cumulative;
            observations[pair].price1CumulativeLast = price1Cumulative;
        }
    }

    function setFactoryInitCode(address factory, bytes memory initCode) public onlyOwner {
        factoryInitCodes[factory] = initCode;
    }

    function setFactory(address tokenA, address tokenB, address factory) public onlyOwner {
        factories[tokenA][tokenB] = factory;
        factories[tokenB][tokenA] = factory;
        //update observation for pair while leaving price the same as before, in case we have switched back to this factory from another factory
        address pair = pairFor(factory, tokenA, tokenB);
        (uint256 price0Cumulative, uint256 price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
        observations[pair].timestamp = block.timestamp;
        observations[pair].price0CumulativeLast = price0Cumulative;
        observations[pair].price1CumulativeLast = price1Cumulative;
    }

    function massSetFactory(address[] calldata tokenAs, address[] calldata tokenBs, address factory) external onlyOwner {
        require(tokenAs.length == tokenBs.length, "input length mismatch");
        for (uint256 i = 0; i < tokenAs.length; i++) {
            setFactory(tokenAs[i], tokenBs[i], factory);
        }
    }

    function _getFactory(address tokenA, address tokenB) internal view returns(address) {
        if(factories[tokenA][tokenB] == address(0)) {
            return DEFAULT_FACTORY;
        } else {
            return factories[tokenA][tokenB];
        }
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }
}
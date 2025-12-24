// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    function liquidity() external view returns (uint128);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

contract CheckPool is Script {
    address constant POOL = 0xd0b53D9277642d899DF5C87A3966A349A798F224; // WETH/USDC 0.05%
    address constant QUOTER = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        IUniswapV3Pool pool = IUniswapV3Pool(POOL);
        
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        uint128 liq = pool.liquidity();
        
        console.log("Pool Address:", POOL);
        console.log("SqrtPriceX96:", sqrtPriceX96);
        console.log("Current Tick:", tick);
        console.log("Liquidity   :", liq);
        
        // Check Quote for 1 ETH
        IQuoterV2 quoter = IQuoterV2(QUOTER);
        try quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            amountIn: 1 ether,
            fee: 500,
            sqrtPriceLimitX96: 0
        })) returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate) {
            console.log("Quote 1 ETH -> USDC:", amountOut);
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed (unknown)");
        }
    }
}
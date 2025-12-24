// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV3Pool {
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);
    
    function initialize(uint160 sqrtPriceX96) external;
}

contract LiquidityHelper {
    function addLiquidity(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        address token0,
        address token1
    ) external {
        IUniswapV3Pool(pool).mint(
            address(this),
            tickLower,
            tickUpper,
            amount,
            abi.encode(token0, token1)
        );
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        (address token0, address token1) = abi.decode(data, (address, address));
        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MasterVault} from "./MasterVault.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/**
 * @title ZapRouter
 * @notice 輔助合約，用於在單筆交易中將任何代幣交換為 USDC 並存入 MasterVault。
 */
contract ZapRouter is Ownable {
    using SafeERC20 for IERC20;

    MasterVault public immutable vault;
    IERC20 public immutable USDC;
    ISwapRouter public immutable swapRouter;
    IWETH public immutable WETH;

    constructor(
        address _vault,
        address _usdc,
        address _swapRouter,
        address _weth
    ) Ownable(msg.sender) {
        vault = MasterVault(_vault);
        USDC = IERC20(_usdc);
        swapRouter = ISwapRouter(_swapRouter);
        WETH = IWETH(_weth);

        // 批准 Vault 使用 USDC
        USDC.approve(address(vault), type(uint256).max);
    }

    function _swap(ISwapRouter.ExactInputSingleParams memory params) internal returns (uint256 amountOut) {
        uint256 balanceBefore = USDC.balanceOf(address(this));
        
        // Use low-level call to avoid return value decoding issues if any
        bytes memory callData = abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params);
        (bool success, ) = address(swapRouter).call{value: 0}(callData);
        require(success, "Swap failed");
        
        uint256 balanceAfter = USDC.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }

    /**
     * @notice 將 ERC20 代幣 Zap 為 USDC 並存款。
     * @param tokenIn 輸入代幣的地址。
     * @param amountIn 要交換的輸入代幣數量。
     * @param minUSDC 從交換中接收的最小 USDC。
     * @param mode 遊戲模式 ID。
     * @param data 模式的附加數據。
     * @param receiver 接收票券 NFT 的地址。
     */
    function zapIn(
        address tokenIn,
        uint256 amountIn,
        uint256 minUSDC,
        uint8 mode,
        bytes calldata data,
        address receiver,
        uint24 poolFee
    ) external returns (uint256 tokenId) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        uint256 usdcAmount;
        if (tokenIn == address(USDC)) {
            usdcAmount = amountIn;
        } else {
            IERC20(tokenIn).approve(address(swapRouter), amountIn);
            
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: address(USDC),
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minUSDC,
                sqrtPriceLimitX96: 0
            });
            
            usdcAmount = _swap(params);
        }

        tokenId = vault.deposit(usdcAmount, receiver, mode, data);
    }

    /**
     * @notice 將 ETH Zap 為 USDC 並存款。
     */
    function zapInETH(
        uint256 minUSDC,
        uint8 mode,
        bytes calldata data,
        address receiver,
        uint24 poolFee
    ) external payable returns (uint256 tokenId) {
        require(msg.value > 0, "Zero ETH");
        
        WETH.deposit{value: msg.value}();
        WETH.approve(address(swapRouter), msg.value);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(USDC),
            fee: poolFee,
            recipient: address(this),
            amountIn: msg.value,
            amountOutMinimum: minUSDC,
            sqrtPriceLimitX96: 0
        });

        uint256 usdcAmount = _swap(params);
        tokenId = vault.deposit(usdcAmount, receiver, mode, data);
    }

    // 允許接收 ETH
    receive() external payable {}
}

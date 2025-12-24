// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IAdapter
 * @notice Proof of Luck 策略適配器介面 (Strategy Adapter Interface)。
 * @dev 用於對接外部 DeFi 協議 (如 Aave, Aerodrome)。
 */
interface IAdapter {
    /**
     * @notice 將資產存入底層協議。
     * @param assets 存入的資產數量 (USDC)。
     * @param data 額外數據。
     * @return shares 獲得的份額數量 (如 aToken)。
     */
    function deposit(uint256 assets, bytes calldata data) external returns (uint256 shares);

    /**
     * @notice 從底層協議贖回資產。
     * @param shares 要贖回的份額數量 (或資產數量)。
     * @param principalToBurn 對應的本金負債減少量。
     * @param receiver 接收資產的地址。
     * @param owner 份額擁有者。
     * @return assets 贖回的資產數量。
     */
    function redeem(uint256 shares, uint256 principalToBurn, address receiver, address owner) external returns (uint256 assets);

    /**
     * @notice 獲取當前累積的收益 (Yield)。
     */
    function getTotalYield() external view returns (uint256);

    /**
     * @notice 將收益再投資 (增加本金負債)。
     * @param amount 要再投資的金額。
     */
    function reinvestYield(uint256 amount) external;

    /**
     * @notice 收集協議收入 (如罰金)。
     * @param amount 要收集的金額。
     * @param receiver 接收地址 (通常是 Governance Treasury)。
     */
    function collectRevenue(uint256 amount, address receiver) external;

    /**
     * @notice 收集收益作為費用 (Collect Yield as Fee)。
     * @param amount 要收集的金額。
     * @param receiver 接收地址。
     */
    function collectYield(uint256 amount, address receiver) external;
}

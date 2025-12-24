// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IPOLHook
 * @notice Proof of Luck Hooks 的接口（邏輯層）。
 * @dev Hooks 包含遊戲邏輯（儲蓄、Alpha、戰鬥）。
 */
interface IPOLHook {
    /**
     * @notice 在執行存款之前由 Vault 調用。
     * @param caller 發起存款的地址。
     * @param assets 正在存入的資產 (USDC) 數量。
     * @param shares 要鑄造的份額 (NFT/代幣) 數量。
     * @param data 傳遞給遊戲邏輯的附加數據（例如，坐標）。
     */
    function beforeDeposit(
        address caller,
        uint256 assets,
        uint256 shares,
        bytes calldata data
    ) external;

    /**
     * @notice 在執行存款之後由 Vault 調用。
     * @param caller 發起存款的地址。
     * @param assets 存入的資產 (USDC) 數量。
     * @param shares 鑄造的份額 (NFT/代幣) 數量。
     * @param data 傳遞給遊戲邏輯的附加數據。
     */
    function afterDeposit(
        address caller,
        uint256 assets,
        uint256 shares,
        bytes calldata data
    ) external;

    /**
     * @notice 當請求贖回時由 Vault 調用。
     * @param caller 請求贖回的地址。
     * @param shares 要贖回的份額 (NFT/代幣) 數量。
     * @param data 傳遞給遊戲邏輯的附加數據。
     */
    function onRedeemRequest(
        address caller,
        uint256 shares,
        bytes calldata data
    ) external;

    /**
     * @notice 計算贖回時應返還的資產數量。
     * @param tokenId 正在贖回的票券 ID。
     * @param principal 存入的原始本金金額。
     * @return amount 返還給用戶的資產數量。
     */
    function getRedeemableAmount(
        uint256 tokenId,
        uint256 principal
    ) external view returns (uint256 amount);
}

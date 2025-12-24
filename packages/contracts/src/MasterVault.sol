// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPOLHook} from "./interfaces/IPOLHook.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {ITicketDescriptor} from "./interfaces/ITicketDescriptor.sol";
import {BattleHook} from "./hooks/BattleHook.sol";

/**
 * @title MasterVault
 * @notice Proof of Luck 核心金庫。
 * @dev 實現混合 ERC-7540 (異步) + ERC-721 (票券) 模式。
 *      使用打包的 TicketData 優化存儲。
 */
contract MasterVault is ERC721, ERC2981, ReentrancyGuard, Ownable {
    /// @notice 底層資產 (USDC)。
    IERC20 public immutable ASSET;

    /// @notice 打包的票券數據 (1 個插槽 = 256 位)。
    struct TicketData {
        uint128 assets;      // 128 bits
        uint40 mintTime;     // 40 bits
        uint16 multiplier;   // 16 bits
        uint8 mode;          // 8 bits
        bool isDead;         // 8 bits
        uint16 x;            // 16 bits
        uint16 y;            // 16 bits
        uint24 extra;        // 24 bits (Reserved for future use)
    }

    /// @notice 代幣 ID 到票券數據的映射。
    mapping(uint256 => TicketData) public tickets;

    /// @notice 模式 ID 到 Hook 地址的映射。
    mapping(uint8 => address) public modeHooks;

    /// @notice Hook 地址到適配器地址的映射。
    mapping(address => address) public hookAdapters;

    /// @notice 票券描述符合約。
    ITicketDescriptor public descriptor;

    /// @notice 代幣 ID 計數器。
    uint256 public nextTokenId;

    /// @notice 事件。
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 tokenId, uint8 mode);
    event RedeemClaim(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 tokenId);
    event AdapterSet(address indexed hook, address indexed adapter);
    event ModeRegistered(uint8 indexed mode, address indexed hook);
    event DescriptorSet(address indexed descriptor);

    constructor(address _asset) ERC721("ProofOfLuck Ticket", "POLT") Ownable(msg.sender) {
        require(_asset != address(0), "Invalid asset");
        ASSET = IERC20(_asset);
        nextTokenId = 1;
        _setDefaultRoyalty(msg.sender, 200); // 2% Royalty
    }

    /**
     * @notice 設置票券描述符。
     */
    function setDescriptor(address _descriptor) external onlyOwner {
        require(_descriptor != address(0), "Invalid descriptor");
        descriptor = ITicketDescriptor(_descriptor);
        emit DescriptorSet(_descriptor);
    }

    /**
     * @notice 設置默認版稅。
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @notice 註冊具有特定 Hook 的模式。
     */
    function registerMode(uint8 mode, address hook) external onlyOwner {
        require(hook != address(0), "Invalid hook");
        modeHooks[mode] = hook;
        emit ModeRegistered(mode, hook);
    }

    /**
     * @notice 為特定 Hook 設置適配器。
     */
    function setAdapter(address hook, address adapter) external onlyOwner {
        require(hook != address(0), "Invalid hook");
        require(adapter != address(0), "Invalid adapter");
        hookAdapters[hook] = adapter;
        emit AdapterSet(hook, adapter);
    }

    /**
     * @notice 存入資產並鑄造票券 NFT。
     * @param assets 存入的 USDC 金額。
     * @param receiver 接收 NFT 的地址。
     * @param mode 遊戲模式 ID。
     * @param data 附加數據（必須包含 x, y 坐標）。
     * @return tokenId 鑄造的票券 ID。
     */
    function deposit(
        uint256 assets,
        address receiver,
        uint8 mode,
        bytes calldata data
    ) external nonReentrant returns (uint256 tokenId) {
        require(assets > 0, "Zero assets");
        address hook = modeHooks[mode];
        require(hook != address(0), "Invalid mode");

        // 從數據解碼 x, y (假設 abi.encode(x, y))
        (uint256 x, uint256 y) = abi.decode(data, (uint256, uint256));
        require(x <= type(uint16).max && y <= type(uint16).max, "Coordinates out of bounds");

        tokenId = nextTokenId++;
        
        tickets[tokenId] = TicketData({
            assets: uint128(assets),
            mintTime: uint40(block.timestamp),
            multiplier: 100, // 默認倍數 1.00x
            mode: mode,
            isDead: false,
            x: uint16(x),
            y: uint16(y),
            extra: 0
        });

        _mint(receiver, tokenId);

        emit Deposit(msg.sender, receiver, assets, tokenId, mode);

        _deposit(assets, tokenId, hook, data);
    }

    function _deposit(
        uint256 assets,
        uint256 tokenId,
        address hook,
        bytes calldata data
    ) internal {
        // 如果發送者是 ZapRouter，則不需要 transferFrom，因為資產已經在 ZapRouter 中
        // 但 MasterVault 預期資產從 msg.sender 轉移過來
        // 當 ZapRouter 調用 deposit 時，msg.sender 是 ZapRouter
        // ZapRouter 應該已經批准了 MasterVault
        bool success = ASSET.transferFrom(msg.sender, address(this), assets);
        require(success, "Transfer failed");

        IPOLHook(hook).beforeDeposit(msg.sender, assets, tokenId, data);

        address adapter = hookAdapters[hook];
        if (adapter != address(0)) {
            ASSET.approve(adapter, assets);
            IAdapter(adapter).deposit(assets, data);
        }

        IPOLHook(hook).afterDeposit(msg.sender, assets, tokenId, data);
    }

    /**
     * @notice 請求贖回票券。
     * @dev 為了簡單起見，將請求和索賠與打包結構結合起來。
     */
    function claimRedeem(uint256 tokenId) external nonReentrant returns (uint256 assets) {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        TicketData storage ticket = tickets[tokenId];
        require(!ticket.isDead, "Already redeemed");

        address hook = modeHooks[ticket.mode];
        require(hook != address(0), "Invalid hook");

        // 通知 Hook
        IPOLHook(hook).onRedeemRequest(msg.sender, tokenId, "");

        // 計算可贖回金額
        assets = IPOLHook(hook).getRedeemableAmount(tokenId, ticket.assets);

        address adapter = hookAdapters[hook];
        bool isWinner = false;

        // 檢查是否為贏家
        try BattleHook(hook).isWinner(tokenId) returns (bool isWin) {
            isWinner = isWin;
            if (isWin && adapter != address(0)) {
                try IAdapter(adapter).getTotalYield() returns (uint256 yield) {
                    assets += yield;
                } catch {}
            }
        } catch {}

        uint256 principalToBurn = ticket.assets;

        // 標記為失效並銷毀
        ticket.isDead = true;
        _burn(tokenId);

        emit RedeemClaim(msg.sender, msg.sender, msg.sender, assets, tokenId);

        if (adapter != address(0)) {
            IAdapter(adapter).redeem(assets, principalToBurn, address(this), address(this));

            if (isWinner) {
                try BattleHook(hook).governance() returns (address gov) {
                    if (gov != address(0)) {
                        IAdapter(adapter).collectRevenue(type(uint256).max, gov);
                    }
                } catch {}
            }
        }

        bool success = ASSET.transfer(msg.sender, assets);
        require(success, "Transfer failed");
    }

    /**
     * @notice 將收益分發給特定票券（再投資）。
     */
    function distributeYieldToTicket(uint256 tokenId) external {
        TicketData storage ticket = tickets[tokenId];
        require(!ticket.isDead, "Ticket is dead");
        address hook = modeHooks[ticket.mode];
        require(msg.sender == hook, "Only hook");
        
        address adapter = hookAdapters[hook];
        if (adapter != address(0)) {
            uint256 yield = IAdapter(adapter).getTotalYield();
            if (yield > 0) {
                IAdapter(adapter).reinvestYield(yield);
                ticket.assets += uint128(yield);
            }
        }
    }

    /**
     * @notice ERC721 代幣 URI。
     * @dev 委託給描述符合約。
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        
        require(address(descriptor) != address(0), "Descriptor not set");
        
        TicketData memory ticket = tickets[tokenId];
        return descriptor.tokenURI(
            tokenId,
            ticket.assets,
            ticket.mode,
            ticket.isDead,
            ticket.x,
            ticket.y
        );
    }

    /**
     * @notice 支持 ERC721 和 ERC2981 接口。
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

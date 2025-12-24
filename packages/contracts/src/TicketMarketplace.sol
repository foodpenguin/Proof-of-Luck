// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketMarketplace
 * @notice 用於交易 Proof of Luck 票券的簡單 NFT 市場。
 */
contract TicketMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        address seller;
        uint256 price;
    }

    // 代幣 ID => 上架信息
    mapping(uint256 => Listing) public listings;
    
    IERC721 public immutable nft;
    IERC20 public immutable paymentToken; // USDC

    uint256 public feeBasisPoints = 250; // 2.5%
    address public treasury;

    event ItemListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event ItemCanceled(address indexed seller, uint256 indexed tokenId);
    event ItemBought(address indexed buyer, address indexed seller, uint256 indexed tokenId, uint256 price);
    event FeeUpdated(uint256 newFee);
    event TreasuryUpdated(address newTreasury);

    constructor(address _nft, address _paymentToken, address _treasury) Ownable(msg.sender) {
        nft = IERC721(_nft);
        paymentToken = IERC20(_paymentToken);
        treasury = _treasury;
    }

    function list(uint256 tokenId, uint256 price) external nonReentrant {
        require(price > 0, "Price must be > 0");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), "Not approved");

        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price
        });

        emit ItemListed(msg.sender, tokenId, price);
    }

    function cancelListing(uint256 tokenId) external nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.seller == msg.sender, "Not seller");
        
        delete listings[tokenId];
        emit ItemCanceled(msg.sender, tokenId);
    }

    function buy(uint256 tokenId) external nonReentrant {
        Listing memory listing = listings[tokenId];
        require(listing.price > 0, "Not listed");
        
        delete listings[tokenId];

        uint256 fee = (listing.price * feeBasisPoints) / 10000;
        uint256 sellerAmount = listing.price - fee;

        // 轉移支付
        require(paymentToken.transferFrom(msg.sender, address(this), listing.price), "Transfer failed");
        
        if (fee > 0) {
            paymentToken.transfer(treasury, fee);
        }
        paymentToken.transfer(listing.seller, sellerAmount);

        // 轉移 NFT
        nft.safeTransferFrom(listing.seller, msg.sender, tokenId);

        emit ItemBought(msg.sender, listing.seller, tokenId, listing.price);
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Max fee 10%");
        feeBasisPoints = _fee;
        emit FeeUpdated(_fee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
}

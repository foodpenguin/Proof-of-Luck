// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/TicketMarketplace.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock NFT", "mNFT") {}
    function mint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}

contract TicketMarketplaceTest is Test {
    TicketMarketplace public marketplace;
    MockERC20 public paymentToken;
    MockERC721 public nft;

    address public deployer = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public treasury = address(4);

    function setUp() public {
        vm.startPrank(deployer);
        
        paymentToken = new MockERC20();
        nft = new MockERC721();
        
        marketplace = new TicketMarketplace(address(nft), address(paymentToken), treasury);
        
        vm.stopPrank();

        // Setup Seller
        nft.mint(seller, 1);
        vm.prank(seller);
        nft.setApprovalForAll(address(marketplace), true);

        // Setup Buyer
        paymentToken.mint(buyer, 10000 * 1e18);
        vm.prank(buyer);
        paymentToken.approve(address(marketplace), type(uint256).max);
    }

    function testListing() public {
        vm.prank(seller);
        marketplace.list(1, 100 * 1e18);

        (address listedSeller, uint256 price) = marketplace.listings(1);
        assertEq(listedSeller, seller);
        assertEq(price, 100 * 1e18);
    }

    function testCancelListing() public {
        vm.startPrank(seller);
        marketplace.list(1, 100 * 1e18);
        marketplace.cancelListing(1);
        vm.stopPrank();

        (address listedSeller, uint256 price) = marketplace.listings(1);
        assertEq(listedSeller, address(0));
        assertEq(price, 0);
    }

    function testBuy() public {
        uint256 price = 100 * 1e18;
        
        vm.prank(seller);
        marketplace.list(1, price);

        uint256 sellerBalanceBefore = paymentToken.balanceOf(seller);
        uint256 treasuryBalanceBefore = paymentToken.balanceOf(treasury);
        uint256 buyerBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(buyer);
        marketplace.buy(1);

        // Check NFT Ownership
        assertEq(nft.ownerOf(1), buyer);

        // Check Balances
        uint256 fee = (price * 250) / 10000; // 2.5%
        uint256 sellerAmount = price - fee;

        assertEq(paymentToken.balanceOf(seller), sellerBalanceBefore + sellerAmount);
        assertEq(paymentToken.balanceOf(treasury), treasuryBalanceBefore + fee);
        assertEq(paymentToken.balanceOf(buyer), buyerBalanceBefore - price);
        
        // Check Listing Removed
        (address listedSeller, ) = marketplace.listings(1);
        assertEq(listedSeller, address(0));
    }

    function testBuyNotListed() public {
        vm.prank(buyer);
        vm.expectRevert("Not listed");
        marketplace.buy(1);
    }

    function testBuyPriceZero() public {
        // Should fail if we try to buy something that was cancelled or not listed
        vm.prank(seller);
        marketplace.list(1, 100);
        
        vm.prank(seller);
        marketplace.cancelListing(1);

        vm.prank(buyer);
        vm.expectRevert("Not listed");
        marketplace.buy(1);
    }
}

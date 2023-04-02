// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20PresetMinterPauser} from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {Swap} from "../src/Swap.sol";
import "../src/DataTypes.sol";
import {FutureAssetOracle, AssetInfo} from "../src/FutureAssetOracle.sol";
import {IFutureAssetOracle} from "../src/interface/IFutureAssetOracle.sol";
import "../src/Errors.sol";

contract ExchangeCoreTest is Test {
    Swap public swap;
    IFutureAssetOracle public oracle;

    ERC20PresetMinterPauser public usdc;
    ERC20PresetMinterPauser public airdropToken;

    uint256 buyerSecretKey;
    uint256 sellerSecretKey;
    address buyer;
    address seller;

    function setUp() public {
        swap = new Swap();
        oracle = new FutureAssetOracle();

        usdc = new ERC20PresetMinterPauser("USDC", "USDC");
        airdropToken = new ERC20PresetMinterPauser("Airdrop Token", "ARB");

        buyerSecretKey = 100;
        sellerSecretKey = 200;
        buyer = vm.addr(buyerSecretKey);
        seller = vm.addr(sellerSecretKey);
    }

    function testDomainSeparator() public {
        // cast ae ...
        string[] memory inputs1 = new string[](8);
        inputs1[0] = "cast";
        inputs1[1] = "ae";
        inputs1[2] = "f(bytes32, bytes32, bytes32, uint256, address)";
        inputs1[3] = "0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f";
        inputs1[4] = "0xcb5f0880d34b0da9c56cf9f4410d44b3457182f7b57d7db56c5d73f8937d5846";
        inputs1[5] = "0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6";
        inputs1[6] = vm.toString(block.chainid);
        inputs1[7] = vm.toString(address(swap));
        bytes memory result1 = vm.ffi(inputs1);

        // cast k
        string[] memory inputs2 = new string[](3);
        inputs2[0] = "cast";
        inputs2[1] = "k";
        inputs2[2] = vm.toString(result1);
        bytes memory result2 = vm.ffi(inputs2);

        assertEq(swap.DOMAIN_SEPARATOR(), bytes32(result2), "domain separator should be equal");
    }

    function testGetOfferHash() public {
        Offer memory offer = Offer(
            OfferType.PROVIDING_PRICING_ASSET,
            address(0x00),
            0,
            0,
            0,
            0,
            address(0x01),
            100,
            address(0x02),
            100,
            address(0x03),
            100,
            5,
            ""
        );
        // cast ae [sig] [args]
        string[] memory inputs1 = new string[](17);
        inputs1[0] = "cast";
        inputs1[1] = "ae";
        inputs1[2] =
            "f(bytes32,uint8 offerType,address offerer,uint48 startTime,uint48 endTime,uint48 createTime,uint48 overdueTime,address pricingAsset,uint256 pricingAssetAmount,address futureAssetOracle,uint256 futureAssetAmount,address collateralAsset,uint256 collateralAssetAmount,uint256 counter)";
        // offer
        inputs1[3] = vm.toString(OFFER_TYPE_HASH);
        inputs1[4] = vm.toString(uint8(offer.offerType));
        inputs1[5] = vm.toString(offer.offerer);
        inputs1[6] = vm.toString(offer.startTime);
        inputs1[7] = vm.toString(offer.endTime);
        inputs1[8] = vm.toString(offer.createTime);
        inputs1[9] = vm.toString(offer.overdueTime);
        inputs1[10] = vm.toString(offer.pricingAsset);
        inputs1[11] = vm.toString(offer.pricingAssetAmount);
        inputs1[12] = vm.toString(offer.futureAssetOracle);
        inputs1[13] = vm.toString(offer.futureAssetAmount);
        inputs1[14] = vm.toString(offer.collateralAsset);
        inputs1[15] = vm.toString(offer.collateralAssetAmount);
        inputs1[16] = vm.toString(offer.counter);
        bytes memory result1 = vm.ffi(inputs1);

        // cast k
        string[] memory inputs2 = new string[](3);
        inputs2[0] = "cast";
        inputs2[1] = "k";
        inputs2[2] = vm.toString(result1);
        bytes memory result2 = vm.ffi(inputs2);

        // cast k again
        string[] memory inputs3 = new string[](3);
        inputs3[0] = "cast";
        inputs3[1] = "k";
        inputs3[2] = vm.toString(abi.encodePacked("\x19\x01", swap.DOMAIN_SEPARATOR(), bytes32(result2)));
        bytes memory result3 = vm.ffi(inputs3);

        bytes32 offerHash = swap.getOfferHash(offer);
        assertEq(offerHash, bytes32(result3), "offer hash should be equal");
    }

    function _createOffer(Offer memory offer) internal returns (Offer memory) {
        bytes32 hash = swap.getOfferHash(offer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(offer.offerer == buyer ? buyerSecretKey : sellerSecretKey, hash);
        offer.signature = abi.encodePacked(r, s, v);

        usdc.mint(offer.offerer, offer.collateralAssetAmount);
        vm.prank(offer.offerer);
        usdc.approve(address(swap), offer.collateralAssetAmount);

        return offer;
    }

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_InitSwapAgreementFromSeller() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectEmit();
        emit Approval(buyer, address(swap), 0);
        vm.expectEmit();
        emit Transfer(buyer, address(swap), offer.collateralAssetAmount);
        vm.expectEmit();
        emit Approval(seller, address(swap), 0);
        vm.expectEmit();
        emit Transfer(seller, address(swap), offer.collateralAssetAmount);
        swap.initSwapAgreement(offer);
        vm.stopPrank();

        vm.expectRevert();
        swap.checkOfferValidity(offer);

        assertEq(
            usdc.balanceOf(address(swap)), offer.collateralAssetAmount * 2, "swap should have 600usdc as collateral"
        );
        assertEq(usdc.balanceOf(buyer), 0, "buyer should spend 300usdc for collateral");
        assertEq(usdc.balanceOf(seller), 0, "seller should spend 300usdc for collateral");
    }

    function test_InitSwapAgreementFromBuyer() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_FUTURE_ASSET,
                offerer: seller,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        usdc.mint(buyer, offer.collateralAssetAmount);
        vm.startPrank(buyer);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        swap.initSwapAgreement(offer);
        vm.stopPrank();

        assertEq(
            usdc.balanceOf(address(swap)), offer.collateralAssetAmount * 2, "swap should have 600usdc as collateral"
        );
        assertEq(usdc.balanceOf(buyer), 0, "buyer should spend 300usdc for collateral");
        assertEq(usdc.balanceOf(seller), 0, "seller should spend 300usdc for collateral");
    }

    function test_OfferNotStart() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp + 10),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(OfferNotStart.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    function test_OfferExpired() public {
        skip(3000);
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp - 30),
                endTime: uint48(block.timestamp - 10),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(OfferExpired.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    function test_AtLeastOneHourBeforeOverdue() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 10),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(AtLeastOneHourBeforeOverdue.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    function test_CounterNotMatch() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 10),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 400 ether,
                counter: 1,
                signature: bytes("")
            })
        );

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(CounterNotMatch.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    function test_OfferNoLongerValid() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 10),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );
        vm.prank(buyer);
        swap.cancelOffer(offer);

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(OfferNoLongerValid.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    function test_InvalidSignature() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 10),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );
        // manipulation
        offer.futureAssetAmount = 99999;

        usdc.mint(seller, offer.collateralAssetAmount);
        vm.startPrank(seller);
        usdc.approve(address(swap), offer.collateralAssetAmount);
        vm.expectRevert(InvalidSignature.selector);
        swap.initSwapAgreement(offer);
        vm.stopPrank();
    }

    event OfferStateChanged(bytes32, OfferState);

    function test_CancelOffer() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        vm.expectEmit();
        emit OfferStateChanged(swap.getOfferHash(offer), OfferState.CANCELED);
        vm.prank(buyer);
        swap.cancelOffer(offer);

        vm.expectRevert();
        swap.checkOfferValidity(offer);
    }

    function test_CancelOfferFromNotOfferOwner() public {
        Offer memory offer = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        vm.prank(seller);
        vm.expectRevert(NotOfferOwner.selector);
        swap.cancelOffer(offer);
    }

    event AllOffersCancelled(address);

    function test_CancelAllOffers() public {
        Offer memory offer1 = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp),
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        Offer memory offer2 = _createOffer(
            Offer({
                offerType: OfferType.PROVIDING_PRICING_ASSET,
                offerer: buyer,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 3700),
                createTime: uint48(block.timestamp) + 1,
                overdueTime: uint48(block.timestamp + 3700),
                pricingAsset: address(usdc),
                pricingAssetAmount: 1000 ether,
                futureAssetOracle: address(oracle),
                futureAssetAmount: 2000,
                collateralAsset: address(usdc),
                collateralAssetAmount: 300 ether,
                counter: 0,
                signature: bytes("")
            })
        );

        assertTrue(swap.checkOfferValidity(offer1));
        assertTrue(swap.checkOfferValidity(offer2));

        vm.expectEmit();
        emit AllOffersCancelled(buyer);
        vm.prank(buyer);
        swap.cancelAllOffers();

        vm.expectRevert();
        swap.checkOfferValidity(offer1);

        vm.expectRevert();
        swap.checkOfferValidity(offer2);
    }

    function test_FulfillPricingAsset() public {
        // TOOD
    }

    function test_FulfillFutureAsset() public {
        // TOOD
    }

    // // 5. oracle set airdrop token info
    // AssetInfo memory airdropTokenInfo = AssetInfo({assetAddress: address(airdropToken), decimals: 18});
    // oracle.setAssetInfo(airdropTokenInfo);
    // assertEq(
    //     oracle.getAssetInfo().assetAddress, airdropTokenInfo.assetAddress, "airdrop token address should be set"
    // );
    // assertEq(oracle.getAssetInfo().decimals, airdropTokenInfo.decimals, "airdrop token decimals should be set");

    // // 6. any party submit token
    // airdropToken.mint(seller, 5000 ether);
    // vm.startPrank(seller);
    // airdropToken.approve(address(swap), type(uint256).max);
    // swap.submitFutureAsset(agreementId);
    // vm.stopPrank();
    // assertEq(airdropToken.balanceOf(address(swap)), 2000 ether, "swap should have 2000 airdrop token");
    // assertEq(airdropToken.balanceOf(address(seller)), 3000 ether, "seller should have 3000 airdrop token");

    // // 7. finish agreement
    // vm.prank(buyer);
    // swap.submitPricingAsset(agreementId);
    // assertEq(airdropToken.balanceOf(address(swap)), 0 ether, "swap should have 0 airdrop token");
    // assertEq(usdc.balanceOf(address(swap)), 0 ether, "swap should have 0 usdc");

    // assertEq(airdropToken.balanceOf(address(buyer)), 2000 ether, "buyer should have 2000 airdrop token");
    // assertEq(usdc.balanceOf(address(buyer)), 4000 ether, "buyer should have 4000 usdc");

    // assertEq(airdropToken.balanceOf(address(seller)), 3000 ether, "seller should have 3000 airdrop token");
    // assertEq(usdc.balanceOf(address(seller)), 6000 ether, "seller should have 6000 usdc");
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20PresetMinterPauser} from "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ExchangeCore} from "../src/ExchangeCore.sol";
import {OfferType, Offer} from "../src/DataTypes.sol";
import {FutureAssetOracle, AssetInfo} from "../src/FutureAssetOracle.sol";
import {IFutureAssetOracle} from "../src/interface/IFutureAssetOracle.sol";
import {Vault} from "../src/Vault.sol";

contract ExchangeCoreTest is Test {
    ExchangeCore public exchangeCore;
    Vault public vault;
    IFutureAssetOracle public oracle;

    ERC20PresetMinterPauser public usdc;
    ERC20PresetMinterPauser public airdropToken;

    function setUp() public {
        exchangeCore = new ExchangeCore();
        vault = Vault(exchangeCore.getVault());
        oracle = new FutureAssetOracle();

        usdc = new ERC20PresetMinterPauser("USDC", "USDC");
        airdropToken = new ERC20PresetMinterPauser("Airdrop Token", "ARB");
    }

    function testDomainSeparator() public {
        // cast ae ...
        string[] memory inputs1 = new string[](8);
        inputs1[0] = "cast";
        inputs1[1] = "ae";
        inputs1[2] = "f(bytes32, bytes32, bytes32, uint256, address)";
        inputs1[3] = "0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f";
        inputs1[4] = "0x3064b798329861315aab0632a1fd5bef7de21f7d5737f1c472a7255026ff3a19";
        inputs1[5] = "0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6";
        inputs1[6] = vm.toString(block.chainid);
        inputs1[7] = vm.toString(address(exchangeCore));
        bytes memory result1 = vm.ffi(inputs1);

        // cast k
        string[] memory inputs2 = new string[](3);
        inputs2[0] = "cast";
        inputs2[1] = "k";
        inputs2[2] = vm.toString(result1);
        bytes memory result2 = vm.ffi(inputs2);

        assertEq(exchangeCore.DOMAIN_SEPARATOR(), bytes32(result2), "domain separator should be equal");
    }

    function testGetOfferHash() public {
        // cast ae ...
        string[] memory inputs1 = new string[](14);
        inputs1[0] = "cast";
        inputs1[1] = "ae";
        inputs1[2] = "f(bytes32, uint8, address, uint16, uint48, uint48, address, uint256, uint256, address, uint256)";
        inputs1[3] = "0xe094571c770141efb143124837534c02daf275588377a58148a69d0869273b89";
        inputs1[4] = "0";
        inputs1[5] = vm.toString(address(0x1));
        inputs1[6] = "100";
        inputs1[7] = "100";
        inputs1[8] = "100";
        inputs1[9] = vm.toString(address(0x2));
        inputs1[10] = "100";
        inputs1[11] = "100";
        inputs1[12] = vm.toString(address(0x3));
        inputs1[13] = "100";
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
        inputs3[2] = vm.toString(abi.encodePacked("\x19\x01", exchangeCore.DOMAIN_SEPARATOR(), bytes32(result2)));
        bytes memory result3 = vm.ffi(inputs3);

        bytes32 offerHash = exchangeCore.getOfferHash(
            Offer(
                OfferType.PROVIDING_PRICING_ASSET,
                address(0x1),
                100,
                100,
                100,
                address(0x2),
                100,
                100,
                address(0x3),
                100,
                ""
            )
        );
        assertEq(offerHash, bytes32(result3), "offer hash should be equal");
    }

    function testInitAgreementByFulfillingOffer() public {
        // saying buyer will pay 1000usdc for 2000arb

        // 1. buyer approve & sign offer offchain
        uint256 buyerSk = 100;
        address buyer = vm.addr(buyerSk);
        usdc.mint(buyer, 5000 ether);

        vm.prank(buyer);
        usdc.approve(address(vault), type(uint256).max);
        Offer memory offer = Offer({
            offerType: OfferType.PROVIDING_PRICING_ASSET,
            offerer: buyer,
            // 30%
            collateralRatio: 3000,
            createTime: uint48(block.timestamp),
            overdueTime: uint48(block.timestamp + 3700),
            pricingAsset: address(usdc),
            // in wei
            pricingAssetAmount: 1000 ether,
            // in human sense decimals
            expectingFutureAssetAmount: 2000,
            futureAssetOracle: address(oracle),
            counter: 0,
            signature: bytes("")
        });

        bytes32 hash = exchangeCore.getOfferHash(offer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSk, hash);
        offer.signature = abi.encodePacked(v, r, s);

        // 2. seller accept offer and create agreement
        uint256 sellerSk = 300;
        address seller = vm.addr(sellerSk);
        usdc.mint(seller, 5000 ether);

        vm.startPrank(seller);
        usdc.approve(address(vault), type(uint256).max);
        vm.recordLogs();
        exchangeCore.initAgreementByFulfillingOffer(offer);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        // 3. 30% of 1000usdc should be locked in vault
        assertEq(usdc.balanceOf(address(vault)), 600 ether, "vault should have 300usdc");
        assertEq(usdc.balanceOf(buyer), 4700 ether, "buyer should have 4000usdc");
        assertEq(usdc.balanceOf(seller), 4700 ether, "buyer should have 4000usdc");

        // 4. event & agreementId
        assertEq(logs[2].topics[0], keccak256("AgreementCreated(uint256)"), "should emit AgreementCreated event");
        uint256 agreementId = abi.decode(logs[2].data, (uint256));

        // 5. oracle set airdrop token info
        AssetInfo memory airdropTokenInfo = AssetInfo({assetAddress: address(airdropToken), decimals: 18});
        oracle.setAssetInfo(airdropTokenInfo);
        assertEq(
            oracle.getAssetInfo().assetAddress, airdropTokenInfo.assetAddress, "airdrop token address should be set"
        );
        assertEq(oracle.getAssetInfo().decimals, airdropTokenInfo.decimals, "airdrop token decimals should be set");

        // 6. any party submit token
        airdropToken.mint(seller, 5000 ether);
        vm.startPrank(seller);
        airdropToken.approve(address(vault), type(uint256).max);
        vault.submitFutureAsset(agreementId);
        vm.stopPrank();
        assertEq(airdropToken.balanceOf(address(vault)), 2000 ether, "vault should have 2000 airdrop token");
        assertEq(airdropToken.balanceOf(address(seller)), 3000 ether, "seller should have 3000 airdrop token");

        // 7. finish agreement
        vm.prank(buyer);
        vault.submitPricingAsset(agreementId);
        assertEq(airdropToken.balanceOf(address(vault)), 0 ether, "vault should have 0 airdrop token");
        assertEq(usdc.balanceOf(address(vault)), 0 ether, "vault should have 0 usdc");

        assertEq(airdropToken.balanceOf(address(buyer)), 2000 ether, "buyer should have 2000 airdrop token");
        assertEq(usdc.balanceOf(address(buyer)), 4000 ether, "buyer should have 4000 usdc");

        assertEq(airdropToken.balanceOf(address(seller)), 3000 ether, "seller should have 3000 airdrop token");
        assertEq(usdc.balanceOf(address(seller)), 6000 ether, "seller should have 6000 usdc");
    }
}

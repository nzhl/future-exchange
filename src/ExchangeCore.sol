// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {Vault} from "./Vault.sol";
import {Agreement, Offer, AgreementState, OfferType, OfferState, OFFER_TYPE_HASH} from "./DataTypes.sol";
import {
    NotOfferOwner,
    CounterNotMatch,
    OfferNoLongerValid,
    AtLeastOneHourBeforeOverdue,
    AgreementAlreadyClosed,
    NotFromVault
} from "./Errors.sol";

contract ExchangeCore is Ownable {
    event AgreementCreated(uint256);
    event OfferCancelled(bytes32);
    event AllOfferCancelled(address);

    uint256 internal idCounter = 0;
    mapping(uint256 => Agreement) public agreementsMap;
    mapping(bytes32 => OfferState) public offerStateMap;
    mapping(address => uint256) public userOfferCounter;

    bytes32 internal DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                // typehash
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                //keccak256("FutureExchange"),
                0x3064b798329861315aab0632a1fd5bef7de21f7d5737f1c472a7255026ff3a19,
                //keccak256(bytes("1")),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
                block.chainid,
                address(this)
            )
        );
    }

    function initAgreementByFulfillingOffer(Offer calldata offer) external {
        // 1. verify
        bytes32 offerHash = getOfferHash(offer);
        _verifyOffer(offer, offerHash);

        if (offer.overdueTime - block.timestamp < 1 hours) {
            revert AtLeastOneHourBeforeOverdue();
        }

        // 2. init vault contract
        uint256 agreementId = idCounter;
        idCounter++;
        Vault vault = new Vault(this, agreementId);

        // 3. agreement init
        if (offer.offerType == OfferType.PROVIDING_PRICING_ASSET) {
            agreementsMap[agreementId] = Agreement({
                id: agreementId,
                state: AgreementState.ACTIVED,
                collateralRatio: offer.collateralRatio,
                overdueTime: offer.overdueTime,
                pricingAsset: offer.pricingAsset,
                pricingAssetAmount: offer.pricingAssetAmount,
                pricingAssetOfferer: offer.offerer,
                futureAssetOracle: offer.futureAssetOracle,
                futureAssetAmount: offer.expectingFutureAssetAmount,
                futureAssetOfferer: _msgSender(),
                vault: address(vault)
            });
        } else {
            agreementsMap[agreementId] = Agreement({
                id: agreementId,
                state: AgreementState.ACTIVED,
                collateralRatio: offer.collateralRatio,
                overdueTime: offer.overdueTime,
                pricingAsset: offer.pricingAsset,
                pricingAssetAmount: offer.pricingAssetAmount,
                pricingAssetOfferer: _msgSender(),
                futureAssetOracle: offer.futureAssetOracle,
                futureAssetAmount: offer.expectingFutureAssetAmount,
                futureAssetOfferer: offer.offerer,
                vault: address(vault)
            });
        }

        // 3. collateral
        vault.completeCollateral();

        offerStateMap[offerHash] = OfferState.USED;

        emit AgreementCreated(agreementId);
    }

    function cancelOffer(Offer calldata offer) external {
        if (offer.offerer != _msgSender()) {
            revert NotOfferOwner();
        }

        bytes32 offerHash = getOfferHash(offer);
        _verifyOffer(offer, offerHash);

        offerStateMap[offerHash] = OfferState.CANCELLED;
        emit OfferCancelled(offerHash);
    }

    function cancelAllOffers() external {
        userOfferCounter[_msgSender()] += 1;

        emit AllOfferCancelled(_msgSender());
    }

    function closeAgreement(uint256 agreementId) external {
        // two cases to close agreement
        //   1. both parties paid
        //   2. overdue
        Agreement memory agreement = agreementsMap[agreementId];

        if (_msgSender() != agreement.vault) {
            revert NotFromVault();
        }

        if (agreement.state == AgreementState.CLOSED) {
            revert AgreementAlreadyClosed();
        }

        // 1. close vault
        // TODO

        // 2. close agreement
        agreementsMap[agreementId].state = AgreementState.CLOSED;
    }

    // https://eips.ethereum.org/EIPS/eip-712#specification
    // bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, hash));
    function getOfferHash(Offer calldata offer) public view returns (bytes32) {
        bytes32 hash = keccak256(
            abi.encode(
                OFFER_TYPE_HASH,
                offer.offerType,
                offer.offerer,
                offer.collateralRatio,
                offer.createTime,
                offer.overdueTime,
                offer.pricingAsset,
                offer.pricingAssetAmount,
                offer.expectingFutureAssetAmount,
                offer.counter
            )
        );

        // typed data hash
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hash));
    }

    function getAgreement(uint256 id) external view returns (Agreement memory) {
        return agreementsMap[id];
    }

    // ------ internal ------------
    function _verifyOffer(Offer calldata offer, bytes32 hash) internal view returns (bool) {
        if (offer.counter != userOfferCounter[offer.offerer]) {
            revert CounterNotMatch();
        }

        if (offerStateMap[hash] != OfferState.VALID) {
            revert OfferNoLongerValid();
        }

        SignatureChecker.isValidSignatureNow(offer.offerer, hash, offer.signature);
        return true;
    }
}

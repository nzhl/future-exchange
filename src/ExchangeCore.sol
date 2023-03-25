// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Vault} from "./Vault.sol";
import {Agreement, Offer, AgreementState, OfferType, OfferState} from "./DataTypes.sol";
import {
  NotOfferOwner,
  CounterNotMatch,
  OfferNoLongerValid,
  AT_LEAST_HALF_AN_HOUR_BEFORE_EFFECCTING_TIME,
  AT_LEAST_HALF_AN_HOUR_BEFORE_OVERDUE
} from './Errors.sol';

contract ExchangeCore is Ownable {
  event AgreementCreated(uint256);

  uint256 constant HALF_AN_HOUR = 1800;
  uint256 internal idCounter = 0;
  mapping (uint256 => Agreement) public agreementsMap;
  mapping (bytes32 => OfferState) public offerStateMap;
  mapping (address => uint256) public userOfferCounter;

  function initAgreementByFulfillingOffer(
    Offer calldata offer
  ) external {
    // 1. verify 
    verifyOffer(offer);

    if (offer.effectingTime - block.timestamp <= HALF_AN_HOUR) {
      revert AT_LEAST_HALF_AN_HOUR_BEFORE_EFFECCTING_TIME();
    }

    if (offer.overdueTime - offer.effectingTime <= HALF_AN_HOUR) {
      revert AT_LEAST_HALF_AN_HOUR_BEFORE_OVERDUE();
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

        futureAsset: address(0),
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

        futureAsset: address(0),
        futureAssetAmount: offer.expectingFutureAssetAmount,
        futureAssetOfferer: offer.offerer,

        vault: address(vault)
      });
    }

    // 3. collateral
    vault.transferCollateral();

    offerStateMap[offer.signature] = OfferState.USED;

    emit AgreementCreated(agreementId);
  }


  function verifyOffer(Offer calldata offer) public view returns (bool) {
    if (offer.counter != userOfferCounter[offer.offerer]) {
      revert CounterNotMatch();
    }

    if (offerStateMap[offer.signature] != OfferState.VALID) {
      revert OfferNoLongerValid();
    }

    // TODO: signature validate

    return true;
  }


  function cancelOffer(Offer calldata offer) external {
    if (offer.offerer != _msgSender()) {
      revert NotOfferOwner();
    }

    verifyOffer(offer);

    offerStateMap[offer.signature] = OfferState.CANCELLED;
  }

  function cancelAllOffers() external {
    userOfferCounter[_msgSender()] += 1;
  }

}

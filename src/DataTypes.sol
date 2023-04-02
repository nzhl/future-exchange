// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

enum OfferType {
    PROVIDING_PRICING_ASSET,
    PROVIDING_FUTURE_ASSET
}

enum OfferState {
    VALID,
    CANCELED,
    USED
}

string constant OFFER_TYPE_STRING =
    "Offer(uint8 offerType,address offerer,uint48 startTime,uint48 endTime,uint48 createTime,uint48 overdueTime,address pricingAsset,uint256 pricingAssetAmount,address futureAssetOracle,uint256 futureAssetAmount,address collateralAsset,uint256 collateralAssetAmount,uint256 counter)";
bytes32 constant OFFER_TYPE_HASH = 0x2a647d6f493905cc02d581604b7e032719faa0bccffd7c95e2c5e47d8d5c2dea;

struct Offer {
    OfferType offerType;
    address offerer;
    // only the time between start and end
    // is valid for others to fulfill the offer
    uint48 startTime;
    uint48 endTime;
    // make similar offers unique.
    uint48 createTime;
    // Once overdue, the penalty will be applied
    uint48 overdueTime;
    address pricingAsset;
    uint256 pricingAssetAmount;
    address futureAssetOracle;
    // in human sense decimals here since we don't know the decimals of future asset for now
    uint256 futureAssetAmount;
    address collateralAsset;
    uint256 collateralAssetAmount;
    uint256 counter;
    bytes signature;
}

enum AgreementState {
    ACTIVED,
    CLOSED
}

struct Agreement {
    uint256 id;
    AgreementState state;
    uint48 overdueTime;
    //
    address pricingAsset;
    uint256 pricingAssetAmount;
    address pricingAssetOfferer;
    //
    address futureAssetOracle;
    uint256 futureAssetAmount;
    address futureAssetOfferer;
    //
    address collateralAsset;
    uint256 collateralAssetAmount;
}

struct AssetInfo {
    address assetAddress;
    uint8 decimals;
}

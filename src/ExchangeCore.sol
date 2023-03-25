// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ExchangeCore is Ownable {
  error ZeroAddr();

  event AgreementInit();

  struct PriceAssetOffering {
    uint16 collateralRatio;
    uint48 effectingTime;
    uint48 overdueTime;

    address pricingAsset;
    uint256 pricingAssetAmount;
    address pricingAssetOfferer;
    uint256 expectingFutureAssetAmount;

    bytes32 signature;
  }

  struct FutureAssetOffering {
    uint16 collateralRatio;
    uint48 effectingTime;
    uint48 overdueTime;

    address futureAsset;
    uint256 futureAssetAmount;
    address futureAssetOfferer;
    uint256 expectingPricingAssetAmount;

    bytes32 signature;
  }


  struct Agreement {
    uint256 id;

    // max 10000 i.e. 100%
    uint16 collateralRatio;
    uint48 overdueTime;

    address pricingAsset;
    uint256 pricingAssetAmount;
    address pricingAssetOfferer;

    address futureAsset;
    uint256 futureAssetAmount;
    address futureAssetOfferer;
  }

  uint256 internal idCounter = 0;
  mapping (uint256 => Agreement) public agreementsMap;



  function initAgreementByFulfillingPricingAssetOffering(
    PriceAssetOffering calldata offering
  ) external {
    // 1. verify 
    verifyOffering(offering);

    // 2. agreement init
    agreementsMap[idCounter] = Agreement({
      id: idCounter,
      collateralRatio: offering.collateralRatio,
      overdueTime: offering.overdueTime,

      pricingAsset:offering.pricingAsset,
      pricingAssetAmount: offering.pricingAssetAmount,
      pricingAssetOfferer: offering.pricingAssetOfferer,

      futureAsset: address(0),
      futureAssetAmount: offering.expectingFutureAssetAmount,
      futureAssetOfferer: _msgSender()
    });
    idCounter++;

    // 3. collateral
  }

  function verifyOffering(PriceAssetOffering calldata offering) public view returns (bool) {
    this;
    return true;
  }


  //  --------------  internal ------------------


}

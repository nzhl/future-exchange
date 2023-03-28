// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ExchangeCore} from "./ExchangeCore.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {Agreement, OfferType} from "./DataTypes.sol";
import {IFutureAssetOracle, AssetInfo} from "./interface/IFutureAssetOracle.sol";
import {FutureAssetNotSet, PricingAssetNotPaid, FutureAssetNotPaid} from "./Errors.sol";

contract Vault is Pausable {
    event OffererPaid(uint256 agreementId, OfferType offerer);

    using SafeERC20 for IERC20;

    ExchangeCore exchange;

    constructor(ExchangeCore _exchange) {
        exchange = _exchange;
    }

    function completeCollateral(uint256 agreementId) external {
        Agreement memory agreement = exchange.getAgreement(agreementId);
        uint256 collateralAmount = (agreement.pricingAssetAmount * agreement.collateralRatio) / 10000;

        IERC20(agreement.pricingAsset).safeTransferFrom(agreement.pricingAssetOfferer, address(this), collateralAmount);
        IERC20(agreement.pricingAsset).safeTransferFrom(agreement.futureAssetOfferer, address(this), collateralAmount);
    }

    function submitFutureAsset(uint256 agreementId) external {
        Agreement memory agreement = exchange.getAgreement(agreementId);
        IFutureAssetOracle futureAssetOracle = IFutureAssetOracle(agreement.futureAssetOracle);
        AssetInfo memory futureAssetInfo = futureAssetOracle.getAssetInfo();
        if (futureAssetInfo.assetAddress == address(0)) {
            revert FutureAssetNotSet();
        }

        // TODO safety check
        IERC20(agreement.pricingAsset).safeTransfer(
            agreement.futureAssetOfferer, (agreement.pricingAssetAmount * agreement.collateralRatio) / 10000
        );

        if (_checkAndPayPricingAsset(agreement)) {
            IERC20(futureAssetInfo.assetAddress).safeTransferFrom(
                _msgSender(),
                agreement.pricingAssetOfferer,
                agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals
            );

            emit OffererPaid(agreementId, OfferType.PROVIDING_FUTURE_ASSET);
            exchange.closeAgreement(agreementId);
        } else {
            IERC20(futureAssetInfo.assetAddress).safeTransferFrom(
                _msgSender(), address(this), agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals
            );
            emit OffererPaid(agreementId, OfferType.PROVIDING_FUTURE_ASSET);
        }
    }

    function submitPricingAsset(uint256 agreementId) external {
        Agreement memory agreement = exchange.getAgreement(agreementId);
        IERC20 pricingAsset = IERC20(agreement.pricingAsset);

        if (_checkAndPayFutureAsset(agreement)) {
            pricingAsset.safeTransferFrom(
                _msgSender(),
                agreement.futureAssetOfferer,
                (agreement.pricingAssetAmount * (10000 - agreement.collateralRatio)) / 10000
            );
            pricingAsset.safeTransfer(
                agreement.futureAssetOfferer, (agreement.pricingAssetAmount * agreement.collateralRatio) / 10000
            );
            emit OffererPaid(agreementId, OfferType.PROVIDING_PRICING_ASSET);
            exchange.closeAgreement(agreementId);
        } else {
            pricingAsset.safeTransferFrom(
                _msgSender(),
                address(this),
                (agreement.pricingAssetAmount * (10000 - agreement.collateralRatio)) / 10000
            );
            emit OffererPaid(agreementId, OfferType.PROVIDING_PRICING_ASSET);
        }
    }

    function _checkAndPayPricingAsset(Agreement memory agreement) internal returns (bool) {
        IERC20 pricingAsset = IERC20(agreement.pricingAsset);
        if (
            pricingAsset.balanceOf(address(this))
                < ((10000 + agreement.collateralRatio) * agreement.pricingAssetAmount) / 10000
        ) {
            return false;
        }

        pricingAsset.safeTransfer(agreement.futureAssetOfferer, agreement.pricingAssetAmount);
        emit OffererPaid(agreement.id, OfferType.PROVIDING_PRICING_ASSET);
        return true;
    }

    function _checkAndPayFutureAsset(Agreement memory agreement) internal returns (bool) {
        IFutureAssetOracle futureAssetOracle = IFutureAssetOracle(agreement.futureAssetOracle);
        AssetInfo memory futureAssetInfo = futureAssetOracle.getAssetInfo();
        if (futureAssetInfo.assetAddress == address(0)) {
            return false;
        }
        if (
            IERC20(futureAssetInfo.assetAddress).balanceOf(address(this))
                < agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals
        ) {
            return false;
        }

        IERC20(futureAssetInfo.assetAddress).safeTransfer(
            agreement.pricingAssetOfferer, agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals
        );
        emit OffererPaid(agreement.id, OfferType.PROVIDING_FUTURE_ASSET);
        return true;
    }
}

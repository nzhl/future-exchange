// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "./DataTypes.sol";
import {IFutureAssetOracle, AssetInfo} from "./interface/IFutureAssetOracle.sol";

import "./Errors.sol";

contract Swap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event OfferStateChanged(bytes32, OfferState);
    event AllOffersCancelled(address);
    event AgreementStateChanged(uint256, AgreementState);
    event OffererPaid(uint256 agreementId, OfferType offerer);

    uint256 internal idCounter = 0;

    mapping(bytes32 => OfferState) private offerStateMap;
    mapping(address => uint256) public userOfferCounter;
    mapping(uint256 => Agreement) public agreementsMap;
    mapping(uint256 => mapping(OfferType => bool)) public offererFulfillmentMap;

    uint16 public overduePenaltyFeeRate = 1000; // 10%
    uint16 public transactionFeeRate = 0; // free for now
    address public cashier;

    bytes32 public DOMAIN_SEPARATOR;

    constructor() {
        cashier = _msgSender();
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                // typehash
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                //keccak256("FutureSwap"),
                0xcb5f0880d34b0da9c56cf9f4410d44b3457182f7b57d7db56c5d73f8937d5846,
                //keccak256(bytes("1")),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
                block.chainid,
                address(this)
            )
        );
    }

    function initSwapAgreement(Offer calldata offer) external {
        // 1. verify
        bytes32 offerHash = getOfferHash(offer);
        _verifyOffer(offer, offerHash);

        // 2. init agreement
        uint256 agreementId = idCounter;
        idCounter++;
        Agreement memory agreement;
        bool isOfferFromPricingAssetSide = offer.offerType == OfferType.PROVIDING_PRICING_ASSET;
        agreement = Agreement({
            id: agreementId,
            state: AgreementState.ACTIVED,
            overdueTime: offer.overdueTime,
            pricingAsset: offer.pricingAsset,
            pricingAssetAmount: offer.pricingAssetAmount,
            pricingAssetOfferer: isOfferFromPricingAssetSide ? offer.offerer : _msgSender(),
            futureAssetOracle: offer.futureAssetOracle,
            futureAssetAmount: offer.futureAssetAmount,
            futureAssetOfferer: isOfferFromPricingAssetSide ? _msgSender() : offer.offerer,
            collateralAsset: offer.collateralAsset,
            collateralAssetAmount: offer.collateralAssetAmount
        });

        // 3. collateral
        _postCollateral(agreement);

        // 4. update state
        offerStateMap[offerHash] = OfferState.USED;
        agreementsMap[agreementId] = agreement;
        emit OfferStateChanged(offerHash, OfferState.USED);
        emit AgreementStateChanged(agreementId, AgreementState.ACTIVED);
    }

    function cancelOffer(Offer calldata offer) external {
        if (offer.offerer != _msgSender()) {
            revert NotOfferOwner();
        }

        bytes32 offerHash = getOfferHash(offer);
        _verifyOffer(offer, offerHash);

        offerStateMap[offerHash] = OfferState.CANCELED;
        emit OfferStateChanged(offerHash, OfferState.CANCELED);
    }

    function cancelAllOffers() external {
        userOfferCounter[_msgSender()] += 1;

        emit AllOffersCancelled(_msgSender());
    }

    function fulfillFutureAsset(uint256 agreementId) external nonReentrant {
        Agreement memory agreement = getAgreement(agreementId);

        // 1. agreement check
        if (block.timestamp > agreement.overdueTime) {
            revert AgreementOverdue();
        }
        if (agreement.state == AgreementState.CLOSED) {
            revert AgreementAlreadyClosed();
        }

        // 2. oracle ready check
        IFutureAssetOracle futureAssetOracle = IFutureAssetOracle(agreement.futureAssetOracle);
        AssetInfo memory futureAssetInfo = futureAssetOracle.getAssetInfo();
        if (futureAssetInfo.assetAddress == address(0)) {
            revert FutureAssetNotSet();
        }

        // 3. transfer
        bool isPricingAssetOffererFulfilled = offererFulfillmentMap[agreement.id][OfferType.PROVIDING_PRICING_ASSET];
        if (isPricingAssetOffererFulfilled) {
            // 3.a swap and finish
            IERC20(futureAssetInfo.assetAddress).safeTransferFrom(
                _msgSender(),
                agreement.pricingAssetOfferer,
                agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals * (10000 - transactionFeeRate) / 10000
            );

            IERC20(agreement.pricingAsset).safeTransfer(
                agreement.futureAssetOfferer, agreement.pricingAssetAmount * (10000 - transactionFeeRate) / 10000
            );

            if (transactionFeeRate > 0) {
                IERC20(futureAssetInfo.assetAddress).safeTransferFrom(
                    _msgSender(),
                    cashier,
                    agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals * transactionFeeRate / 10000
                );

                IERC20(agreement.pricingAsset).safeTransfer(
                    cashier, agreement.pricingAssetAmount * transactionFeeRate / 10000
                );
            }
            emit OffererPaid(agreementId, OfferType.PROVIDING_FUTURE_ASSET);
            _closeAgreement(agreement);
        } else {
            // 3.b transfer to contract
            IERC20(futureAssetInfo.assetAddress).safeTransferFrom(
                _msgSender(), address(this), agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals
            );
            offererFulfillmentMap[agreement.id][OfferType.PROVIDING_FUTURE_ASSET] = true;
            emit OffererPaid(agreementId, OfferType.PROVIDING_FUTURE_ASSET);
        }

        // 3. repay collateral
        IERC20(agreement.collateralAsset).safeTransfer(agreement.futureAssetOfferer, agreement.collateralAssetAmount);
    }

    function fulfillPricingAsset(uint256 agreementId) external nonReentrant {
        Agreement memory agreement = getAgreement(agreementId);

        // 1. agreement check
        if (block.timestamp > agreement.overdueTime) {
            revert AgreementOverdue();
        }

        if (agreement.state == AgreementState.CLOSED) {
            revert AgreementAlreadyClosed();
        }

        // 2. transfer
        IERC20 pricingAsset = IERC20(agreement.pricingAsset);
        bool isFutureAssetOffererFulfilled =
            offererFulfillmentMap[agreement.id][OfferType.PROVIDING_FUTURE_ASSET] = true;
        if (isFutureAssetOffererFulfilled) {
            pricingAsset.safeTransferFrom(
                _msgSender(),
                agreement.futureAssetOfferer,
                agreement.pricingAssetAmount * (10000 - transactionFeeRate) / 10000
            );

            IFutureAssetOracle futureAssetOracle = IFutureAssetOracle(agreement.futureAssetOracle);
            AssetInfo memory futureAssetInfo = futureAssetOracle.getAssetInfo();
            IERC20(futureAssetInfo.assetAddress).safeTransfer(
                agreement.pricingAssetOfferer,
                agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals * (10000 - transactionFeeRate) / 10000
            );

            if (transactionFeeRate > 0) {
                pricingAsset.safeTransferFrom(
                    _msgSender(), cashier, agreement.pricingAssetAmount * transactionFeeRate / 10000
                );

                IERC20(futureAssetInfo.assetAddress).safeTransfer(
                    cashier, agreement.futureAssetAmount * 10 ** futureAssetInfo.decimals * transactionFeeRate / 10000
                );
            }

            emit OffererPaid(agreementId, OfferType.PROVIDING_PRICING_ASSET);
            _closeAgreement(agreement);
        } else {
            pricingAsset.safeTransferFrom(_msgSender(), address(this), agreement.pricingAssetAmount);
            offererFulfillmentMap[agreement.id][OfferType.PROVIDING_PRICING_ASSET] = true;
            emit OffererPaid(agreementId, OfferType.PROVIDING_PRICING_ASSET);
        }

        // 3. repay collateral
        IERC20(agreement.collateralAsset).safeTransfer(agreement.pricingAssetOfferer, agreement.collateralAssetAmount);
    }

    function claimPenalty(uint256 agreementId) external nonReentrant {
        Agreement memory agreement = getAgreement(agreementId);

        if (block.timestamp <= agreement.overdueTime) {
            revert AgreementNotOverdue();
        }

        if (agreement.state == AgreementState.CLOSED) {
            revert AgreementAlreadyClosed();
        }

        bool isFutureAssetOffererFulfilled = offererFulfillmentMap[agreement.id][OfferType.PROVIDING_FUTURE_ASSET];
        bool isPricingAssetOffererFulfilled = offererFulfillmentMap[agreement.id][OfferType.PROVIDING_PRICING_ASSET];

        if (!isFutureAssetOffererFulfilled) {
            IERC20(agreement.collateralAsset).safeTransfer(
                agreement.pricingAssetOfferer, agreement.collateralAssetAmount * (10000 - overduePenaltyFeeRate) / 10000
            );

            IERC20(agreement.collateralAsset).safeTransfer(
                cashier, agreement.collateralAssetAmount * overduePenaltyFeeRate / 10000
            );
        }

        if (!isPricingAssetOffererFulfilled) {
            IERC20(agreement.collateralAsset).safeTransfer(
                agreement.futureAssetOfferer, agreement.collateralAssetAmount * (10000 - overduePenaltyFeeRate) / 10000
            );

            IERC20(agreement.collateralAsset).safeTransfer(
                cashier, agreement.collateralAssetAmount * overduePenaltyFeeRate / 10000
            );
        }

        _closeAgreement(agreement);
    }

    function setOverduePenaltyFeeRate(uint16 _overduePenaltyFeeRate) external onlyOwner {
        overduePenaltyFeeRate = _overduePenaltyFeeRate;
    }

    function setTransactionFeeRate(uint16 _transactionFeeRate) external onlyOwner {
        transactionFeeRate = _transactionFeeRate;
    }

    function setCashier(address _cashier) external onlyOwner {
        cashier = _cashier;
    }

    // ------ view ------------

    // https://eips.ethereum.org/EIPS/eip-712#specification
    // bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, hash));
    function getOfferHash(Offer calldata offer) public view returns (bytes32) {
        bytes32 hash = keccak256(
            abi.encode(
                OFFER_TYPE_HASH,
                offer.offerType,
                offer.offerer,
                offer.startTime,
                offer.endTime,
                offer.createTime,
                offer.overdueTime,
                offer.pricingAsset,
                offer.pricingAssetAmount,
                offer.futureAssetOracle,
                offer.futureAssetAmount,
                offer.collateralAsset,
                offer.collateralAssetAmount,
                offer.counter
            )
        );

        // typed data hash
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hash));
    }

    function getAgreement(uint256 id) public view returns (Agreement memory) {
        return agreementsMap[id];
    }

    function checkOfferValidity(Offer calldata offer) public view returns (bool) {
        bytes32 hash = getOfferHash(offer);
        return _verifyOffer(offer, hash);
    }

    // ------ internal ------------
    function _verifyOffer(Offer calldata offer, bytes32 hash) internal view returns (bool) {
        if (offer.startTime > block.timestamp) {
            revert OfferNotStart();
        }
        if (offer.endTime < block.timestamp) {
            revert OfferExpired();
        }

        if (offer.overdueTime - block.timestamp < 1 hours) {
            revert AtLeastOneHourBeforeOverdue();
        }

        if (offer.counter != userOfferCounter[offer.offerer]) {
            revert CounterNotMatch();
        }

        if (offerStateMap[hash] != OfferState.VALID) {
            revert OfferNoLongerValid();
        }

        if (!SignatureChecker.isValidSignatureNow(offer.offerer, hash, offer.signature)) {
            revert InvalidSignature();
        }
        return true;
    }

    function _postCollateral(Agreement memory agreement) internal {
        IERC20(agreement.collateralAsset).safeTransferFrom(
            agreement.pricingAssetOfferer, address(this), agreement.collateralAssetAmount
        );
        IERC20(agreement.collateralAsset).safeTransferFrom(
            agreement.futureAssetOfferer, address(this), agreement.collateralAssetAmount
        );
    }

    function _closeAgreement(Agreement memory agreement) internal {
        agreementsMap[agreement.id].state = AgreementState.CLOSED;
    }
}

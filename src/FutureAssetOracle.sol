// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IFutureAssetOracle, AssetInfo} from "./interface/IFutureAssetOracle.sol";

contract FutureAssetOracle is Ownable, IFutureAssetOracle {
    AssetInfo internal assetInfo;

    function getAssetInfo() external view returns (AssetInfo memory) {
        return assetInfo;
    }

    function setAssetInfo(AssetInfo calldata _assetInfo) external onlyOwner {
        assetInfo = _assetInfo;
    }
}

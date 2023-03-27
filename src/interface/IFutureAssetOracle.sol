// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

struct AssetInfo {
    address assetAddress;
    uint8 decimals;
}

interface IFutureAssetOracle {
    function getAssetInfo() external view returns (AssetInfo memory);

    function setAssetInfo(AssetInfo calldata) external;
}

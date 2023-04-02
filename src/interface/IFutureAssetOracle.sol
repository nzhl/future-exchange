// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AssetInfo} from "../DataTypes.sol";

interface IFutureAssetOracle {
    function getAssetInfo() external view returns (AssetInfo memory);

    function setAssetInfo(AssetInfo calldata) external;
}

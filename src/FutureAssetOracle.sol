// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IFutureAssetOracle} from "./interface/IFutureAssetOracle.sol";

contract FutureAssetOracle is Ownable, IFutureAssetOracle {
  address internal assetAddr;

  function getAssetAddress() external view returns (address) {
    return assetAddr;
  }

  function setAssetAddress(address _assetAddr) external onlyOwner {
    assetAddr = _assetAddr;
  }
}

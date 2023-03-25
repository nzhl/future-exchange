
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

interface IFutureAssetOracle {
  function getAssetAddress() external view returns (address);
  function setAssetAddress(address) external;
}

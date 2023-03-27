// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/ExchangeCore.sol";

contract ExchangeCoreTest is Test {
    ExchangeCore public exchangeCore;

    function setUp() public {
        exchangeCore = new ExchangeCore();
    }
}

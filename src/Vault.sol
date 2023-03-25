// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ExchangeCore} from './ExchangeCore.sol';

contract Vault {
  ExchangeCore exchange;
  uint256 agreementId;

  constructor(ExchangeCore _exchange, uint _agreementId) {
    exchange = _exchange;
    agreementId = agreementId;
  }


  function transferCollateral() external {

    
  }

}


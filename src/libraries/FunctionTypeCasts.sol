// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { CollateralParameters } from '../interfaces/CollateralStruct.sol';

/**
 * @dev Type-casts to convert functions returning raw (uint) pointers
 *      to functions returning memory pointers of specific types.
 *
 *      Used to get around solc's over-allocation of memory when
 *      dynamic return parameters are re-assigned.
 *
 *      With `viaIR` enabled, calling any of these functions is a noop.
 */
library FunctionTypeCasts {

  /**
   * @dev Function type cast to avoid duplicate declaration/allocation
   *      of manually allocated MarketParameters in collateral constructor.
   */
  function asReturnsCollateralParameters(
    function() internal view returns (uint256) fnIn
  ) internal pure returns (function() internal view returns (CollateralParameters memory) fnOut) {
    assembly {
      fnOut := fnIn
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IsUBI is IERC20 {
  function registerHuman(address _human) external;

  function removeHuman(address _human) external;

  function streamToHuman(address _origin, address _target) external;
}
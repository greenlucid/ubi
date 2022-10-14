// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IUBI is IERC20 {

  struct UbiAccount {
    uint80 balance;
    uint32 accruedSince;
    uint32 streamsReceived;
    bool isHuman;
    bool isStreaming;
    bool hasMigrated;
    uint88 freeSpace;
    address streamTarget;
    uint96 freespace2;
  }

  // used to generate the exact totalSupply
  struct Counter {
    uint80 hardSupply; // whenever a human is added or removed, this updates.
    uint80 humanCount;
    uint32 timestamp; // last moment in which a human entered or left.
    uint64 freespace;
  }

  function registerHuman(address _human) external;

  function removeHuman(address _human) external;

  function streamToHuman(address _target) external;

  function getCounter() external view returns (Counter memory);

  function getUbiAccount(address _owner) external view returns (UbiAccount memory);
}
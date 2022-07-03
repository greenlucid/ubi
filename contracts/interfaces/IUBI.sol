// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IUBI is IERC20 {

  struct UbiAccount {
    uint80 balance;
    uint32 accruedSince;
    uint32 streamsReceived;
    bool isHuman;
    bool isStreaming;
    uint96 freespace;
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

  function removeHuman(address _reporter, address _human) external returns (address);

  function streamToHuman(address _you, address _target) external returns (address);

  function getCounter() external view returns (Counter memory);

  function getUbiAccount(address _owner) external view returns (UbiAccount memory);

  function mint(address _recipient, uint256 _amount) external;
}
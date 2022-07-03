// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./interfaces/IUBI.sol";
import "./interfaces/IsUBI.sol";

interface OldUBI is IERC20 {
  function burnFrom(address _account, uint256 _amount) external;
}

/**
 * Main ideas:
 * for a given time (say 1 month) it allows receiving v1 UBI.
 * it mints the equivalent amount (not 1:1!) of gUBI and burns the old UBI.
 * a function can also be made available to do this migration + register the human automatically.
 */

contract UBIGovernorMigrator {

  IUBI public UBI;
  IsUBI public sUBI;
  OldUBI public oldUBI;
  address governor;
  uint256 timestamp;

  uint256 immutable migrationPeriod;

  /** @dev Constructor. If this becomes a proxy contract, then it will be changed to initialize.
   */
  constructor(IUBI _UBI, IsUBI _sUBI, OldUBI _oldUBI, address _governor, uint256 _migrationPeriod) {
    UBI = _UBI;
    sUBI = _sUBI;
    oldUBI = _oldUBI;
    governor = _governor;
    timestamp = block.timestamp;
    migrationPeriod = _migrationPeriod;
  }

  modifier onlyGovernor {
    require(msg.sender == governor, "Only governor");
    _;
  }

  function changeGovernor(address _governor) external onlyGovernor {
    governor = _governor;
  }

  function changeUbis(IUBI _UBI, IsUBI _sUBI, OldUBI _oldUBI) external onlyGovernor {
    UBI = _UBI;
    sUBI = _sUBI;
    oldUBI = _oldUBI;
  }

  function resetTimestamp() external onlyGovernor {
    timestamp = block.timestamp;
  }

  modifier onlyPeriod {
    require(block.timestamp <= migrationPeriod + timestamp, "Too late");
    _;
  }

  // todo make func to execute arbitrary stuff on behalf of me

  // things i don't like about this: i dont see how to make it trigger gas refunds.
  // only the allowance refund seems like it will happen.
  // the only way to make a refund here is to get the user to sign 2 txs for the same block
  // (to prevent old ubi accrual to rewrite the balance)
  function migrateV1ToV2(address _owner) external onlyPeriod {
    // will transform all allowed v1 UBI (thats owned). can be called by anyone!
    uint256 allowance = oldUBI.allowance(_owner, address(this));
    uint256 balance = oldUBI.balanceOf(_owner);
    uint256 migratedAmount = allowance > balance ? balance : allowance;
    // first, burn the oldUBI allowance.
    oldUBI.burnFrom(_owner, migratedAmount);
    // now, mint the equivalent amount of UBI. the accrual ratio is 100791936645.
    uint256 newUbi = migratedAmount / 100791936645;
    UBI.mint(_owner, newUbi);
  }

}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IsUBI.sol";
import "./interfaces/IUBI.sol";

contract sUBI is IsUBI {
  // this contract has no state, other than the reference to UBI.sol

  /// @dev The UBI implementation (so that the streams are ERC-20s)
  IUBI constant UBI = IUBI(0xdd1ad9a21ce722c151a836373babe42c868ce9a4);

  /// @dev Name of the token.
  string constant public name = "sUBI";

  /// @dev Symbol of the token.
  string constant public symbol = "sUBI";

  /// @dev Number of decimals of the token.
  uint8 constant public decimals = 0;

    // you want sUBI to be ERC-20 and for that you need to emit some events.
  modifier onlyUBI() {
    require(msg.sender == address(UBI), "Only UBI interacts with this");
    _;
  }

  // ERC-721 stuff

  function totalSupply() public view returns (uint256) {
    uint256 allSupply = uint256(UBI.getCounter().humanCount);
    uint256 burnedSupply = uint256(UBI.getUbiAccount(address(0)).streamsReceived); // this way we dont need "burn" methods.
    return (allSupply - burnedSupply);
  }

  function balanceOf(address _owner) public view returns (uint256) {
    IUBI.UbiAccount memory account = UBI.getUbiAccount(_owner);
    uint256 sUBIs = uint256(account.streamsReceived);
    if (account.isHuman && !account.isStreaming) {
      sUBIs++;
    }
    return sUBIs;
  }

  function registerHuman(address _human) onlyUBI external {
    emit Transfer(address(0), _human, 1); // symbolizes a "mint"
  }

  function removeHuman(address _human) onlyUBI external {
    emit Transfer(_human, address(0), 1); // actually, it was destroyed.
  }

  function streamToHuman(address _origin, address _target) onlyUBI external {
    emit Transfer(previousStream, _target, 1);
  }

  function tokenURI(uint256 _tokenId) public pure returns (string memory) {
    return ("");
  }

  // Disabled some ERC-20 functions below

  function allowance(address _owner, address _spender) public pure returns (uint256) {
    return 0;
  }

  function transfer(address _to, uint256 _value) public pure returns (bool success) {
    // doesn't do anything.
    return false;
  }

  function transferFrom(address _from, address _to, uint256 _value) public pure returns (bool success) {
    // doesn't do anything.
    return false;
  }

  function approve(address spender, uint256 amount) public pure returns (bool success) {
    // doesn't do anything
    return false;

  function supportsInterface(bytes4 _interface) public pure returns (bool) {
    return 0x80ac58cd == _interface;
  }

}
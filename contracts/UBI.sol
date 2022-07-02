// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./interfaces/IUBI.sol";
import "./interfaces/IsUBI.sol";

/**
 * @title ProofOfHumanity Interface
 * @dev See https://github.com/Proof-Of-Humanity/Proof-Of-Humanity.
 */
interface IProofOfHumanity {
  function isRegistered(address _submissionID)
    external
    view
    returns (
      bool registered
    );
}

contract UBI is IUBI {
  /* Storage */

  /// @dev most info is contained in here.
  mapping (address => UbiAccount) internal ubiAccounts;

  /// @dev for ERC-20 allowances
  mapping (address => mapping (address => uint256)) public allowance;

  // just to keep track of the totalSupply.
  Counter internal counter;

  /// @dev Name of the token.
  string constant public name = "gUBI";

  /// @dev Symbol of the token.
  string constant public symbol = "gUBI";

  /// @dev Number of decimals of the token.
  uint8 constant public decimals = 7;

  /// @dev How many tokens per second will be minted for every valid human.
  uint256 constant public accruedPerSecond = 2778;

  /// @dev The contract's governor.
  address public governor;

  /// @dev The Proof Of Humanity registry to reference.
  IProofOfHumanity public proofOfHumanity;

  /// @dev The sUBI implementation (so that the streams are ERC-20s)
  IsUBI public sUBI;

  /** @dev Constructor. If this becomes a proxy contract, then it will be changed to initialize.
   *  @param _proofOfHumanity The Proof Of Humanity registry to reference.
   */
  constructor(IProofOfHumanity _proofOfHumanity) {
    proofOfHumanity = _proofOfHumanity;
    governor = msg.sender;
    counter.timestamp = uint32(block.timestamp);
  }

  // ERC-20 stuff

  function totalSupply() public view returns (uint256) {
    Counter memory memCounter = counter;
    uint256 allSupply = uint256(memCounter.hardSupply +
      (memCounter.humanCount * accruedPerSecond * (block.timestamp - uint256(memCounter.timestamp)))
    );
    uint256 burnedSupply = balanceOf(address(0)); // this way we dont need "burn" methods.
    return (allSupply - burnedSupply);
  }

  function balanceOf(address _owner) public view returns (uint256) {
    UbiAccount memory ubiAccount = ubiAccounts[_owner];
    uint256 streams = ubiAccount.streamsReceived;
    if (ubiAccount.isHuman && !ubiAccount.isStreaming) {
      streams++;
    }
    return uint256(ubiAccount.balance + (streams * accruedPerSecond));
  }

  function transfer(address _to, uint256 _value) public returns (bool success) {
    uint256 balance = balanceOf(msg.sender);
    require(balance >= _value, "Not enough balance");
    _transfer(msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
    uint256 balance = balanceOf(_from);
    require(balance >= _value, "Not enough balance");
    require(allowance[_from][msg.sender] >= _value, "Not enough allowance");

    // update allowance first
    allowance[_from][msg.sender] -= _value;

    _transfer(msg.sender, _to, _value);
    return true;
  }

  function approve(address _spender, uint256 _value) public returns (bool success) {
    allowance[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  function _transfer(address _from, address _to, uint256 _value) internal {
    // update your balances
    UbiAccount storage ownerAccount = ubiAccounts[msg.sender];
    uint256 balance = balanceOf(_from);
    ownerAccount.balance = uint80(balance - _value);
    ownerAccount.accruedSince = uint32(block.timestamp);
    // update receiver balances
    uint256 receiverBalance = balanceOf(_to);
    UbiAccount storage toAccount = ubiAccounts[_to];
    toAccount.balance = uint80(receiverBalance + _value);
    toAccount.accruedSince = uint32(block.timestamp);

    emit Transfer(msg.sender, _to, _value);
  }

  // this function was not used in the erc-20 funcs to save gas.
  function _updateBalance(address _owner) internal returns (uint256) {
    UbiAccount storage ubiAccount = ubiAccounts[_owner];
    uint256 balance = balanceOf(_owner);
    ubiAccount.accruedSince = uint32(block.timestamp);
    ubiAccount.balance = uint80(balance);
    return (balance);
  }

  // UBI - human stuff

  // you want sUBI to be ERC-20 and for that you need to emit some events.
  modifier onlySUBI() {
    require(msg.sender == address(sUBI), "Only sUBI interacts with this");
    _;
  }

  function _updateCounter() internal {
    counter.hardSupply = uint80(totalSupply());
    counter.timestamp = uint32(block.timestamp);
  }

  function registerHuman(address _human) onlySUBI external {
    UbiAccount storage ubiAccount = ubiAccounts[_human];
    require(!ubiAccount.isHuman, "Already a human");
    require(proofOfHumanity.isRegistered(_human), "This human is not registered in PoH");
    _updateBalance(_human);
    ubiAccount.isHuman = true;
    // the requires above enforce a human increment.
    _updateCounter();
    counter.humanCount++;
    // this transfer should let explorers know the human may hold the token.
    emit Transfer(address(0), _human, 0);
  }

  function removeHuman(address _reporter, address _human) onlySUBI external returns (address) {
    UbiAccount storage badHuman = ubiAccounts[_human];
    require(badHuman.isHuman, "Already not a human");
    require(!proofOfHumanity.isRegistered(_human), "This human is registered in PoH");
    // here the complications begin. we want to award the reporter the leftover UBI
    address previousStream;
    uint256 reportReward;
    if (badHuman.isStreaming) {
      // if they're streaming, the reporter gets the ubi from the streamed.
      previousStream = badHuman.streamTarget;
      UbiAccount storage streamee = ubiAccounts[badHuman.streamTarget];
      streamee.streamsReceived--;
      reportReward = accruedPerSecond * (block.timestamp - streamee.accruedSince);
      _updateBalance(badHuman.streamTarget);
    } else {
      previousStream = _human;
      reportReward = accruedPerSecond * (block.timestamp - badHuman.accruedSince);
    }

    badHuman.streamTarget = address(0); // get a gas refund maybe
    badHuman.isStreaming = false;
    badHuman.isHuman = false;
    _updateBalance(_human); // to update the timestamp

    // award this reward to the reporter
    ubiAccounts[_reporter].balance += uint80(reportReward);

    // the requires above enforce a human decrement.
    _updateCounter();
    counter.humanCount--;

    emit Transfer(previousStream, _reporter, reportReward);
    return (previousStream);
  }

  function streamToHuman(address _you, address _target) onlySUBI external returns (address) {
    UbiAccount storage you = ubiAccounts[_you];

    address previousStream;

    // first, check if you were streaming to someone. if so, stop it.
    if (you.isStreaming) {
      previousStream = you.streamTarget;
      _updateBalance(you.streamTarget);
      ubiAccounts[you.streamTarget].streamsReceived--;
    } else {
      previousStream = _you;
    }

    // now, start the stream.
    _updateBalance(_you);
    if (_target == _you) {
      // target yourself to stop the stream.
      // we don't refund the "streamTarget" to 0 on purpose. gas will be saved on rewrite.
      you.isStreaming = false;
    } else {
      you.isStreaming = true;
      you.streamTarget = _target;
      _updateBalance(_target);
      ubiAccounts[you.streamTarget].streamsReceived++;
    }

    return (previousStream);
  }

  // VIEWS (manual getters got UbiAccount and Counter)

  function getUbiAccount(address _owner) external view returns (UbiAccount memory) {
    return ubiAccounts[_owner];
  }

  function getCounter() external view returns (Counter memory) {
    return counter;
  }
}

// minting would be interesting, if by "governor"

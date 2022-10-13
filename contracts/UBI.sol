// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

  /* OldStorage */
  
  mapping (address => uint256) private oldBalance;

  mapping (address => mapping (address => uint256)) private oldAllowance;

  /// @dev A lower bound of the total supply. Does not take into account tokens minted as UBI by an address before it moves those (transfer or burn).
  uint256 private oldTotalSupply;
  
  /// @dev Name of the token.
  string private oldName;
  
  /// @dev Symbol of the token.
  string private oldSymbol;
  
  /// @dev Number of decimals of the token.
  uint8 private oldDecimals;

  /// @dev How many tokens per second will be minted for every valid human.
  uint256 private oldAccruedPerSecond;

  /// @dev The contract's governor.
  address private oldGovernor;
  
  /// @dev The Proof Of Humanity registry to reference.
  IProofOfHumanity private oldProofOfHumanity; 

  /// @dev Timestamp since human started accruing.
  mapping(address => uint256) private oldAccruedSince;

  /* Storage */

  /// @dev most info is contained in here.
  mapping (address => UbiAccount) internal ubiAccounts;

  /// @dev for ERC-20 allowances
  mapping (address => mapping (address => uint256)) public allowance;

  // just to keep track of the totalSupply.
  Counter internal counter;

  /// @dev Name of the token.
  string constant public name = "UBI";

  /// @dev Symbol of the token.
  string constant public symbol = "UBI";

  /// @dev Number of decimals of the token.
  uint8 constant public decimals = 7;

  /// @dev How many tokens per second will be minted for every valid human.
  uint256 constant public accruedPerSecond = 2778;

  /// @dev The Proof Of Humanity registry to reference.
  IProofOfHumanity constant public proofOfHumanity = IProofOfHumanity(0xc5e9ddebb09cd64dfacab4011a0d5cedaf7c9bdb);

  /// @dev The sUBI implementation (so that the streams are ERC-20s)
  IsUBI constant public sUBI = IsUBI(0x0); // todo fill in later

    /* Initializer */

  /** @dev Constructor.
  */
  function initialize() public initializer {
    counter.timestamp = uint32(block.timestamp);
  }

  function changeParams(IProofOfHumanity _proofOfHumanity, IsUBI _sUBI) external {
    require(msg.sender == governor, "Only governor");
    proofOfHumanity = _proofOfHumanity;
    sUBI = _sUBI;
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
    return uint256(ubiAccount.balance + (streams * accruedPerSecond *
      (block.timestamp - ubiAccount.accruedSince)));
  }

  function transfer(address _to, uint256 _value) public returns (bool success) {
    uint256 balance = balanceOf(msg.sender);
    require(balance >= _value, "Not enough balance");
    _transfer(balance, msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
    uint256 balance = balanceOf(_from);
    require(balance >= _value, "Not enough balance");
    require(allowance[_from][msg.sender] >= _value, "Not enough allowance");

    // update allowance first
    allowance[_from][msg.sender] -= _value;

    _transfer(balance, msg.sender, _to, _value);
    return true;
  }

  function approve(address _spender, uint256 _value) public returns (bool success) {
    allowance[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  function _transfer(uint256 _balance, address _from, address _to, uint256 _value) internal {
    // update your balances
    UbiAccount storage ownerAccount = ubiAccounts[_from];
    ownerAccount.balance = uint80(_balance - _value);
    ownerAccount.accruedSince = uint32(block.timestamp);
    // just increment reciever balance.
    ubiAccounts[_to].balance += uint80(_value);

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

  // mint function (intended for v1 v2 migration)

  function mint(address _recipient, uint256 _amount) external {
    require(msg.sender == governor, "Only governor");
    ubiAccounts[_recipient].balance += uint80(_amount);
    counter.hardSupply += uint80(_amount); // no need to update the other stuff, saves gas.

    emit Transfer(address(0), _recipient, _amount);
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
    // this transfer should let explorers about the token.
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

    // arguably it should do a poh check but this is cheaper.
    require(you.isHuman, "Not a registered human");

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

    emit Transfer(address(0), _target, 0);
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

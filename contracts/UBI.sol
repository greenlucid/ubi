// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/IUBI.sol";
import "./interfaces/IsUBI.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

contract UBI is IUBI, Initializable {

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

  /// @dev Nonces for permit function. Must be modified only through permit function, where is incremented only by one.
  mapping (address => uint256) public nonces;

  /// @dev Domain separator used for permit function.
  bytes32 public domainSeparator;

  // just to keep track of the totalSupply.
  Counter internal counter;

  /// @dev Name of the token.
  string constant public name = "UBI";

  /// @dev Symbol of the token.
  string constant public symbol = "UBI";

  /// @dev Number of decimals of the token.
  uint8 constant public decimals = 7;

  // decimals have changed so this is new ratio
  uint256 constant private v1v2Ratio = 100791936645;
  // todo set as the timestamp there will be when this contract is deployed.
  uint256 constant private v1DeathTime = 0; 

  /// @dev How many tokens per second will be minted for every valid human.
  uint256 constant public accruedPerSecond = 2778;

  /// @dev The Proof Of Humanity registry to reference.
  IProofOfHumanity constant public proofOfHumanity = IProofOfHumanity(0xC5E9dDebb09Cd64DfaCab4011A0D5cEDaf7c9BDb);

  /// @dev The sUBI implementation (so that the streams are ERC-20s)
  IsUBI constant public sUBI = IsUBI(address(0x0)); // todo fill in later

  bytes32 constant public permitTypehash = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  uint256 constant public chainId = 1; 

    /* Initializer */

  /** @dev Constructor.
  */
  function initialize() public initializer {
    counter.timestamp = uint32(block.timestamp);
    // we delete this stuff to trigger refunds and get a cheaper deployment
    delete oldTotalSupply;
    delete oldName;
    delete oldSymbol;
    delete oldDecimals;
    delete oldAccruedPerSecond;
    delete oldGovernor;
    delete oldProofOfHumanity; 
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

  function oldBalanceOf(address _owner) public view returns (uint256 amount) {
    if(oldAccruedSince[_owner] != 0 && proofOfHumanity.isRegistered(_owner)) {
      amount = accruedPerSecond * (v1DeathTime - oldAccruedSince[_owner]);
    }
  }

  function balanceOf(address _owner) public view returns (uint256 acc) {
    // todo optimize (remove memory?)
    UbiAccount memory ubiAccount = ubiAccounts[_owner];
    acc = ubiAccount.hasMigrated ? 0 : oldBalanceOf(_owner);
    uint256 streams = ubiAccount.streamsReceived;
    if (ubiAccount.isHuman && !ubiAccount.isStreaming) {
      streams++;
    }
    acc += uint256(ubiAccount.balance + (streams * accruedPerSecond *
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
    if (!ownerAccount.hasMigrated) _migrate(_from);
    ownerAccount.balance = uint80(_balance - _value);
    ownerAccount.accruedSince = uint32(block.timestamp);
    // just increment reciever balance.
    ubiAccounts[_to].balance += uint80(_value);
    // we purposedly not migrate receiver.

    emit Transfer(msg.sender, _to, _value);
  }

  function _migrate(address _human) internal {
    UbiAccount storage ubiAccount = ubiAccounts[_human];
    uint80 amount = uint80(oldBalanceOf(_human));
    counter.hardSupply += amount;
    ubiAccount.balance += amount;
    ubiAccount.hasMigrated = true;
    delete oldBalance[_human];
    delete oldAccruedSince[_human];
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

  function _updateCounter() internal {
    counter.hardSupply = uint80(totalSupply());
    counter.timestamp = uint32(block.timestamp);
  }

  function registerHuman(address _human) external {
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
    sUBI.registerHuman(_human);
  }

  function removeHuman(address _human) external {
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
    ubiAccounts[msg.sender].balance += uint80(reportReward);

    // the requires above enforce a human decrement.
    _updateCounter();
    counter.humanCount--;

    emit Transfer(previousStream, msg.sender, reportReward);
    sUBI.removeHuman(previousStream);
  }

  function streamToHuman(address _target) external {
    UbiAccount storage you = ubiAccounts[msg.sender];

    // arguably it should do a poh check but this is cheaper.
    require(you.isHuman, "Not a registered human");

    address previousStream;

    // first, check if you were streaming to someone. if so, stop it.
    if (you.isStreaming) {
      previousStream = you.streamTarget;
      _updateBalance(you.streamTarget);
      ubiAccounts[you.streamTarget].streamsReceived--;
    } else {
      previousStream = msg.sender;
    }

    // now, start the stream.
    _updateBalance(msg.sender);
    if (_target == msg.sender) {
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
    sUBI.streamToHuman(msg.sender, _target);
  }

  // VIEWS (manual getters got UbiAccount and Counter)

  function getUbiAccount(address _owner) external view returns (UbiAccount memory) {
    return ubiAccounts[_owner];
  }

  function getCounter() external view returns (Counter memory) {
    return counter;
  }

  /**
  * @dev Approves, through a message signed by the `_owner`, `_spender` to spend `_value` tokens from `_owner`.
  * @param _owner The address of the token owner.
  * @param _spender The address of the spender.
  * @param _value The amount of tokens to approve.
  * @param _deadline The expiration time until which the signature will be considered valid.
  * @param _v The signature v value.
  * @param _r The signature r value.
  * @param _s The signature s value.
  */
  function permit(address _owner, address _spender, uint256 _value, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) public {
    require(_owner != address(0), "ERC20Permit: invalid owner");
    require(block.timestamp <= _deadline, "ERC20Permit: expired deadline");
    bytes32 structHash = keccak256(abi.encode(permitTypehash, _owner, _spender, _value, nonces[_owner], _deadline));
    if (_getCurrentChainId() != chainId) {
      domainSeparator = _buildDomainSeparator();
    }
    bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    address signer = ECDSA.recover(hash, _v, _r, _s);
    require(signer == _owner, "ERC20Permit: invalid signature");
    // Must be modified only here. Doesn't need SafeMath because can't reach overflow if incremented only here by one.
    // See: https://www.schneier.com/blog/archives/2009/09/the_doghouse_cr.html
    nonces[_owner]++;
    allowance[_owner][_spender] = _value;
    emit Approval(_owner, _spender, _value);
  }

  /**
  * @dev Builds and returns the domain separator used in the encoding of the signature for `permit` using the current
  * chain id.
  */
  function _buildDomainSeparator() internal view returns (bytes32) {
    string memory version = "2";
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(name)),
        keccak256(bytes(version)),
        _getCurrentChainId(),
        address(this)
      )
    ); 
  }

  /**
  * @dev Returns the current chain id.
  */
  function _getCurrentChainId() internal view returns (uint256 currentChainId) {
    assembly {
      currentChainId := chainid()
    }
  }
}

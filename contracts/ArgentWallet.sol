//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import { IArgentWallet } from "./IArgentWallet.sol";
import { UserOperation, UserOperationLib } from "./lib/UserOperation.sol";

contract ArgentWallet is IArgentWallet {

    using UserOperationLib for UserOperation;

    uint256 public constant ESCAPE_SECURITY_PERIOD = 1 weeks;
    bytes4 public constant CHANGE_SIGNER_SELECTOR = bytes4(keccak256("changeSigner(address,bytes,bytes,uint256)"));
    bytes4 public constant CHANGE_GUARDIAN_SELECTOR = bytes4(keccak256("changeGuardian(address,bytes,bytes,uint256)"));
    bytes4 public constant TRIGGER_ESCAPE_SELECTOR = bytes4(keccak256("triggerEscape(address,bytes,uint256)"));
    bytes4 public constant CANCEL_ESCAPE_SELECTOR = bytes4(keccak256("cancelEscape(bytes,bytes,uint256)"));
    bytes4 public constant ESCAPE_SIGNER_SELECTOR = bytes4(keccak256("escapeSigner(address,bytes,uint256)"));
    bytes4 public constant ESCAPE_GUARDIAN_SELECTOR = bytes4(keccak256("escapeGuardian(address,bytes,uint256)"));

    SignerNonce public signerNonce;
    address public guardian;
    Escape public escape;

    address public entryPoint;

    constructor(address _signer, address _guardian, address _entryPoint) {
        signerNonce.signer = _signer;
        guardian = _guardian;
        entryPoint = _entryPoint;
    }

    function nonce() public view returns (uint) {
        return signerNonce.nonce;
    }

    function signer() public view returns(address) {
        return signerNonce.signer;
    }

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    )
        external
        returns (bool success)
    {
        require(_to != address(0), "null _to");

        bytes32 signedHash = getSignedHash(_to, _value, _data, _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        (success,) = _to.call{value: _value}(_data);
        require(success, "execution failed");
    }

    function changeSigner(
        address _newSigner,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    )
        external
    {
        require(_newSigner != address(0), "null _newSigner");

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(CHANGE_SIGNER_SELECTOR, _newSigner), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        signerNonce.signer = _newSigner;
    }

    function changeGuardian(
        address _newGuardian,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    )
        external
    {
        require(_newGuardian != address(0), "null _newGuardian");

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(CHANGE_GUARDIAN_SELECTOR, _newGuardian), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        guardian = _newGuardian;
    }

    function triggerEscape(address _escaper, bytes calldata _signature, uint256 _nonce) external {
        require(_escaper != address(0), "null _escaper");

        if (escape.activeAt != 0) {
            require(escape.caller == guardian, "invalid escape.caller");
            require(_escaper == signer(), "invalid _escaper");
        }

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(TRIGGER_ESCAPE_SELECTOR, _escaper), _nonce);

        if (_escaper == signer()) {
            validateSignerSignature(signedHash, _signature);
        } else {
            validateGuardianSignature(signedHash, _signature);
        }

        escape = Escape(uint96(block.timestamp + ESCAPE_SECURITY_PERIOD), _escaper);
    }

    function cancelEscape(bytes calldata _signerSignature, bytes calldata _guardianSignature, uint256 _nonce) external {
        require(escape.activeAt != 0 && escape.caller != address(0), "not escaping");
        // or?
        // require(escape.activeAt <= block.timestamp, "not escaping");

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(CANCEL_ESCAPE_SELECTOR), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        delete escape;
    }

    function escapeSigner(address _newSigner, bytes calldata _guardianSignature, uint256 _nonce) external {
        require(_newSigner != address(0), "null _newSigner");
        require(escape.caller == guardian, "invalid escape.caller");
        require(escape.activeAt <= block.timestamp, "no active escape");

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(ESCAPE_SIGNER_SELECTOR, _newSigner), _nonce);
        validateGuardianSignature(signedHash, _guardianSignature);

        signerNonce.signer = _newSigner;
        delete escape;
    }

    function escapeGuardian(address _newGuardian, bytes calldata _signerSignature, uint256 _nonce) external {
        require(_newGuardian != address(0), "null _newGuardian");
        require(escape.caller == signer(), "invalid escape.signer");
        require(escape.activeAt <= block.timestamp, "no active escape");

        bytes32 signedHash = getSignedHash(address(this), 0, abi.encodePacked(ESCAPE_GUARDIAN_SELECTOR, _newGuardian), _nonce);
        validateSignerSignature(signedHash, _signerSignature);

        guardian = _newGuardian;
        delete escape;
    }

    // AA

    modifier onlySigner() {
        // directly from signer key, or through the entryPoint (which gets redirected through execFromEntryPoint)
        require(msg.sender == signer() || msg.sender == address(this), "only signer");
        _;
    }

    function updateEntryPoint(address _entryPoint) external onlySigner {
        emit EntryPointChanged(entryPoint, _entryPoint);
        entryPoint = _entryPoint;
    }

    function _requireFromEntryPoint() internal view {
        require(msg.sender == address(entryPoint), "wallet: not from EntryPoint");
    }

    function verifyUserOp(UserOperation calldata userOp, uint requiredPrefund) external override {
        _requireFromEntryPoint();
        _validateSignature(userOp);
        _validateAndIncrementNonce(userOp);
        _payPrefund(requiredPrefund);
    }

    function _validateSignature(UserOperation calldata userOp) internal view {
        bytes4 selector = bytes4(userOp.callData);
        bytes32 signedHash = userOp.hash();

        if (selector == CHANGE_SIGNER_SELECTOR) {
            bytes calldata _signerSignature = userOp.signature[:65];
            bytes calldata _guardianSignature = userOp.signature[65:130];
            validateSignatures(signedHash, _signerSignature, _guardianSignature);
        }
    }

    function _validateAndIncrementNonce(UserOperation calldata userOp) internal {
        //during construction, the "nonce" field hold the salt.
        // if we assert it is zero, then we allow only a single wallet per owner.
        if (userOp.initCode.length == 0) {
            require(signerNonce.nonce++ == userOp.nonce, "wallet: invalid nonce");
        }
    }

    function _payPrefund(uint requiredPrefund) internal {
        if (requiredPrefund != 0) {
            (bool success) = payable(msg.sender).send(requiredPrefund);
            (success);
            //ignore failure (its EntryPoint's job to verify, not wallet.)
        }
    }

    function exec(address dest, uint value, bytes calldata func) external onlySigner {
        _call(dest, value, func);
    }

    //called by entryPoint, only after verifyUserOp succeeded.
    function execFromEntryPoint(address dest, uint value, bytes calldata func) external {
        _requireFromEntryPoint();
        _call(dest, value, func);
    }

    function _call(address sender, uint value, bytes memory data) internal {
        (bool success, bytes memory result) = sender.call{value : value}(data);
        if (!success) {
            assembly {
                revert(result, add(result, 32))
            }
        }
    }

    // public 

    function getSignedMessage(address _to, uint256 _value, bytes memory _data, uint256 _nonce) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_to, _value, _data, _nonce, block.chainid));
    }

    // internal

    function getSignedHash(address _to, uint256 _value, bytes memory _data, uint256 _nonce) internal view returns (bytes32) {
        bytes32 message = getSignedMessage(_to, _value, _data, _nonce);
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
    }

    function validateSignatures(
        bytes32 _signedHash,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature
    ) 
        internal 
        view
    {
        validateSignature(_signedHash, _signerSignature, signer());
        validateSignature(_signedHash, _guardianSignature, guardian);
    }

    function validateSignerSignature(bytes32 _signedHash, bytes calldata _signature) internal view {
        validateSignature(_signedHash, _signature, signer());
    }

    function validateGuardianSignature(bytes32 _signedHash, bytes calldata _signature) internal view {
        validateSignature(_signedHash, _signature, guardian);
    }

    function validateSignature(bytes32 _signedHash, bytes calldata _signature, address _account) internal pure {
        require(_signature.length == 65, "invalid signature length");

        uint8 v;
        bytes32 r;
        bytes32 s;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := calldataload(_signature.offset)
            s := calldataload(add(_signature.offset, 0x20))
            v := byte(0, calldataload(add(_signature.offset, 0x40)))
        }

        require(_account == ecrecover(_signedHash, v, r, s), "invalid signature");
    }

    receive() external payable {

    }
}

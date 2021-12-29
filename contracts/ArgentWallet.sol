//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import { IArgentWallet } from "./IArgentWallet.sol";
import { UserOperation, UserOperationLib } from "./lib/UserOperation.sol";

contract ArgentWallet is IArgentWallet {

    using UserOperationLib for UserOperation;

    uint256 public constant ESCAPE_SECURITY_PERIOD = 1 weeks;
    bytes4 public constant CHANGE_SIGNER_SELECTOR = bytes4(keccak256("changeSigner(address)"));
    bytes4 public constant CHANGE_GUARDIAN_SELECTOR = bytes4(keccak256("changeGuardian(address)"));
    bytes4 public constant TRIGGER_ESCAPE_SELECTOR = bytes4(keccak256("triggerEscape(address)"));
    bytes4 public constant CANCEL_ESCAPE_SELECTOR = bytes4(keccak256("cancelEscape()"));
    bytes4 public constant ESCAPE_SIGNER_SELECTOR = bytes4(keccak256("escapeSigner(address)"));
    bytes4 public constant ESCAPE_GUARDIAN_SELECTOR = bytes4(keccak256("escapeGuardian(address)"));

    SignerNonce public signerNonce;
    address internal guardian_;
    Escape public escape;

    address public entryPoint;

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    modifier onlySigner() {
        // directly from signer key, or through the entryPoint (which gets redirected through execFromEntryPoint)
        require(msg.sender == signer() || msg.sender == address(this), "only signer");
        _;
    }

    constructor(address _signer, address _guardian, address _entryPoint) {
        signerNonce.signer = _signer;
        guardian_ = _guardian;
        entryPoint = _entryPoint;
    }

    function nonce() public view returns (uint) {
        return signerNonce.nonce;
    }

    function signer() public view returns (address) {
        return signerNonce.signer;
    }

    function guardian() public view returns (address) {
        return guardian_;
    }

    // Social recovery

    function changeSigner(address _newSigner) public onlySelf {
        require(_newSigner != address(0), "null _newSigner");
        signerNonce.signer = _newSigner;
    }

    function changeGuardian(address _newGuardian) public onlySelf {
        require(_newGuardian != address(0), "null _newGuardian");
        guardian_ = _newGuardian;
    }

    function triggerEscape(address _escaper) public onlySelf {
        require(_escaper == signer() || _escaper == guardian(), "null _escaper");

        if (escape.activeAt != 0) {
            require(escape.caller == guardian(), "invalid escape.caller");
            require(_escaper == signer(), "invalid _escaper");
        }

        escape = Escape(uint96(block.timestamp + ESCAPE_SECURITY_PERIOD), _escaper);
    }

    function cancelEscape() public onlySelf {
        require(escape.activeAt != 0 && escape.caller != address(0), "not escaping");
        // or?
        // require(escape.activeAt <= block.timestamp, "not escaping");

        delete escape;
    }

    function escapeSigner(address _newSigner) public onlySelf {
        require(_newSigner != address(0), "null _newSigner");
        require(escape.caller == guardian(), "invalid escape.caller");
        require(escape.activeAt <= block.timestamp, "no active escape");

        signerNonce.signer = _newSigner;
        delete escape;
    }

    function escapeGuardian(address _newGuardian) public onlySelf {
        require(_newGuardian != address(0), "null _newGuardian");
        require(escape.caller == signer(), "invalid escape.signer");
        require(escape.activeAt <= block.timestamp, "no active escape");

        guardian_ = _newGuardian;
        delete escape;
    }

    // AA

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
        bytes4 selector = bytes4(userOp.callData[128+4: 128+8]);
        bytes32 signedHash = userOp.hash();

        if (selector == TRIGGER_ESCAPE_SELECTOR) {
            revert("not implemented");
            // TODO: validate signer OR guardian and determine which it is
        } else if (selector == ESCAPE_GUARDIAN_SELECTOR) {
            bytes calldata _signerSignature = userOp.signature[:65];
            validateSignerSignature(signedHash, _signerSignature);
        } else if (selector == ESCAPE_SIGNER_SELECTOR) {
            bytes calldata _guardianSignature = userOp.signature[65:130];
            validateGuardianSignature(signedHash, _guardianSignature);
        } else {
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
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(result, add(result, 32))
            }
        }
    }

    // Signature checking 

    function validateSignatures(
        bytes32 _signedHash,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature
    ) 
        internal 
        view
    {
        validateSignature(_signedHash, _signerSignature, signer());
        validateSignature(_signedHash, _guardianSignature, guardian());
    }

    function validateSignerSignature(bytes32 _signedHash, bytes calldata _signature) internal view {
        validateSignature(_signedHash, _signature, signer());
    }

    function validateGuardianSignature(bytes32 _signedHash, bytes calldata _signature) internal view {
        validateSignature(_signedHash, _signature, guardian());
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

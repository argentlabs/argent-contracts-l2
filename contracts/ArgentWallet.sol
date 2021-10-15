//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import { IArgentWallet } from "./IArgentWallet.sol";

contract ArgentWallet is IArgentWallet {

    uint256 public constant ESCAPE_SECURITY_PERIOD = 1 weeks;
    bytes4 public constant CHANGE_SIGNER_SELECTOR = bytes4(keccak256("changeSigner(address,bytes,bytes,uint256)"));
    bytes4 public constant CHANGE_GUARDIAN_SELECTOR = bytes4(keccak256("changeGuardian(address,bytes,bytes,uint256)"));
    bytes4 public constant CHANGE_L1_ADDRESS_SELECTOR = bytes4(keccak256("changeL1Address(address,bytes,bytes,uint256)"));
    bytes4 public constant TRIGGER_ESCAPE_SELECTOR = bytes4(keccak256("triggerEscape(address,bytes,uint256)"));
    bytes4 public constant CANCEL_ESCAPE_SELECTOR = bytes4(keccak256("cancelEscape(bytes,bytes,uint256)"));
    bytes4 public constant ESCAPE_SIGNER_SELECTOR = bytes4(keccak256("escapeSigner(address,bytes,uint256)"));
    bytes4 public constant ESCAPE_GUARDIAN_SELECTOR = bytes4(keccak256("escapeGuardian(address,bytes,uint256)"));

    uint256 public nonce = 0;
    address public signer;
    address public guardian;
    address public l1Address;
    Escape public escape = Escape(0, address(0));

    constructor(address _signer, address _guardian, address _l1Address) {
        signer = _signer;
        guardian = _guardian;
        l1Address = _l1Address;
    }

    function execute(
        address _to,
        bytes calldata _data,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    )
        external
        returns (bool success)
    {
        require(_to != address(0), "null _to");
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(_to, bytes4(_data[:4]), _data[4:], _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        (success,) = _to.call(_data);
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
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), CHANGE_SIGNER_SELECTOR, abi.encodePacked(_newSigner), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        signer = _newSigner;
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
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), CHANGE_GUARDIAN_SELECTOR, abi.encodePacked(_newGuardian), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        guardian = _newGuardian;
    }

    function changeL1Address(
        address _newL1Address,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    )
        external
    {
        require(_newL1Address != address(0), "null _newL1Address");
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), CHANGE_GUARDIAN_SELECTOR, abi.encodePacked(_newL1Address), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        l1Address = _newL1Address;
    }

    function triggerEscape(address _escaper, bytes calldata _signature, uint256 _nonce) external {
        require(_escaper != address(0), "null _escaper");
        validateAndBumpNonce(_nonce);

        if (escape.activeAt != 0) {
            require(escape.caller == guardian, "invalid escape.caller");
            require(_escaper == signer, "invalid _escaper");
        }

        bytes32 signedHash = getSignedHash(address(this), TRIGGER_ESCAPE_SELECTOR, abi.encodePacked(_escaper), _nonce);

        if (_escaper == signer) {
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
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), CANCEL_ESCAPE_SELECTOR, abi.encodePacked(""), _nonce);
        validateSignatures(signedHash, _signerSignature, _guardianSignature);

        escape = Escape(0, address(0));
    }

    function escapeSigner(address _newSigner, bytes calldata _guardianSignature, uint256 _nonce) external {
        require(_newSigner != address(0), "null _newSigner");
        require(escape.activeAt <= block.timestamp, "no active escape");
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), ESCAPE_SIGNER_SELECTOR, abi.encodePacked(_newSigner), _nonce);
        validateGuardianSignature(signedHash, _guardianSignature);

        signer = _newSigner;
        escape = Escape(0, address(0));
    }

    function escapeGuardian(address _newGuardian, bytes calldata _signerSignature, uint256 _nonce) external {
        require(_newGuardian != address(0), "null _newGuardian");
        require(escape.activeAt <= block.timestamp, "no active escape");
        validateAndBumpNonce(_nonce);

        bytes32 signedHash = getSignedHash(address(this), ESCAPE_GUARDIAN_SELECTOR, abi.encodePacked(_newGuardian), _nonce);
        validateSignerSignature(signedHash, _signerSignature);

        guardian = _newGuardian;
        escape = Escape(0, address(0));
    }

    // public 

    function getSignedMessage(address _to, bytes4 _selector, bytes memory _data, uint256 _nonce) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_to, _selector, _data, _nonce, block.chainid));
    }

    // internal

    function getSignedHash(address _to, bytes4 _selector, bytes memory _data, uint256 _nonce) internal view returns (bytes32) {
        bytes32 message = getSignedMessage(_to, _selector, _data, _nonce);
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
    }

    function validateAndBumpNonce(uint256 _messageNonce) internal {
        require(_messageNonce == nonce, "invalid nonce");
        nonce += 1;
    }

    function validateSignatures(
        bytes32 _signedHash,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature
    ) 
        internal 
        view
    {
        validateSignature(_signedHash, _signerSignature, signer);
        validateSignature(_signedHash, _guardianSignature, guardian);
    }

    function validateSignerSignature(bytes32 _signedHash, bytes calldata _signature) internal view {
        validateSignature(_signedHash, _signature, signer);
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
            v := byte(0, calldataload(add(_signature.offset, 0x40)))
            r := calldataload(_signature.offset)
            s := calldataload(add(_signature.offset, 0x20))
        }

        require(_account == ecrecover(_signedHash, v, r, s), "invalid signature");
    }
}
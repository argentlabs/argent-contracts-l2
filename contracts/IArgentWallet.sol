// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.8;

interface IArgentWallet {

    struct Escape {
        uint96 activeAt; // timestamp for activation of escape mode, 0 otherwise
        address caller;
    }

    function signer() external view returns (address);
    function guardian() external view returns (address);
    function l1Address() external view returns (address);

    function execute(
        address _to,
        bytes calldata _data,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    ) external returns (bool success);
    

    function changeSigner(
        address _newSigner,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    ) external;

    function changeGuardian(
        address _newGuardian,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    ) external;

    function changeL1Address(
        address _newL1Address,
        bytes calldata _signerSignature,
        bytes calldata _guardianSignature,
        uint256 _nonce
    ) external;

    function triggerEscape(address _escaper, bytes calldata _signature, uint256 _nonce) external;

    function cancelEscape(bytes calldata _signerSignature, bytes calldata _guardianSignature, uint256 _nonce) external;

    function escapeSigner(address _newSigner, bytes calldata _guardianSignature, uint256 _nonce) external;

    function escapeGuardian(address _newGuardian, bytes calldata _signerSignature, uint256 _nonce) external;

}
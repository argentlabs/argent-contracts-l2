// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import { IWallet } from "./lib/IWallet.sol";

interface IArgentWallet is IWallet {

    struct SignerNonce {
        uint96 nonce;
        address signer;
    }

    struct Escape {
        uint96 activeAt; // timestamp for activation of escape mode, 0 otherwise
        address caller;
    }

    event EntryPointChanged(address oldEntryPoint, address newEntryPoint);

    function signer() external view returns (address);
    function guardian() external view returns (address);
}
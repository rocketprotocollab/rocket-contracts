// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IMeme} from "./IMeme.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Meme is IMeme, ERC20 {
    string public override meta;

    constructor(
        string memory name,
        string memory symbol,
        string memory _meta) ERC20(name, symbol) {
        meta = _meta;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
    }
}
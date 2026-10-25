// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed supply of one billion MAD, with 18 decimals, minted once to the deployer.
/// @dev When created by a factory, the factory receives the entire supply. There are no admin roles.
contract MADToken is ERC20 {
    /// @notice The complete supply in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Mutually Assured Destruction", "MAD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Test-only closed population. A separate ledger tracks balances and allowances across calls.
contract MADTokenHandler is Test {
    MADToken public immutable token;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(MADToken token_) {
        token = token_;
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include unlimited approvals, replacement and revocation alongside ordinary amounts.
        if (amount % 7 == 0) amount = type(uint256).max;
        else if (amount % 7 == 1) amount = 0;
        // Other values remain unrestricted: approvals can exceed the entire supply.
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    /// @dev Guarantees positive delegated transfers even before random approvals line up.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool unlimited)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (!unlimited) expectedAllowance[owner][spender] = 0;
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost updates: the invariants must still match the entire pre-call ledger.
    }

    function rejectTransferFromOverAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 approvalSeed,
        uint256 amountSeed
    ) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 approval = bound(approvalSeed, 0, balance - 1);
        uint256 amount = bound(amountSeed, approval + 1, balance);
        _approve(owner, spender, approval);
        // The balance suffices, isolating the missing authorization as the failure.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 excess,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, spending allowance before the balance check must roll back.
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) {
            if (expectedAllowance[owner][spender] < amount) _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (expectedBalance[actor] > 0) return actor;
        }
        // This is a harness failure, not a silently skipped action: supply is nonzero.
        revert("no funded actor in the closed ledger");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract MADTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    MADToken private token;
    MADTokenHandler private handler;

    function setUp() public {
        token = new MADToken();
        handler = new MADTokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = MADTokenHandler.transfer.selector;
        selectors[1] = MADTokenHandler.approve.selector;
        selectors[2] = MADTokenHandler.transferFrom.selector;
        selectors[3] = MADTokenHandler.approveAndSpend.selector;
        selectors[4] = MADTokenHandler.rejectTransferOverBalance.selector;
        selectors[5] = MADTokenHandler.rejectTransferFromOverAllowance.selector;
        selectors[6] = MADTokenHandler.rejectTransferFromOverBalance.selector;
        selectors[7] = MADTokenHandler.rejectZeroRecipient.selector;
        selectors[8] = MADTokenHandler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndExactBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchAuthorizationsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_metadataRemainsUnchanged() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev Pins every handler action to a concrete sequence with nonzero successful spending.
    function test_handlerFailuresDoNotPreventLaterSpending() public {
        handler.transfer(0, 1, 100);
        handler.approve(1, 2, 9);
        handler.transferFrom(1, 2, 3, 4);
        assertEq(token.balanceOf(handler.actors(3)), 4);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 5);

        handler.rejectTransferOverBalance(1, 3, 1);
        handler.rejectTransferFromOverAllowance(1, 2, 3, 5, 6);
        handler.rejectTransferFromOverBalance(1, 2, 3, 1, false);
        handler.rejectZeroRecipient(1, 2, 1, true);
        handler.rejectZeroRecipient(1, 2, 1, false);
        handler.rejectZeroSpender(1, type(uint256).max);
        invariant_fixedSupplyAndExactBalances();
        invariant_allowancesMatchAuthorizationsAndSpending();

        handler.transferFrom(1, 2, 3, 96);
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(3)), 100);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 1);
        handler.approveAndSpend(3, 2, 1, 100, true);
        assertEq(token.balanceOf(handler.actors(1)), 100);
        assertEq(token.balanceOf(handler.actors(3)), 0);
        assertEq(token.allowance(handler.actors(3), handler.actors(2)), type(uint256).max);
        invariant_fixedSupplyAndExactBalances();
        invariant_allowancesMatchAuthorizationsAndSpending();
        invariant_metadataRemainsUnchanged();
    }
}
